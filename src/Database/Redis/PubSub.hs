{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Database.Redis.PubSub (
    PubSub,
    Message(Message, PMessage),
    pubSub,
    subscribe, unsubscribe,
    psubscribe, punsubscribe
) where

import Control.Applicative
import Control.Monad.Writer
import qualified Data.ByteString.Char8 as B

import Database.Redis.Internal (Redis)
import qualified Database.Redis.Internal as Internal
import Database.Redis.Reply
import Database.Redis.Types


newtype PubSub a = PubSub (WriterT PuSubActions IO a)
    deriving (Monad, MonadIO, MonadWriter PuSubActions)

-- TODO more efficient/less ugly type?
type PuSubActions = [[B.ByteString]]

data Message = Message B.ByteString B.ByteString
             | PMessage B.ByteString B.ByteString B.ByteString
             | SubscriptionCnt Integer
    deriving (Show)


------------------------------------------------------------------------------
-- Public Interface
--
subscribe :: B.ByteString -> PubSub ()
subscribe = pubSubAction "SUBSCRIBE"

unsubscribe :: B.ByteString -> PubSub ()
unsubscribe = pubSubAction "UNSUBSCRIBE"

psubscribe :: B.ByteString -> PubSub ()
psubscribe = pubSubAction "PSUBSCRIBE"

punsubscribe :: B.ByteString -> PubSub ()
punsubscribe = pubSubAction "PUNSUBSCRIBE"


pubSub :: PubSub () -> (Message -> PubSub ()) -> Redis ()
pubSub (PubSub p) callback = send p 0
  where
    send action outstanding = do
        cmds <- liftIO (execWriterT action)
        mapM_ Internal.send cmds
        recv (outstanding + length cmds)
        
    recv outstanding = do
        reply <- Internal.recv
        case decodeMsg reply of
            Just (SubscriptionCnt cnt)
                | cnt == 0 && outstanding == 0
                            -> return ()
                | otherwise -> send (return ()) (outstanding -1)
            Just msg        -> send (callback msg) callback
            Nothing         -> undefined


------------------------------------------------------------------------------
-- Helpers
--
pubSubAction :: B.ByteString -> B.ByteString -> PubSub ()
pubSubAction cmd chan = tell [[cmd, chan]]

decodeMsg :: Reply -> Maybe Message
decodeMsg (MultiBulk (Just (r0:r1:r2:rs))) = do
    kind <- decodeValue r0
    case kind :: B.ByteString of
        "message"  -> Message  <$> decodeValue r1 <*> decodeValue r2
        "pmessage" -> PMessage <$> decodeValue r1
                                        <*> decodeValue r2
                                        <*> (maybeHead rs >>= decodeValue)
        -- kind `elem` ["subscribe","unsubscribe","psubscribe","punsubscribe"]
        _          -> SubscriptionCnt <$> decodeInt r2                        
                        
decodeMsg _ = Nothing

maybeHead :: [a] -> Maybe a
maybeHead (x:_) = Just x
maybeHead _     = Nothing
