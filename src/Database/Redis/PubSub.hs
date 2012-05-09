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
import Database.Redis.Reply (Reply(..))
import Database.Redis.Types


data PubSubState = PubSubState { subCnt, pending :: Int }

modifyPending :: (MonadState PubSubState m) => (Int -> Int) -> m ()
modifyPending f = modify $ \s -> s{ pending = f (pending s) }

setSubCnt :: (MonadState PubSubState m) => Int -> m ()
setSubCnt n = modify $ \s -> s{ subCnt = n }


data Channel
data Pattern

data Subscribe a = SubNone | Sub [ByteString] deriving (Eq)
data Unsubscribe a = UnsubNone | Unsub [ByteString] deriving (Eq)

instance Monoid (Unsubscribe a) where
    mempty                        = UnsubNone
    mappend UnsubNone  x          = x
    mappend x          UnsubNone  = x
    -- empty subscription list => unsubscribe all channels and patterns
    mappend (Unsub []) _          = Unsub []
    mappend _          (Unsub []) = Unsub []
    mappend (Unsub xs) (Unsub ys) = Unsub (xs ++ ys)

instance Monoid (Subscribe a) where
    mempty                    = SubNone
    mappend SubNone  x        = x
    mappend x        SubNone  = x
    mappend (Sub xs) (Sub ys) = Sub (xs ++ ys)


-- |Encapsulates subscription changes. Use 'subscribe', 'unsubscribe',
--  'psubscribe', 'punsubscribe' or 'mempty' to construct a value. Combine
--  values by using the 'Monoid' interface, i.e. 'mappend' and 'mconcat'.
data PubSub = PubSub
    { subs    :: Subscribe Channel
    , unsubs  :: Unsubscribe Channel
    , psubs   :: Subscribe Pattern
    , punsubs :: Unsubscribe Pattern
    } deriving (Eq)

instance Monoid PubSub where
    mempty        = PubSub mempty mempty mempty mempty
    mappend p1 p2 = PubSub { subs    = subs p1 `mappend` subs p2
                           , unsubs  = unsubs p1 `mappend` unsubs p2
                           , psubs   = psubs p1 `mappend` psubs p2
                           , punsubs = punsubs p1 `mappend` punsubs p2
                           }


data Cmd = DoNothing
         | Cmd { cmdRedisCmd      :: ByteString
               , cmdChanges       :: [ByteString]
               , cmdUpdatePending :: Int -> Int
               }

sendCmd :: Cmd -> StateT PubSubState Core.Redis ()
sendCmd DoNothing = return ()
sendCmd Cmd{..}   = do
    lift $ Core.send (cmdRedisCmd : cmdChanges)
    modifyPending cmdUpdatePending

class Command a where
    cmd :: a -> Cmd

instance Command (Subscribe Channel) where
    cmd SubNone  = DoNothing
    cmd (Sub cs) = Cmd "SUBSCRIBE" cs (+ length cs)

instance Command (Subscribe Pattern) where
    cmd SubNone  = DoNothing
    cmd (Sub ps) = Cmd "PSUBSCRIBE" ps (+ length ps)

instance Command (Unsubscribe Channel) where
    cmd UnsubNone  = DoNothing
    cmd (Unsub cs) = Cmd "UNSUBSCRIBE" cs id

instance Command (Unsubscribe Pattern) where
    cmd UnsubNone  = DoNothing
    cmd (Unsub ps) = Cmd "PUNSUBSCRIBE" ps id


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
subscribe channels = mempty{ subs = Sub channels }

-- |Stop listening for messages posted to the given channels
--  (<http://redis.io/commands/unsubscribe>).
unsubscribe
    :: [ByteString] -- ^ channel
    -> PubSub
unsubscribe channels = mempty{ unsubs = Unsub channels }

-- |Listen for messages published to channels matching the given patterns 
--  (<http://redis.io/commands/psubscribe>).
psubscribe
    :: [ByteString] -- ^ pattern
    -> PubSub
psubscribe []       = mempty
psubscribe patterns = mempty{ psubs = Sub patterns }

-- |Stop listening for messages posted to channels matching the given patterns 
--  (<http://redis.io/commands/punsubscribe>).
punsubscribe
    :: [ByteString] -- ^ pattern
    -> PubSub
punsubscribe patterns = mempty{ punsubs = Unsub patterns }

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
        mapM_ sendCmd [cmd subs, cmd unsubs, cmd psubs, cmd punsubs]
        recv

    recv :: StateT PubSubState Core.Redis ()
    recv = do
        reply <- lift Core.recv
        case decodeMsg reply of
            Msg msg        -> liftIO (callback msg) >>= send
            Subscribed     -> modifyPending (subtract 1) >> recv
            Unsubscribed n -> do
                setSubCnt n
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
