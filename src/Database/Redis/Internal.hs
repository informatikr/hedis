{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Database.Redis.Internal (
    module Network,
    Connection,
    connectTo,
    disconnect,
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
import System.IO (Handle, hFlush, hClose)

import Database.Redis.Reply
import Database.Redis.Request


data Connection = Connected Handle [Reply]
                | Disconnected


connectTo :: HostName -> PortID -> IO Connection
connectTo host port = do
    h <- Network.connectTo host port
    return $ Connected h []

disconnect :: Connection -> IO ()
disconnect (Connected h _) = hClose h
disconnect _               = return ()


newtype Redis a = Redis (StateT Connection IO a)
    deriving (Monad, MonadIO, Functor)


runRedis :: Connection -> Redis a -> IO a
runRedis Disconnected    _r        = error "Disconnected"
runRedis (Connected h _) (Redis r) = do
    replies <- fmap parseReply $ LB.hGetContents h
    evalStateT r $ Connected h replies


send :: [B.ByteString] -> Redis ()
send req = Redis $ do
    (Connected h _) <- get
    liftIO $ B.hPut h $ renderRequest req
    liftIO $ hFlush h
    
        
recv :: Redis Reply
recv = Redis $ do
    (Connected h rs) <- get
    put $ Connected h (tail rs)
    return $ head rs

sendRequest :: [B.ByteString] -> Redis Reply
sendRequest req = send req >> recv
