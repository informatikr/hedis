{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Main where

import Control.Concurrent
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy.Char8 as LB
import Network
import System.IO (Handle, hClose, hFlush)

import Control.Monad.Reader
import Control.Monad.State
import Control.Monad.Trans

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


sendCommand :: [B.ByteString] -> IO Reply
sendCommand = undefined


main :: IO ()
main = withSocketsDo $ do
    
    h <- connectTo "127.0.0.1" (PortNumber 6379)

    pong1 <- runRedis h $ do
        p1 <- sendPing
        pong2 <- sendSet
        pong3 <- sendRequest ["FOOBAR", "foobarbaz"]
        pong4 <- sendRequest ["EXISTS", "mykey"]
        pong5 <- sendRequest ["GET", "mykey"]
        pong6 <- sendRequest ["GET", "doesnotexist"]
        pong7 <- sendRequest ["LRANGE", "mylist", "0", "2"]
    
        return [p1,pong3, pong7]

    print pong1
                
    hClose h
