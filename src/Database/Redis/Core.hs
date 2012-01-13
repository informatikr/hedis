{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Database.Redis.Core (
    Connection(..),
    Redis(),runRedis,runRedisInternal,
    send,
    recv,
    sendRequest
) where

import Control.Applicative
import Control.Arrow
import Control.Monad.Reader
import Control.Concurrent
import qualified Data.ByteString as B
import Data.IORef
import Data.Pool
import System.IO (Handle)

import Database.Redis.Reply
import Database.Redis.Request
import Database.Redis.Types

-- |Connection to a Redis server. Use the 'connect' function to create one.
--
--  A 'Connection' is actually a pool of network connections.
newtype Connection = Conn (Pool (MVar (Handle, IORef [Reply])))

-- |All Redis commands run in the 'Redis' monad.
newtype Redis a = Redis (ReaderT RedisEnv IO a)
    deriving (Monad, MonadIO, Functor, Applicative)

type RedisEnv = (Handle, IORef [Reply])

askHandle :: ReaderT RedisEnv IO Handle
askHandle = asks fst

askReplies :: ReaderT RedisEnv IO (IORef [Reply])
askReplies = asks snd

-- |Interact with a Redis datastore specified by the given 'Connection'.
--
--  Each call of 'runRedis' takes a network connection from the 'Connection'
--  pool and runs the given 'Redis' action. Calls to 'runRedis' may thus block, --  while all connections from the pool are in use.
runRedis :: Connection -> Redis a -> IO a
runRedis (Conn pool) redis =
    withResource pool $ \conn ->
    withMVar conn $ \conn' -> runRedisInternal conn' redis

-- |Internal version of 'runRedis' that does not depend on the 'Connection'
--  abstraction. Used to run the AUTH command when connecting. 
runRedisInternal :: RedisEnv -> Redis a -> IO a
runRedisInternal env (Redis redis) = runReaderT redis env

send :: [B.ByteString] -> Redis ()
send req = Redis $ do
    h <- askHandle
    -- hFlushing the handle is done while reading replies.
    liftIO $ {-# SCC "send.hPut" #-} B.hPut h (renderRequest req)

recv :: Redis Reply
recv = Redis $ do
    -- head/tail avoids forcing the ':' constructor, enabling automatic
    -- pipelining.
    rs <- askReplies
    liftIO $ atomicModifyIORef rs (tail &&& head)

sendRequest :: (RedisResult a) => [B.ByteString] -> Redis (Either Reply a)
sendRequest req = decode <$> (send req >> recv)
