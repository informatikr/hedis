{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module PubSub (
    PubSub,
    Message(Message, PMessage),
    pubSub,
    subscribe, unsubscribe,
    psubscribe, punsubscribe
) where

import Control.Applicative
import Control.Monad.Writer
import qualified Data.ByteString.Char8 as B
import Data.Maybe

import Reply
import Internal


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
pubSub (PubSub init) callback = do
    liftIO (execWriterT init) >>= mapM_ send
    reply <- recv
    case readMsg reply of
            Nothing                  -> undefined
            Just (SubscriptionCnt 0) -> return ()
            Just (SubscriptionCnt _) -> pubSub (return ()) callback
            Just msg                 -> pubSub (callback msg) callback


------------------------------------------------------------------------------
-- Helpers
--
pubSubAction :: B.ByteString -> B.ByteString -> PubSub ()
pubSubAction cmd chan = tell [(cmd : [chan])]

readMsg :: Reply -> Maybe Message
readMsg (MultiBulk (Just (r0:r1:r2:rs))) = do
    kind <- fromBulk r0
    case kind of
        "message"  -> Message  <$> fromBulk r1 <*> fromBulk r2
        "pmessage" -> PMessage <$> fromBulk r1
                                        <*> fromBulk r2
                                        <*> (maybeHead rs >>= fromBulk)
        _          -> SubscriptionCnt <$>
                        if kind `elem` [ "subscribe", "unsubscribe"
                                       , "psubscribe", "punsubscribe"]
                            then fromInt r2
                            else Nothing
readMsg _ = Nothing

maybeHead :: [a] -> Maybe a
maybeHead (x:xs) = Just x
maybeHead _      = Nothing

fromBulk :: Reply -> Maybe B.ByteString
fromBulk (Bulk s) = s
fromBulk _        = Nothing

fromInt :: Reply -> Maybe Integer
fromInt (Integer i) = Just i
fromInt _           = Nothing
