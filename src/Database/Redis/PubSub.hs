{-# LANGUAGE OverloadedStrings #-}
module Database.Redis.PubSub (
    publish,
    pubSub,
    Message(..),
    PubSub(),
    subscribe, unsubscribe,
    psubscribe, punsubscribe,
) where

import Control.Applicative
import Control.Monad.Writer
import Data.ByteString.Char8 (ByteString)
import Data.Maybe
import qualified Database.Redis.Core as Core
import Database.Redis.Reply
import Database.Redis.Types


newtype PubSub = PubSub [[ByteString]]

instance Monoid PubSub where
    mempty                         = PubSub []
    mappend (PubSub p) (PubSub p') = PubSub (p ++ p')

data Message = Message  { msgChannel, msgMessage :: ByteString}
             | PMessage { msgPattern, msgChannel, msgMessage :: ByteString}
    deriving (Show)

------------------------------------------------------------------------------
-- Public Interface
--

-- |Post a message to a channel (<http://redis.io/commands/publish>).
publish
    :: ByteString -- ^ channel
    -> ByteString -- ^ message
    -> Core.Redis (Either Reply Integer)
publish channel message =
    Core.sendRequest ["PUBLISH", channel, message]

-- |Listen for messages published to the given channels
--  (<http://redis.io/commands/subscribe>).
subscribe
    :: [ByteString] -- ^ channel
    -> PubSub
subscribe = pubSubAction "SUBSCRIBE"

-- |Stop listening for messages posted to the given channels 
--  (<http://redis.io/commands/unsubscribe>).
unsubscribe
    :: [ByteString] -- ^ channel
    -> PubSub
unsubscribe = pubSubAction "UNSUBSCRIBE"

-- |Listen for messages published to channels matching the given patterns 
--  (<http://redis.io/commands/psubscribe>).
psubscribe
    :: [ByteString] -- ^ pattern
    -> PubSub
psubscribe = pubSubAction "PSUBSCRIBE"

-- |Stop listening for messages posted to channels matching the given patterns 
--  (<http://redis.io/commands/punsubscribe>).
punsubscribe
    :: [ByteString] -- ^ pattern
    -> PubSub
punsubscribe = pubSubAction "PUNSUBSCRIBE"

-- |Listens to published messages on subscribed channels.
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
pubSub p callback = send p 0
  where
    send (PubSub cmds) pending = do
        mapM_ Core.send cmds
        recv (pending + length cmds)

    recv pending = do
        reply <- Core.recv
        case decodeMsg reply of
            Left cnt  -> let pending' = pending - 1
                         in unless (cnt == 0 && pending' == 0) $
                            send mempty pending'
            Right msg -> do act <- liftIO $ callback msg
                            send act pending

------------------------------------------------------------------------------
-- Helpers
--

pubSubAction :: ByteString -> [ByteString] -> PubSub
pubSubAction cmd chans = PubSub [cmd : chans]

decodeMsg :: Reply -> Either Integer Message
decodeMsg (MultiBulk (Just (r0:r1:r2:rs))) = either (error "decodeMsg") id $ do
    kind <- decode r0
    case kind :: ByteString of
        "message"  -> Right <$> decodeMessage
        "pmessage" -> Right <$> decodePMessage
        -- kind `elem` ["subscribe","unsubscribe","psubscribe","punsubscribe"]
        _          -> Left <$> decode r2
  where
    decodeMessage  = Message  <$> decode r1 <*> decode r2
    decodePMessage = PMessage <$> decode r1 <*> decode r2
                                    <*> decode (head rs)
        
decodeMsg r = error $ "not a message: " ++ show r
