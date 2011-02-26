{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Main where

import Control.Concurrent
import Control.Monad.Reader
import Control.Monad.State
import Control.Monad.Trans
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy.Char8 as LB
import Network
import System.IO (Handle, hClose, hFlush)

import Request
import Reply


type Connection = Handle

newtype Redis a = Redis (ReaderT Handle (StateT [Reply] IO) a)
    deriving (Monad, MonadIO)


runRedis :: Handle -> Redis a -> IO a
runRedis h (Redis r) = do
    replies <- fmap parseReply $ LB.hGetContents h
    evalStateT (runReaderT r h) replies


sendPing :: Redis Reply
sendPing = sendRequest ["PING"]

sendSet :: Redis Reply
sendSet = sendRequest ["SET", "mykey", "myvalue"]

sendGet :: Redis Reply
sendGet = sendRequest ["GET", "anotherkey"]


sendRequest :: [B.ByteString] -> Redis Reply
sendRequest req = Redis $ do
    h <- ask
    liftIO $ B.hPut h $ renderRequest req
    liftIO $ hFlush h
    
    (reply:rs) <- get
    put rs
    return reply


main :: IO ()
main = withSocketsDo $ do
    
    h <- connectTo "127.0.0.1" (PortNumber 6379)

    pong1 <- runRedis h $ do
        sendRequest ["MULTI"]
        sendRequest ["GET", "mykey"]
        sendRequest ["LRANGE", "mylist", "0", "2"]
        sendRequest ["EXEC"]

    print pong1
                
    hClose h
