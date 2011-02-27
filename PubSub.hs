{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module PubSub where

import Control.Applicative
import Control.Monad.Writer
import qualified Data.ByteString.Char8 as B
import Data.Maybe

import Reply
import Internal


newtype PubSub a = PubSub (WriterT [PubSubAction] IO a)
    deriving (Monad, MonadIO)

data PubSubAction = PubSubAction B.ByteString [B.ByteString]


data Message = Subscribe B.ByteString Integer
             | Unsubscribe B.ByteString Integer
             | PSubscribe B.ByteString Integer
             | PUnsubscribe B.ByteString Integer
             | Message B.ByteString B.ByteString
             | PMessage B.ByteString B.ByteString B.ByteString
    deriving (Show)


readMsg :: Reply -> Maybe Message
readMsg (MultiBulk (Just (r0:r1:r2:rs))) = do
    kind <- fromBulk r0
    case kind of
        "subscribe"    -> Subscribe    <$> fromBulk r1 <*> fromInt r2
        "unsubscribe"  -> Unsubscribe  <$> fromBulk r1 <*> fromInt r2
        "psubscribe"   -> PSubscribe   <$> fromBulk r1 <*> fromInt r2
        "punsubscribe" -> PUnsubscribe <$> fromBulk r1 <*> fromInt r2
        "message"      -> Message      <$> fromBulk r1 <*> fromBulk r2
        "pmessage"     -> PMessage     <$> fromBulk r1
                                            <*> fromBulk r2
                                            <*> (maybeHead rs >>= fromBulk)
        _              -> Nothing
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


subscribe   = PubSubAction "SUBSCRIBE"
unsubscribe = PubSubAction "UNSUBSCRIBE"


pubSub :: PubSub () -> (Message -> PubSub ()) -> Redis ()
pubSub init = do
    undefined
    
    
    

--subscribe, unsubscribe :: ByteString -> WriterT [PubSub] Redis

{- 
Die an "pubSub" übergebene Action gibt eine Liste an weiteren 


Für jede Message ein Callback. Callbackfunktion hat den von Redis gewrappten
Typ (z.B. IO). Dazu ein WriterT für weitere PubSub-Commands.

Nach dem Callback werden die zurückgegebenen Commands an den Server geschickt.
Liegen keine Kommandos mehr vor und ist die Anzahl der Subscriptions gleich
null wird PubSub abgebrochen.

-}



--pubSub (subscribe ["myChan"]) $ \msg -> do
--    liftIO doSomething
--    subscribe ["anotherChan"]
--    unsubscribe "anotherChan"
--    unsubscribe "myChan"

foo :: Reply
foo = MultiBulk $ Just
        [ Bulk (Just "message")
        , Bulk (Just "myChan")
        , Bulk (Just "message payload")
        ]

main :: IO ()
main = print $ readMsg foo
