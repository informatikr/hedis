{-# LANGUAGE CPP, OverloadedStrings, RecordWildCards, EmptyDataDecls,
    FlexibleInstances, FlexibleContexts, GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ScopedTypeVariables, TupleSections, ConstraintKinds #-}

module Database.Redis.PubSub (
    publish,

    -- ** Subscribing to channels
    -- $pubsubexpl

    -- *** Single-thread Pub/Sub
    pubSub,
    Message(..),
    PubSub(),
    subscribe, unsubscribe, psubscribe, punsubscribe,
    -- *** Continuous Pub/Sub message controller
    pubSubForever,
    RedisChannel, RedisPChannel, MessageCallback, PMessageCallback,
    PubSubController, newPubSubController, currentChannels, currentPChannels,
    addChannels, addChannelsAndWait, removeChannels, removeChannelsAndWait,
    UnregisterCallbacksAction,
    pendingChannels, pendingPatternChannels
) where

#if __GLASGOW_HASKELL__ < 710
import Control.Applicative
import Data.Monoid hiding (<>)
#endif
import Control.Arrow (second)
import Control.Concurrent.Async (withAsync, waitEitherCatch, waitEitherCatchSTM)
import Control.Concurrent.STM
import Control.Exception (throwIO)
import Control.Monad
import Control.Monad.State
import Data.ByteString.Char8 (ByteString)
import Data.List (foldl')
import Data.Maybe (isJust)
import Data.Pool
#if __GLASGOW_HASKELL__ < 808
import Data.Semigroup (Semigroup(..))
#endif
import Data.Hashable (Hashable)
import qualified Data.HashMap.Strict as HM
import qualified Data.HashSet as HS
import qualified Database.Redis.Core as Core
import qualified Database.Redis.Connection as Connection
import qualified Database.Redis.ProtocolPipelining as PP
import Database.Redis.Protocol (Reply(..), renderRequest)
import Database.Redis.Types

-- |While in PubSub mode, we keep track of the number of current subscriptions
--  (as reported by Redis replies) and the number of messages we expect to
--  receive after a SUBSCRIBE or PSUBSCRIBE command. We can safely leave the
--  PubSub mode when both these numbers are zero.
data PubSubState = PubSubState { subCnt, pending :: Int }

modifyPending :: (MonadState PubSubState m) => (Int -> Int) -> m ()
modifyPending f = modify $ \s -> s{ pending = f (pending s) }

putSubCnt :: (MonadState PubSubState m) => Int -> m ()
putSubCnt n = modify $ \s -> s{ subCnt = n }

data Subscribe
data Unsubscribe
data Channel
data Pattern

-- |Encapsulates subscription changes. Use 'subscribe', 'unsubscribe',
--  'psubscribe', 'punsubscribe' or 'mempty' to construct a value. Combine
--  values by using the 'Monoid' interface, i.e. 'mappend' and 'mconcat'.
data PubSub = PubSub
    { subs    :: Cmd Subscribe Channel
    , unsubs  :: Cmd Unsubscribe Channel
    , psubs   :: Cmd Subscribe Pattern
    , punsubs :: Cmd Unsubscribe Pattern
    } deriving (Eq)

instance Semigroup PubSub where
    (<>) p1 p2 = PubSub { subs    = subs p1 `mappend` subs p2
                           , unsubs  = unsubs p1 `mappend` unsubs p2
                           , psubs   = psubs p1 `mappend` psubs p2
                           , punsubs = punsubs p1 `mappend` punsubs p2
                           }

instance Monoid PubSub where
    mempty        = PubSub mempty mempty mempty mempty
    mappend = (<>)

data Cmd a b = DoNothing | Cmd { changes :: [ByteString] } deriving (Eq)

instance Semigroup (Cmd Subscribe a) where
  (<>) DoNothing x = x
  (<>) x DoNothing = x
  (<>) (Cmd xs) (Cmd ys) = Cmd (xs ++ ys)

instance Monoid (Cmd Subscribe a) where
  mempty = DoNothing
  mappend = (<>)

instance Semigroup (Cmd Unsubscribe a) where
  (<>) DoNothing x = x
  (<>) x DoNothing = x
  -- empty subscription list => unsubscribe all channels and patterns
  (<>) (Cmd []) _ = Cmd []
  (<>) _ (Cmd []) = Cmd []
  (<>) (Cmd xs) (Cmd ys) = Cmd (xs ++ ys)

instance Monoid (Cmd Unsubscribe a) where
  mempty = DoNothing
  mappend = (<>)

class Command a where
    redisCmd      :: a -> ByteString
    updatePending :: a -> Int -> Int

sendCmd :: (Command (Cmd a b)) => Cmd a b -> StateT PubSubState Core.Redis ()
sendCmd DoNothing = return ()
sendCmd cmd       = do
    lift $ Core.send (redisCmd cmd : changes cmd)
    modifyPending (updatePending cmd)

rawSendCmd :: (Command (Cmd a b)) => PP.Connection -> Cmd a b -> IO ()
rawSendCmd _ DoNothing = return ()
rawSendCmd conn cmd    = PP.send conn $ renderRequest $ redisCmd cmd : changes cmd

plusChangeCnt :: Cmd a b -> Int -> Int
plusChangeCnt DoNothing = id
plusChangeCnt (Cmd cs)  = (+ length cs)

instance Command (Cmd Subscribe Channel) where
    redisCmd      = const "SUBSCRIBE"
    updatePending = plusChangeCnt

instance Command (Cmd Subscribe Pattern) where
    redisCmd      = const "PSUBSCRIBE"
    updatePending = plusChangeCnt

instance Command (Cmd Unsubscribe Channel) where
    redisCmd      = const "UNSUBSCRIBE"
    updatePending = const id

instance Command (Cmd Unsubscribe Pattern) where
    redisCmd      = const "PUNSUBSCRIBE"
    updatePending = const id


data Message = Message  { msgChannel, msgMessage :: ByteString}
             | PMessage { msgPattern, msgChannel, msgMessage :: ByteString}
    deriving (Show)

data PubSubReply
    = Subscribed RedisChannel
    | PSubscribed RedisPChannel
    | Unsubscribed RedisChannel Int
    | PUnsubscribed RedisPChannel Int
    | Msg Message


------------------------------------------------------------------------------
-- Public Interface
--

-- |Post a message to a channel (<http://redis.io/commands/publish>).
publish
    :: (Core.RedisCtx m f)
    => ByteString -- ^ channel
    -> ByteString -- ^ message
    -> m (f Integer)
publish channel message =
    Core.sendRequest ["PUBLISH", channel, message]

-- |Listen for messages published to the given channels
--  (<http://redis.io/commands/subscribe>).
subscribe
    :: [ByteString] -- ^ channel
    -> PubSub
subscribe [] = mempty
subscribe cs = mempty{ subs = Cmd cs }

-- |Stop listening for messages posted to the given channels
--  (<http://redis.io/commands/unsubscribe>).
unsubscribe
    :: [ByteString] -- ^ channel
    -> PubSub
unsubscribe [] = mempty
unsubscribe cs = mempty{ unsubs = Cmd cs }

-- |Listen for messages published to channels matching the given patterns
--  (<http://redis.io/commands/psubscribe>).
psubscribe
    :: [ByteString] -- ^ pattern
    -> PubSub
psubscribe [] = mempty
psubscribe ps = mempty{ psubs = Cmd ps }

-- |Stop listening for messages posted to channels matching the given patterns
--  (<http://redis.io/commands/punsubscribe>).
punsubscribe
    :: [ByteString] -- ^ pattern
    -> PubSub
punsubscribe [] = mempty
punsubscribe ps = mempty{ punsubs = Cmd ps }

-- |Listens to published messages on subscribed channels and channels matching
--  the subscribed patterns. For documentation on the semantics of Redis
--  Pub\/Sub see <http://redis.io/topics/pubsub>.
--
--  The given callback function is called for each received message.
--  Subscription changes are triggered by the returned 'PubSub'. To keep
--  subscriptions unchanged, the callback can return 'mempty'.
--
--  Example: Subscribe to the \"news\" channel indefinitely.
--
--  @
--  pubSub (subscribe [\"news\"]) $ \\msg -> do
--      putStrLn $ \"Message from \" ++ show (msgChannel msg)
--      return mempty
--  @
--
--  Example: Receive a single message from the \"chat\" channel.
--
--  @
--  pubSub (subscribe [\"chat\"]) $ \\msg -> do
--      putStrLn $ \"Message from \" ++ show (msgChannel msg)
--      return $ unsubscribe [\"chat\"]
--  @
--
-- It should be noted that Redis Pub\/Sub by its nature is asynchronous
-- so returning `unsubscribe` does not mean that callback won't be able
-- to receive any further messages. And to guarantee that you won't
-- won't process messages after unsubscription and won't unsubscribe
-- from the same channel more than once you need to use `IORef` or
-- something similar
--
pubSub
    :: PubSub                 -- ^ Initial subscriptions.
    -> (Message -> IO PubSub) -- ^ Callback function.
    -> Core.Redis ()
pubSub initial callback
    | initial == mempty = return ()
    | otherwise         = evalStateT (send initial) (PubSubState 0 0)
  where
    send :: PubSub -> StateT PubSubState Core.Redis ()
    send PubSub{..} = do
        sendCmd subs
        sendCmd unsubs
        sendCmd psubs
        sendCmd punsubs
        recv

    recv :: StateT PubSubState Core.Redis ()
    recv = do
        reply <- lift Core.recv
        case decodeMsg reply of
            Msg msg           -> liftIO (callback msg) >>= send
            Subscribed _      -> modifyPending (subtract 1) >> recv
            PSubscribed _     -> modifyPending (subtract 1) >> recv
            PUnsubscribed _ n -> onUnsubscribe n
            Unsubscribed _ n  -> onUnsubscribe n

    onUnsubscribe :: Int -> StateT PubSubState Core.Redis ()
    onUnsubscribe n = do
        putSubCnt n
        PubSubState{..} <- get
        unless (subCnt == 0 && pending == 0) recv

-- | A Redis channel name
type RedisChannel = ByteString

-- | A Redis pattern channel name
type RedisPChannel = ByteString

-- | A handler for a message from a subscribed channel.
-- The callback is passed the message content.
--
-- Messages are processed synchronously in the receiving thread, so if the callback
-- takes a long time it will block other callbacks and other messages from being
-- received.  If you need to move long-running work to a different thread, we suggest
-- you use 'TBQueue' with a reasonable bound, so that if messages are arriving faster
-- than you can process them, you do eventually block.
--
-- If the callback throws an exception, the exception will be thrown from 'pubSubForever'
-- which will cause the entire Redis connection for all subscriptions to be closed.
-- As long as you call 'pubSubForever' in a loop you will reconnect to your subscribed
-- channels, but you should probably add an exception handler to each callback to
-- prevent this.
type MessageCallback = ByteString -> IO ()

-- | A handler for a message from a psubscribed channel.
-- The callback is passed the channel the message was sent on plus the message content.
--
-- Similar to 'MessageCallback', callbacks are executed synchronously and any exceptions
-- are rethrown from 'pubSubForever'.
type PMessageCallback = RedisChannel -> ByteString -> IO ()

-- | An action that when executed will unregister the callbacks.  It is returned from 'addChannels'
-- or 'addChannelsAndWait' and typically you would use it in 'bracket' to guarantee that you
-- unsubscribe from channels.  For example, if you are using websockets to distribute messages to
-- clients, you could use something such as:
--
-- > websocketConn <- Network.WebSockets.acceptRequest pending
-- > let mycallback msg = Network.WebSockets.sendTextData websocketConn msg
-- > bracket (addChannelsAndWait ctrl [("hello", mycallback)] []) id $ const $ do
-- >   {- loop here calling Network.WebSockets.receiveData -}
type UnregisterCallbacksAction = IO ()

newtype UnregisterHandle = UnregisterHandle Integer
  deriving (Eq, Show, Num)

-- | Stores channels subscribed, pending subscription, and pending removal
-- by type, where type can be a normal channel, or a pattern channel.
data ChannelData channel callback
    = ChannelData
    { cdSubscribedChannels :: !(TVar (HM.HashMap channel [(UnregisterHandle, callback)]))
    , cdChannelsPendingSubscription :: !(TVar (HS.HashSet channel))
    , cdChannelsPendingRemoval :: !(TVar (HS.HashSet channel))
    }

-- | A controller that stores a set of channels, pattern channels, and callbacks.
-- It allows you to manage Pub/Sub subscriptions and pattern subscriptions and alter them at
-- any time throughout the life of your program.
-- You should typically create the controller at the start of your program and then store it
-- through the life of your program, using 'addChannels' and 'removeChannels' to update the
-- current subscriptions.
data PubSubController = PubSubController
  { sendChanges :: TBQueue PubSub
  , pscChannelData :: ChannelData RedisChannel MessageCallback
  , pscPChannelData :: ChannelData RedisPChannel PMessageCallback
  , lastUsedCallbackId :: TVar UnregisterHandle
  }

newChannelData :: Hashable channel => [(channel, callback)] -> STM (ChannelData channel callback)
newChannelData initialSubs
    = ChannelData
    <$> newTVar (HM.fromListWith (++) $ map (second $ pure . (0,)) initialSubs)
    <*> newTVar mempty
    <*> newTVar mempty

-- | Create a new 'PubSubController'.  Note that this does not subscribe to any channels, it just
-- creates the controller.  The subscriptions will happen once 'pubSubForever' is called.
newPubSubController :: MonadIO m => [(RedisChannel, MessageCallback)] -- ^ the initial subscriptions
                                 -> [(RedisPChannel, PMessageCallback)] -- ^ the initial pattern subscriptions
                                 -> m PubSubController
newPubSubController initialSubs initialPSubs = liftIO $ atomically $ do
    c <- newTBQueue 10
    lastId <- newTVar 0
    channelData' <- newChannelData initialSubs
    pchannelData' <- newChannelData initialPSubs
    return $ PubSubController c channelData' pchannelData' lastId

#if __GLASGOW_HASKELL__ < 710
type FunctorMonadIO m = (MonadIO m, Functor m)
#else
type FunctorMonadIO m = MonadIO m
#endif

-- | Get the list of current channels in the 'PubSubController'.  WARNING! This might not
-- exactly reflect the subscribed channels in the Redis server, because there is a delay
-- between adding or removing a channel in the 'PubSubController' and when Redis receives
-- and processes the subscription change request.
currentChannels :: FunctorMonadIO m => PubSubController -> m [RedisChannel]
currentChannels ctrl = HM.keys <$> (liftIO $ atomically $ readTVar $ cdSubscribedChannels $ pscChannelData ctrl)

-- | Get the list of current pattern channels in the 'PubSubController'.  WARNING! This might not
-- exactly reflect the subscribed channels in the Redis server, because there is a delay
-- between adding or removing a channel in the 'PubSubController' and when Redis receives
-- and processes the subscription change request.
currentPChannels :: FunctorMonadIO m => PubSubController -> m [RedisPChannel]
currentPChannels ctrl = HM.keys <$> (liftIO $ atomically $ readTVar $ cdSubscribedChannels $ pscPChannelData ctrl)

pendingChannels :: MonadIO m => PubSubController -> m (HS.HashSet RedisChannel)
pendingChannels ctrl = liftIO $ readTVarIO $ cdChannelsPendingSubscription $ pscChannelData ctrl

pendingPatternChannels :: MonadIO m => PubSubController -> m (HS.HashSet RedisChannel)
pendingPatternChannels ctrl = liftIO $ readTVarIO $ cdChannelsPendingSubscription $ pscPChannelData ctrl

-- type CallbackMap a = HM.HashMap ByteString [(UnregisterHandle, a)]

-- | Helper for `addChannels`. Can take either normal or pattern channels.
addChannelsOfType
    :: Hashable channel
    => UnregisterHandle
    -> [(channel, callback)]
    -> ChannelData channel callback
    -> STM [channel]
addChannelsOfType ident newChans channelData = do
    callbacks <- readTVar $ cdSubscribedChannels channelData
    pendingCallbacks <- readTVar $ cdChannelsPendingSubscription channelData
    let newChans' = filter (not . memberMapOrSet callbacks pendingCallbacks) $ fst <$> newChans
    writeTVar (cdSubscribedChannels channelData) (HM.unionWith (++) callbacks $ (\z -> [(ident,z)]) <$> HM.fromList newChans)
    writeTVar (cdChannelsPendingSubscription channelData) $ HS.union pendingCallbacks $ HS.fromList newChans'
    pure newChans'

-- | Add channels into the 'PubSubController', and if there is an active 'pubSubForever', send the subscribe
-- and psubscribe commands to Redis.  The 'addChannels' function is thread-safe.  This function
-- does not wait for Redis to acknowledge that the channels have actually been subscribed; use
-- 'addChannelsAndWait' for that.
--
-- You can subscribe to the same channel or pattern channel multiple times; the 'PubSubController' keeps
-- a list of callbacks and executes each callback in response to a message.
--
-- The return value is an action 'UnregisterCallbacksAction' which will unregister the callbacks,
-- which should typically used with 'bracket'.
addChannels :: MonadIO m => PubSubController
                         -> [(RedisChannel, MessageCallback)] -- ^ the channels to subscribe to
                         -> [(RedisPChannel, PMessageCallback)] -- ^ the channels to pattern subscribe to
                         -> m UnregisterCallbacksAction
addChannels _ [] [] = return $ return ()
addChannels ctrl newChans newPChans = liftIO $ do
    ident <- atomically $ do
      modifyTVar (lastUsedCallbackId ctrl) (+1)
      ident <- readTVar $ lastUsedCallbackId ctrl
      newChannels <- addChannelsOfType ident newChans $ pscChannelData ctrl
      newPChannels <- addChannelsOfType ident newPChans $ pscPChannelData ctrl
      let ps = subscribe newChannels `mappend` psubscribe newPChannels
      writeTBQueue (sendChanges ctrl) ps
      return ident
    return $ unsubChannels ctrl (map fst newChans) (map fst newPChans) ident


-- | Call 'addChannels' and then wait for Redis to acknowledge that the channels are actually subscribed.
--
-- Note that this function waits for all pending subscription change requests, so if you for example call
-- 'addChannelsAndWait' from multiple threads simultaneously, they all will wait for all pending
-- subscription changes to be acknowledged by Redis (this is due to the fact that we just track the total
-- number of pending change requests sent to Redis and just wait until that count reaches zero).
--
-- This also correctly waits if the network connection dies during the subscription change.  Say that the
-- network connection dies right after we send a subscription change to Redis.  'pubSubForever' will throw
-- 'ConnectionLost' and 'addChannelsAndWait' will continue to wait.  Once you recall 'pubSubForever'
-- with the same 'PubSubController', 'pubSubForever' will open a new connection, send subscription commands
-- for all channels in the 'PubSubController' (which include the ones we are waiting for),
-- and wait for the responses from Redis.  Only once we receive the response from Redis that it has subscribed
-- to all channels in 'PubSubController' will 'addChannelsAndWait' unblock and return.
addChannelsAndWait :: MonadIO m => PubSubController
                                -> [(RedisChannel, MessageCallback)] -- ^ the channels to subscribe to
                                -> [(RedisPChannel, PMessageCallback)] -- ^ the channels to psubscribe to
                                -> m UnregisterCallbacksAction
addChannelsAndWait _ [] [] = return $ return ()
addChannelsAndWait ctrl newChans newPChans = do
  unreg <- addChannels ctrl newChans newPChans
  liftIO $ waitUntilAbsent (cdChannelsPendingSubscription $ pscChannelData ctrl) $ fst <$> newChans
  liftIO $ waitUntilAbsent (cdChannelsPendingSubscription $ pscPChannelData ctrl) $ fst <$> newPChans
  return unreg

waitUntilAbsent :: Hashable channel => TVar (HS.HashSet channel) -> [channel] -> IO ()
waitUntilAbsent tPendingChannels channels = forM_ channels $ \channel -> atomically $ do
  pendingChannels' <- readTVar tPendingChannels
  when (HS.member channel pendingChannels') retry

-- | Remove channels from the 'PubSubController', and if there is an active 'pubSubForever', send the
-- unsubscribe commands to Redis.  Note that as soon as this function returns, no more callbacks will be
-- executed even if more messages arrive during the period when we request to unsubscribe from the channel
-- and Redis actually processes the unsubscribe request.  This function is thread-safe.
--
-- If you remove all channels, the connection in 'pubSubForever' to redis will stay open and waiting for
-- any new channels from a call to 'addChannels'.  If you really want to close the connection,
-- use 'Control.Concurrent.killThread' or 'Control.Concurrent.Async.cancel' to kill the thread running
-- 'pubSubForever'.
removeChannels :: MonadIO m => PubSubController
                            -> [RedisChannel]
                            -> [RedisPChannel]
                            -> m ()
removeChannels _ [] [] = return ()
removeChannels ctrl remChans remPChans = liftIO $ atomically $ do
    remChans' <- removeChannels' (pscChannelData ctrl) remChans
    remPChans' <- removeChannels' (pscPChannelData ctrl) remPChans
    writeTBQueue (sendChanges ctrl) $ unsubscribe remChans' `mappend` punsubscribe remPChans'

#if !(MIN_VERSION_stm(2,3,0))
-- | Strict version of 'modifyTVar'.
--
-- @since 2.3
modifyTVar' :: TVar a -> (a -> a) -> STM ()
modifyTVar' var f = do
    x <- readTVar var
    writeTVar var $! f x
{-# INLINE modifyTVar' #-}
#endif

data ShowTag a = ShowTag String a deriving Show

-- Helper for `removeChannels` that works on normal or pattern channels
removeChannels' :: (Show channel, Hashable channel) => ChannelData channel callback -> [channel] -> STM [channel]
removeChannels' channelData remChannels = do
    subbedChannels <- readTVar $ cdSubscribedChannels channelData
    pendingChannelSubs <- readTVar $ cdChannelsPendingSubscription channelData
    let remChannels' = filter (memberMapOrSet subbedChannels pendingChannelSubs) remChannels
    writeTVar (cdSubscribedChannels channelData) (foldl' (flip HM.delete) subbedChannels remChannels')
    writeTVar (cdChannelsPendingSubscription channelData) (foldl' (flip HS.delete) pendingChannelSubs remChannels')
    modifyTVar' (cdChannelsPendingRemoval channelData) $ flip (foldl' $ flip HS.insert) remChannels'
    pure remChannels'

memberMapOrSet :: Hashable k => HM.HashMap k v1 -> HS.HashSet k -> k -> Bool
memberMapOrSet m s k = HM.member k m || HS.member k s

unregisterHandles
    :: forall channel callback. Hashable channel => ChannelData channel callback
    -> [channel]
    -> UnregisterHandle
    -> STM [channel]
unregisterHandles channelData remChansParam h = do
    callbacks <- readTVar $ cdSubscribedChannels channelData
    let remChans = filter (`HM.member` callbacks) remChansParam

    -- helper functions to filter out handlers that match
    -- returns number of removals, and remaining subscriptions
    -- maps after taking out channels matching the handle
    let callbacks' = foldl' removeHandles callbacks remChans
        remChans' = filter (\chan -> HM.member chan callbacks && not (HM.member chan callbacks')) remChans

    writeTVar (cdSubscribedChannels channelData) callbacks'
    unless (null remChans') $ modifyTVar (cdChannelsPendingSubscription channelData) (`HS.difference` HS.fromList remChans')
    pure remChans'

    where
        filterHandle :: Maybe [(UnregisterHandle,a)] -> Maybe (Int, [(UnregisterHandle,a)])
        filterHandle Nothing = Nothing
        filterHandle (Just lst) = case filter (\x -> fst x /= h) lst of
                                    [] -> Nothing
                                    xs -> Just (length lst - length xs, xs)

        removeHandles :: HM.HashMap channel [(UnregisterHandle,a)]
                      -> channel
                      -> HM.HashMap channel [(UnregisterHandle,a)]
        removeHandles m k = case filterHandle (HM.lookup k m) of -- recent versions of unordered-containers have alter
            Nothing -> HM.delete k m
            Just (_, v) -> HM.insert k v m


-- | Internal function to unsubscribe only from those channels matching the given handle.
unsubChannels :: PubSubController -> [RedisChannel] -> [RedisPChannel] -> UnregisterHandle -> IO ()
unsubChannels ctrl chans pchans h = liftIO $ atomically $ do
    channelsToDrop <- unregisterHandles (pscChannelData ctrl) chans h
    pChannelsToDrop <- unregisterHandles (pscPChannelData ctrl) pchans h

    let commands = unsubscribe channelsToDrop `mappend` punsubscribe pChannelsToDrop

    -- do the unsubscribe
    writeTBQueue (sendChanges ctrl) commands
    return ()

-- | Call 'removeChannels' and then wait for all pending subscription change requests to be acknowledged
-- by Redis.  This uses the same waiting logic as 'addChannelsAndWait'.  Since 'removeChannels' immediately
-- notifies the 'PubSubController' to start discarding messages, you likely don't need this function and
-- can just use 'removeChannels'.
removeChannelsAndWait :: MonadIO m => PubSubController
                                   -> [RedisChannel]
                                   -> [RedisPChannel]
                                   -> m ()
removeChannelsAndWait ctrl remChannels remPChannels = liftIO $ do
    (remChans', remPChans') <- atomically $ do
        remChans' <- removeChannels' (pscChannelData ctrl) remChannels
        remPChans' <- removeChannels' (pscPChannelData ctrl) remPChannels
        writeTBQueue (sendChanges ctrl) $ unsubscribe remChans' `mappend` punsubscribe remPChans'
        pure (remChans', remPChans')
    waitUntilAbsent (cdChannelsPendingRemoval $ pscChannelData ctrl) remChans'
    waitUntilAbsent (cdChannelsPendingRemoval $ pscPChannelData ctrl) remPChans'

-- | Internal thread which listens for messages and executes callbacks.
-- This is the only thread which ever receives data from the underlying
-- connection.
listenThread :: PubSubController -> PP.Connection -> IO ()
listenThread ctrl rawConn = forever $ do
    msg <- PP.recv rawConn
    case decodeMsg msg of
        Msg (Message channel msgCt) -> do
          cm <- atomically $ readTVar $ cdSubscribedChannels $ pscChannelData ctrl
          case HM.lookup channel cm of
            Nothing -> return ()
            Just c -> mapM_ (\(_,x) -> x msgCt) c
        Msg (PMessage pattern channel msgCt) -> do
          pm <- atomically $ readTVar $ cdSubscribedChannels $ pscPChannelData ctrl
          case HM.lookup pattern pm of
            Nothing -> return ()
            Just c -> mapM_ (\(_,x) -> x channel msgCt) c
        Subscribed chan -> atomically $ modifyTVar (cdChannelsPendingSubscription $ pscChannelData ctrl) $ HS.delete chan
        PSubscribed chan -> atomically $ modifyTVar (cdChannelsPendingSubscription $ pscPChannelData ctrl) $ HS.delete chan
        Unsubscribed chan _ -> atomically $ modifyTVar (cdChannelsPendingRemoval $ pscChannelData ctrl) $ HS.delete chan
        PUnsubscribed chan _ -> atomically $ modifyTVar (cdChannelsPendingRemoval $ pscPChannelData ctrl) $ HS.delete chan

-- | Internal thread which sends subscription change requests.
-- This is the only thread which ever sends data on the underlying
-- connection.
sendThread :: PubSubController -> PP.Connection -> IO ()
sendThread ctrl rawConn = forever $ do
    PubSub{..} <- atomically $ readTBQueue (sendChanges ctrl)
    rawSendCmd rawConn subs
    rawSendCmd rawConn unsubs
    rawSendCmd rawConn psubs
    rawSendCmd rawConn punsubs
    -- normally, the socket is flushed during 'recv', but
    -- 'recv' could currently be blocking on a message.
    PP.flush rawConn

-- | Open a connection to the Redis server, register to all channels in the 'PubSubController',
-- and process messages and subscription change requests forever.  The only way this will ever
-- exit is if there is an exception from the network code or an unhandled exception
-- in a 'MessageCallback' or 'PMessageCallback'. For example, if the network connection to Redis
-- dies, 'pubSubForever' will throw a 'ConnectionLost'.  When such an exception is
-- thrown, you can recall 'pubSubForever' with the same 'PubSubController' which will open a
-- new connection and resubscribe to all the channels which are tracked in the 'PubSubController'.
--
-- The general pattern is therefore during program startup create a 'PubSubController' and fork
-- a thread which calls 'pubSubForever' in a loop (using an exponential backoff algorithm
-- such as the <https://hackage.haskell.org/package/retry retry> package to not hammer the Redis
-- server if it does die).  For example,
--
-- @
-- myhandler :: ByteString -> IO ()
-- myhandler msg = putStrLn $ unpack $ decodeUtf8 msg
--
-- onInitialComplete :: IO ()
-- onInitialComplete = putStrLn "Redis acknowledged that mychannel is now subscribed"
--
-- main :: IO ()
-- main = do
--   conn <- connect defaultConnectInfo
--   pubSubCtrl <- newPubSubController [("mychannel", myhandler)] []
--   concurrently ( forever $
--       pubSubForever conn pubSubCtrl onInitialComplete
--         \`catch\` (\\(e :: SomeException) -> do
--           putStrLn $ "Got error: " ++ show e
--           threadDelay $ 50*1000) -- TODO: use exponential backoff
--        ) $ restOfYourProgram
--
--
--   {- elsewhere in your program, use pubSubCtrl to change subscriptions -}
-- @
--
-- At most one active 'pubSubForever' can be running against a single 'PubSubController' at any time.  If
-- two active calls to 'pubSubForever' share a single 'PubSubController' there will be deadlocks.  If
-- you do want to process messages using multiple connections to Redis, you can create more than one
-- 'PubSubController'.  For example, create one PubSubController for each 'Control.Concurrent.getNumCapabilities'
-- and then create a Haskell thread bound to each capability each calling 'pubSubForever' in a loop.
-- This will create one network connection per controller/capability and allow you to
-- register separate channels and callbacks for each controller, spreading the load across the capabilities.
pubSubForever :: Connection.Connection -- ^ The connection pool
              -> PubSubController -- ^ The controller which keeps track of all subscriptions and handlers
              -> IO () -- ^ This action is executed once Redis acknowledges that all the subscriptions in
                       -- the controller are now subscribed.  You can use this after an exception (such as
                       -- 'ConnectionLost') to signal that all subscriptions are now reactivated.
              -> IO ()
pubSubForever (Connection.NonClusteredConnection pool) ctrl onInitialLoad = withResource pool $ \rawConn -> do
    -- get initial subscriptions and write them into the queue.
    atomically $ do
      let loop = tryReadTBQueue (sendChanges ctrl) >>=
                   \x -> if isJust x then loop else return ()
      loop
      channels <- fmap HM.keys $ readTVar $ cdSubscribedChannels $ pscChannelData ctrl
      patternChannels <- fmap HM.keys $ readTVar $ cdSubscribedChannels $ pscPChannelData ctrl
      let ps = subscribe channels `mappend` psubscribe patternChannels
      writeTBQueue (sendChanges ctrl) ps
      writeTVar (cdChannelsPendingSubscription $ pscChannelData ctrl) $ HS.fromList channels
      writeTVar (cdChannelsPendingSubscription $ pscPChannelData ctrl) $ HS.fromList patternChannels

    withAsync (listenThread ctrl rawConn) $ \listenT ->
      withAsync (sendThread ctrl rawConn) $ \sendT -> do

        -- wait for initial subscription count to go to zero or for threads to fail
        mret <- atomically $
            (Left <$> (waitEitherCatchSTM listenT sendT))
          `orElse`
            (Right <$> do
              a <- readTVar $ cdChannelsPendingSubscription $ pscChannelData ctrl
              unless (HS.null a) retry
              b <- readTVar $ cdChannelsPendingSubscription $ pscPChannelData ctrl
              unless (HS.null b) retry)
        case mret of
          Right () -> onInitialLoad
          _ -> return () -- if there is an error, waitEitherCatch below will also see it

        -- wait for threads to end with error
        merr <- waitEitherCatch listenT sendT
        case merr of
          (Right (Left err)) -> throwIO err
          (Left (Left err)) -> throwIO err
          _ -> return ()  -- should never happen, since threads exit only with an error
pubSubForever (Connection.ClusteredConnection _ _) _ _ = undefined


------------------------------------------------------------------------------
-- Helpers
--
decodeMsg :: Reply -> PubSubReply
decodeMsg r@(MultiBulk (Just (r0:r1:r2:rs))) = either (errMsg r) id $ do
    kind <- decode r0
    case kind :: ByteString of
        "message"      -> Msg <$> decodeMessage
        "pmessage"     -> Msg <$> decodePMessage
        "subscribe"    -> Subscribed <$> decodeChan
        "psubscribe"   -> PSubscribed <$> decodeChan
        "unsubscribe"  -> Unsubscribed <$> decodeChan <*> decodeCnt
        "punsubscribe" -> PUnsubscribed <$> decodeChan <*> decodeCnt
        _              -> errMsg r
  where
    decodeMessage  = Message  <$> decode r1 <*> decode r2
    decodePMessage = PMessage <$> decode r1 <*> decode r2 <*> decode (head rs)
    decodeCnt      = fromInteger <$> decode r2
    decodeChan     = decode r1

decodeMsg r = errMsg r

errMsg :: Reply -> a
errMsg r = error $ "Hedis: expected pub/sub-message but got: " ++ show r


-- $pubsubexpl
-- There are two Pub/Sub implementations.  First, there is a single-threaded implementation 'pubSub'
-- which is simpler to use but has the restriction that subscription changes can only be made in
-- response to a message.  Secondly, there is a more complicated Pub/Sub controller 'pubSubForever'
-- that uses concurrency to support changing subscriptions at any time but requires more setup.
-- You should only use one or the other.  In addition, no types or utility functions (that are part
-- of the public API) are shared, so functions or types in one of the following sections cannot
-- be used for the other.  In particular, be aware that they use different utility functions to subscribe
-- and unsubscribe to channels.
