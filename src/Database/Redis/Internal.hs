{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Database.Redis.Internal (
    module Network,
    ConnPool,
    newConnPool,
    disconnectConnPool,
    Redis(),
    runRedis,
    send,
    recv,
    sendRequest
) where

import Control.Applicative
import Control.Exception
import Control.Monad.Reader
import Control.Monad.State
import Control.Concurrent
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy.Char8 as LB
import Network (HostName, PortID(..), withSocketsDo)
import qualified Network (connectTo)
import System.IO (Handle, hFlush, hClose)

import Database.Redis.Reply
import Database.Redis.Request


------------------------------------------------------------------------------
-- Connection & Connection Pool
--
data Conn = Connected Handle [Reply]
          | Disconnected

data ConnPool = ConnPool Int HostName PortID (Chan Conn)


newConnPool :: Int -> HostName -> PortID -> IO ConnPool
newConnPool size host port = do
    conns <- newChan
    writeList2Chan conns $ replicate size Disconnected
    return $ ConnPool size host port conns

disconnectConnPool :: ConnPool -> IO ()
disconnectConnPool (ConnPool size _ _ conns) = do
    forM_ [1..size] $ \_ -> readChan conns >>= disconnect
    writeList2Chan conns $ replicate size Disconnected


connect :: HostName -> PortID -> Conn -> IO Conn
connect host port Disconnected = do
    h <- Network.connectTo host port
    Connected h . parseReply <$> LB.hGetContents h
connect _ _ c = return c

disconnect :: Conn -> IO Conn
disconnect (Connected h _) = hClose h >> return Disconnected
disconnect c               = return c


------------------------------------------------------------------------------
-- The Redis Monad
--
newtype Redis a = Redis (StateT Conn IO a)
    deriving (Monad, MonadIO, Functor)


runRedis :: ConnPool -> Redis a -> IO a
runRedis (ConnPool _ host port conns) (Redis r) = do
    c <- readChan conns >>= connect host port
    do
        (a, c') <- runStateT r c
        writeChan conns c'
        return a
      `onException`
        (disconnect c >>= writeChan conns)


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
