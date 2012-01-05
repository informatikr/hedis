{-# LANGUAGE GeneralizedNewtypeDeriving, RecordWildCards #-}
module Database.Redis.Internal (
    HostName,PortID(..),
    RedisConn(), connect, disconnect,
    Redis(),runRedis,
    send,
    recv,
    sendRequest
) where

import Control.Applicative
import Control.Monad.RWS
import Control.Concurrent
import Control.Exception
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy.Char8 as LB
import Network (HostName, PortID(..), connectTo)
import System.IO (Handle, hFlush, hClose)

import Database.Redis.Reply
import Database.Redis.Request
import Database.Redis.Types

------------------------------------------------------------------------------
-- Connection
--

-- |Connection to a Redis server. Use the 'connect' function to create one.
data RedisConn = Conn { connHandle :: Handle, connReplies :: MVar [Reply] }

-- |Opens a connection to a Redis server at the given host and port.
connect :: HostName -> PortID -> IO RedisConn
connect host port = do
    h       <- connectTo host port
    replies <- parseReply <$> LB.hGetContents h
    Conn h <$> newMVar replies

-- |Close the given connection.
disconnect :: RedisConn -> IO ()
disconnect (Conn h _) = hClose h


------------------------------------------------------------------------------
-- The Redis Monad
--
newtype Redis a = Redis (RWST Handle () [Reply] IO a)
    deriving (Monad, MonadIO, Functor, Applicative)

runRedis :: RedisConn -> Redis a -> IO a
runRedis Conn{..} (Redis redis) = do
    replies <- takeMVar connReplies
    (a,replies',_) <- runRWST redis connHandle replies
    putMVar connReplies replies'
    return a

send :: [B.ByteString] -> Redis ()
send req = Redis $ do
    h <- ask
    liftIO $ do
        B.hPut h $ renderRequest req
        hFlush h

recv :: Redis Reply
recv = Redis $ do
    -- head/tail avoids forcing the ':' constructor, enabling automatic
    -- pipelining.
    rs <- get
    put (tail rs)
    return (head rs)

-- |Send a request to the Redis server.
sendRequest :: (RedisResult a) => [B.ByteString] -> Redis a
sendRequest req = do
    reply <- send req >> recv
    either (liftIO . throwIO) return (decode reply)
