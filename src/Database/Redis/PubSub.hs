{-# LANGUAGE OverloadedStrings, NamedFieldPuns, RecordWildCards #-}

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

-- |Encapsulates subscription changes. Use 'subscribe', 'unsubscribe',
--  'psubscribe', 'punsubscribe' or 'mempty' to construct a value. Combine
--  values by using the 'Monoid' interface, i.e. 'mappend' and 'mconcat'.
data PubSub = PubSub { subs, unsubs, psubs, punsubs :: [ByteString] }
    deriving (Eq)

instance Monoid PubSub where
    mempty        = PubSub [] [] [] []
    mappend p1 p2 = PubSub { subs    = subs p1 `mappend` subs p2
                           , unsubs  = unsubs p1 `mappend` unsubs p2
                           , psubs   = psubs p1 `mappend` psubs p2
                           , punsubs = punsubs p1 `mappend` punsubs p2
                           }

data Message = Message  { msgChannel, msgMessage :: ByteString}
             | PMessage { msgPattern, msgChannel, msgMessage :: ByteString}
    deriving (Show)

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
subscribe subs = mempty{ subs }

-- |Stop listening for messages posted to the given channels
--  (<http://redis.io/commands/unsubscribe>).
unsubscribe
    :: [ByteString] -- ^ channel
    -> PubSub
unsubscribe unsubs = mempty{ unsubs }

-- |Listen for messages published to channels matching the given patterns 
--  (<http://redis.io/commands/psubscribe>).
psubscribe
    :: [ByteString] -- ^ pattern
    -> PubSub
psubscribe psubs = mempty{ psubs }

-- |Stop listening for messages posted to channels matching the given patterns 
--  (<http://redis.io/commands/punsubscribe>).
punsubscribe
    :: [ByteString] -- ^ pattern
    -> PubSub
punsubscribe punsubs = mempty{ punsubs }

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
    | otherwise         = evalStateT (send initial) 0
  where
    send :: PubSub -> StateT Int Core.Redis ()
    send PubSub{..} = do
        let changeSubs (cmd, changes) = unless (null changes) $ do
                lift $ Core.send (cmd : changes)
                modify (+ length changes)
        mapM_ changeSubs
            [("SUBSCRIBE",    subs)
            ,("UNSUBSCRIBE",  unsubs)
            ,("PSUBSCRIBE",   psubs)
            ,("PUNSUBSCRIBE", punsubs)
            ]
        recv

    recv :: StateT Int Core.Redis ()
    recv = do
        reply <- lift Core.recv
        case decodeMsg reply of
            Left subCnt -> do
                pending <- modify (subtract 1) >> get
                unless (subCnt == 0 && pending == 0) (send mempty)
            Right msg -> liftIO (callback msg) >>= send

------------------------------------------------------------------------------
-- Helpers
--
decodeMsg :: Reply -> Either Integer Message
decodeMsg r@(MultiBulk (Just (r0:r1:r2:rs))) = either (errMsg r) id $ do
    kind <- decode r0
    case kind :: ByteString of
        "message"  -> Right <$> decodeMessage
        "pmessage" -> Right <$> decodePMessage
        -- kind `elem` ["subscribe","unsubscribe","psubscribe","punsubscribe"]
        _          -> Left <$> decode r2
  where
    decodeMessage  = Message  <$> decode r1 <*> decode r2
    decodePMessage = PMessage <$> decode r1 <*> decode r2 <*> decode (head rs)
        
decodeMsg r = errMsg r

errMsg :: Reply -> a
errMsg r = error $ "Hedis: expected pub/sub-message but got: " ++ show r
