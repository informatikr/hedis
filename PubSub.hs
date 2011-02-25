{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module PubSub where

import Control.Monad.Writer
import Data.ByteString.Lazy.Char8


newtype PubSub a = PubSub (WriterT [PubSubAction] IO a)
    deriving (Monad, MonadIO)

data PubSubAction = PubSubAction ByteString [ByteString]


subscribe chans = PubSubAction "SUBSCRIBE" chans
unsubscribe = PubSubAction "UNSUBSCRIBE"


--pubSub :: PubSub () -> (Message -> PubSub ()) -> Redis a

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
    