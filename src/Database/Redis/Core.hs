module Database.Redis.Core (
    Redis(),runRedis,runRedis',
    send,
    recv,
    sendRequest
) where

import Control.Applicative
import Control.Monad.RWS
import Control.Concurrent
import qualified Data.ByteString as B
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
    modifyMVar conn $ \(h,rs) -> do
        (rs',a) <- runRedis' h rs redis
        return ((h,rs'),a)

-- |Internal version of 'runRedis' that does not depend on the 'Connection'
--  abstraction. Used to run the AUTH command when connecting. 
runRedis' :: Handle -> [Reply] -> Redis a -> IO ([Reply],a)
runRedis' h rs (Redis redis) = do
    (a,rs',_) <- runRWST redis h rs
    return (rs',a)

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

sendRequest :: (RedisResult a) => [B.ByteString] -> Redis (Either Reply a)
sendRequest req = decode <$> (send req >> recv)
