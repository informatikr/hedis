{-# LANGUAGE GeneralizedNewtypeDeriving #-}
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
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy.Char8 as LB
import Network (HostName, PortID(..), connectTo)
import System.IO (Handle, hFlush, hClose, hIsOpen)

import Database.Redis.Reply
import Database.Redis.Request
import Database.Redis.Types

------------------------------------------------------------------------------
-- Connection
--

-- |Connection to a Redis server. Use the 'connect' function to create one.
--
--  A 'RedisConn' can only be used by a single thread at a time. This means that
--  calls to 'runRedis' or 'disconnet' may block when the 'RedisConn' is shared
--  between multiple threads.
data RedisConn = Conn (MVar (Handle, [Reply]))

withConn :: RedisConn
         -> (Handle -> [Reply] -> IO ([Reply], a))
         -> IO a
withConn (Conn conn) f = do
    (h,rs)     <- takeMVar conn
    (rs',a) <- f h rs
    putMVar conn (h,rs')
    return a

-- |Opens a connection to a Redis server at the given host and port.
connect :: HostName -> PortID -> IO RedisConn
connect host port = do
    h       <- connectTo host port
    replies <- parseReply <$> LB.hGetContents h
    Conn <$> newMVar (h, replies)

-- |Close the given connection.
--
--  May block when the given 'RedisConn' is shared between multiple threads. The
-- 'RedisConn' can not be re-used.
disconnect :: RedisConn -> IO ()
disconnect conn = withConn conn $ \h rs -> do
    open <- hIsOpen h
    when open (hClose h)
    return (rs, ())


------------------------------------------------------------------------------
-- The Redis Monad
--
newtype Redis a = Redis (RWST Handle () [Reply] IO a)
    deriving (Monad, MonadIO, Functor, Applicative)

-- |Interact with a Redis datastore specified by the given 'RedisConn'.
--
--  May block when the given 'RedisConn' is shared between multiple threads.
runRedis :: RedisConn -> Redis a -> IO a
runRedis conn (Redis redis) = withConn conn $ \h rs -> do
    open <- hIsOpen h
    if open
        then do
            (a,rs',_) <- runRWST redis h rs
            return (rs',a)
        else error "Redis: disconnected"

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

-- |Sends a request to the Redis server, returning the 'decode'd reply.
sendRequest :: (RedisResult a) => [B.ByteString] -> Redis (Either Reply a)
sendRequest req = decode <$> (send req >> recv)
