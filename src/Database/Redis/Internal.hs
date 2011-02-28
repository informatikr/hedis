{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Database.Redis.Internal (
    module Network,
    Connection,
    connectTo,
    Redis(..),
    runRedis,
    send,
    recv,
    sendRequest
) where

import Control.Monad.Reader
import Control.Monad.State
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy.Char8 as LB
import Network (HostName, PortID(..), withSocketsDo)
import qualified Network (connectTo)
import System.IO (Handle, hFlush)

import Database.Redis.Reply
import Database.Redis.Request


type Connection = Handle

connectTo :: HostName -> PortID -> IO Connection
connectTo host port = Network.connectTo host port


newtype Redis a = Redis (ReaderT Handle (StateT [Reply] IO) a)
    deriving (Monad, MonadIO)


runRedis :: Connection -> Redis a -> IO a
runRedis h (Redis r) = do
    replies <- fmap parseReply $ LB.hGetContents h
    evalStateT (runReaderT r h) replies


send :: [B.ByteString] -> Redis ()
send req = Redis $ do
    h <- ask
    liftIO $ B.hPut h $ renderRequest req
    liftIO $ hFlush h
    
recv :: Redis Reply
recv = Redis $ do
    (reply:rs) <- get
    put rs
    return reply

sendRequest :: [B.ByteString] -> Redis Reply
sendRequest req = send req >> recv
