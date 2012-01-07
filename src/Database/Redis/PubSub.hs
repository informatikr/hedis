{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
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
import Database.Redis.Internal (Redis)
import qualified Database.Redis.Internal as Internal
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
publish :: (RedisArg channel, RedisArg message, RedisResult a)
    => channel -- ^
    -> message -- ^
    -> Redis a
publish channel message =
    Internal.sendRequest ["PUBLISH", encode channel, encode message]

-- |Listen for messages published to the given channels
--  (<http://redis.io/commands/subscribe>).
subscribe :: RedisArg channel
    => [channel] -- ^
    -> PubSub
subscribe = pubSubAction "SUBSCRIBE"

-- |Stop listening for messages posted to the given channels 
--  (<http://redis.io/commands/unsubscribe>).
unsubscribe :: RedisArg channel
    => [channel] -- ^
    -> PubSub
unsubscribe = pubSubAction "UNSUBSCRIBE"

-- |Listen for messages published to channels matching the given patterns 
--  (<http://redis.io/commands/psubscribe>).
psubscribe :: RedisArg pattern
    => [pattern] -- ^
    -> PubSub
psubscribe = pubSubAction "PSUBSCRIBE"

-- |Stop listening for messages posted to channels matching the given patterns 
--  (<http://redis.io/commands/punsubscribe>).
punsubscribe :: RedisArg pattern
    => [pattern] -- ^
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
    -> Redis ()
pubSub p callback = send p 0
  where
    send (PubSub cmds) pending = do
        mapM_ Internal.send cmds
        recv (pending + length cmds)

    recv pending = do
        reply <- Internal.recv        
        case decodeMsg reply of
            Left cnt
                | cnt == 0 && pending == 0
                            -> return ()
                | otherwise -> send mempty (pending - 1)
            Right msg       -> do act <- liftIO $ callback msg
                                  send act pending

------------------------------------------------------------------------------
-- Helpers
--

pubSubAction :: (RedisArg chan) => ByteString -> [chan] -> PubSub
pubSubAction cmd chans = PubSub [cmd : map encode chans]

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
                                    <*> (decode =<< maybeHead rs)
        
decodeMsg r = error $ "not a message: " ++ show r

maybeHead :: [a] -> Either ResultError a
maybeHead (x:_) = Right x
maybeHead _     = Left ResultError
