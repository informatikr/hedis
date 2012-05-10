{-# LANGUAGE OverloadedStrings, RecordWildCards, EmptyDataDecls,
    FlexibleInstances, FlexibleContexts #-}

module Database.Redis.PubSub (
    publish,
    pubSub,
    Message(..),
    PubSub(),
    subscribe, unsubscribe, psubscribe, punsubscribe
) where

import Control.Applicative
import Control.Monad
import Control.Monad.State
import Data.ByteString.Char8 (ByteString)
import Data.Maybe
import Data.Monoid
import qualified Database.Redis.Core as Core
import Database.Redis.Protocol (Reply(..))
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

instance Monoid PubSub where
    mempty        = PubSub mempty mempty mempty mempty
    mappend p1 p2 = PubSub { subs    = subs p1 `mappend` subs p2
                           , unsubs  = unsubs p1 `mappend` unsubs p2
                           , psubs   = psubs p1 `mappend` psubs p2
                           , punsubs = punsubs p1 `mappend` punsubs p2
                           }

data Cmd a b = DoNothing | Cmd { changes :: [ByteString] } deriving (Eq)

instance Monoid (Cmd Subscribe a) where
    mempty                      = DoNothing
    mappend DoNothing x         = x
    mappend x         DoNothing = x
    mappend (Cmd xs)  (Cmd ys)  = Cmd (xs ++ ys)
    
instance Monoid (Cmd Unsubscribe a) where
    mempty                       = DoNothing
    mappend DoNothing x          = x
    mappend x         DoNothing  = x
    -- empty subscription list => unsubscribe all channels and patterns
    mappend (Cmd [])  _          = Cmd []
    mappend _         (Cmd [])   = Cmd []
    mappend (Cmd xs)  (Cmd ys)   = Cmd (xs ++ ys)


class Command a where
    redisCmd      :: a -> ByteString
    updatePending :: a -> Int -> Int

sendCmd :: (Command (Cmd a b)) => Cmd a b -> StateT PubSubState Core.Redis ()
sendCmd DoNothing = return ()
sendCmd cmd       = do
    lift $ Core.send (redisCmd cmd : changes cmd)
    modifyPending (updatePending cmd)

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

data PubSubReply = Subscribed | Unsubscribed Int | Msg Message


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
subscribe []       = mempty
subscribe cs = mempty{ subs = Cmd cs }

-- |Stop listening for messages posted to the given channels
--  (<http://redis.io/commands/unsubscribe>).
unsubscribe
    :: [ByteString] -- ^ channel
    -> PubSub
unsubscribe cs = mempty{ unsubs = Cmd cs }

-- |Listen for messages published to channels matching the given patterns 
--  (<http://redis.io/commands/psubscribe>).
psubscribe
    :: [ByteString] -- ^ pattern
    -> PubSub
psubscribe []       = mempty
psubscribe ps = mempty{ psubs = Cmd ps }

-- |Stop listening for messages posted to channels matching the given patterns 
--  (<http://redis.io/commands/punsubscribe>).
punsubscribe
    :: [ByteString] -- ^ pattern
    -> PubSub
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
            Msg msg        -> liftIO (callback msg) >>= send
            Subscribed     -> modifyPending (subtract 1) >> recv
            Unsubscribed n -> do
                putSubCnt n
                PubSubState{..} <- get
                unless (subCnt == 0 && pending == 0) recv

------------------------------------------------------------------------------
-- Helpers
--
decodeMsg :: Reply -> PubSubReply
decodeMsg r@(MultiBulk (Just (r0:r1:r2:rs))) = either (errMsg r) id $ do
    kind <- decode r0
    case kind :: ByteString of
        "message"      -> Msg <$> decodeMessage
        "pmessage"     -> Msg <$> decodePMessage
        "subscribe"    -> return Subscribed
        "psubscribe"   -> return Subscribed
        "unsubscribe"  -> Unsubscribed <$> decodeCnt
        "punsubscribe" -> Unsubscribed <$> decodeCnt
        _              -> errMsg r
  where
    decodeMessage  = Message  <$> decode r1 <*> decode r2
    decodePMessage = PMessage <$> decode r1 <*> decode r2 <*> decode (head rs)
    decodeCnt      = decode r2
        
decodeMsg r = errMsg r

errMsg :: Reply -> a
errMsg r = error $ "Hedis: expected pub/sub-message but got: " ++ show r
