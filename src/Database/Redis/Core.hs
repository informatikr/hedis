{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Database.Redis.Core (
    Connection(..), RedisEnv(..),
    Redis(),runRedis,runRedisInternal,
    send,
    recv,
    sendRequest
) where

import Control.Applicative
import Control.Monad.Reader
import Control.Concurrent
import Control.Concurrent.STM
import qualified Data.ByteString as B
import Data.Pool
import System.IO (Handle)

import Database.Redis.Reply
import Database.Redis.Request
import Database.Redis.Types

-- |A threadsafe pool of network connections to a Redis server. Use the
--  'connect' function to create one.
newtype Connection = Conn (Pool (MVar RedisEnv))

-- |All Redis commands run in the 'Redis' monad.
newtype Redis a = Redis (ReaderT RedisEnv IO a)
    deriving (Monad, MonadIO, Functor, Applicative)

data RedisEnv = Env
    { envHandle    :: Handle
    , envReplies   :: TVar [Reply]
    , envThunkChan :: TChan Reply
    , envThunkCnt  :: TVar Integer
    }

-- |Interact with a Redis datastore specified by the given 'Connection'.
--
--  Each call of 'runRedis' takes a network connection from the 'Connection'
--  pool and runs the given 'Redis' action. Calls to 'runRedis' may thus block
--  while all connections from the pool are in use.
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
    h <- asks envHandle
    -- hFlushing the handle is done while reading replies.
    liftIO $ {-# SCC "send.hPut" #-} B.hPut h (renderRequest req)

recv :: Redis Reply
recv = Redis $ do
    -- head/tail avoids forcing the ':' constructor, enabling automatic
    -- pipelining.
    replies <- asks envReplies
    chan <- asks envThunkChan
    thunkCnt <- asks envThunkCnt
    liftIO $ atomically $ do
        
        cnt <- readTVar thunkCnt
        guard $ cnt < 1000
                
        rs <- readTVar replies
        writeTVar replies (tail rs)
        let r = head rs
        writeTChan chan r
        writeTVar thunkCnt (cnt + 1)
        return r

sendRequest :: (RedisResult a) => [B.ByteString] -> Redis (Either Reply a)
sendRequest req = decode <$> (send req >> recv)
