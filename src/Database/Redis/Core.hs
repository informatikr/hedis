module Database.Redis.Core (
    Redis(),runRedis,runRedis',
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
import System.IO (Handle, hFlush)

import Database.Redis.Reply
import Database.Redis.Request
import Database.Redis.Types


-- |Interact with a Redis datastore specified by the given 'Connection'.
--
--  Each call of 'runRedis' takes a network connection from the 'Connection'
--  pool and runs the given 'Redis' action. Calls to 'runRedis' may thus block, --  while all connections from the pool are in use.
runRedis :: Connection -> Redis a -> IO a
runRedis (Conn pool) redis =
    withResource pool $ \conn ->
    withMVar conn $ \conn' -> runRedis' conn' redis

-- |Internal version of 'runRedis' that does not depend on the 'Connection'
--  abstraction. Used to run the AUTH command when connecting. 
runRedis' :: (Handle,IORef [Reply]) -> Redis a -> IO a
runRedis' conn (Redis redis) = runReaderT redis conn

send :: [B.ByteString] -> Redis ()
send req = Redis $ do
    h <- asks fst
    liftIO $ do
        {-# SCC "send.hPut" #-} B.hPut h $ renderRequest req
        {-# SCC "send.hFlush" #-} hFlush h

recv :: Redis Reply
recv = Redis $ do
    -- head/tail avoids forcing the ':' constructor, enabling automatic
    -- pipelining.
    replies <- asks snd
    liftIO $ atomicModifyIORef replies (tail &&& head)

sendRequest :: (RedisResult a) => [B.ByteString] -> Redis (Either Reply a)
sendRequest req = decode <$> (send req >> recv)
