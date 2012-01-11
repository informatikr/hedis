{-# LANGUAGE GeneralizedNewtypeDeriving,RecordWildCards #-}
module Database.Redis.Internal (
    HostName,PortID(..),
    ConnectInfo(..),defaultConnectInfo,
    Connection(), connect,
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
import Data.Pool
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
--  A 'Connection' is actually a pool of network connections.
newtype Connection = Conn (Pool (MVar (Handle, [Reply])))

-- |Information for connnecting to a Redis server.
data ConnectInfo = ConnInfo
    { connectHost :: HostName
    , connectPort :: PortID
    , connectAuth :: Maybe B.ByteString
    }

-- |Default information for connecting:
--
-- @
--  connectHost = \"localhost\"
--  connectPort = PortNumber 6379 -- Redis default port
--  connectAuth = Nothing         -- No password
-- @
--
defaultConnectInfo :: ConnectInfo
defaultConnectInfo = ConnInfo
    { connectHost = "localhost"
    , connectPort = PortNumber 6379
    , connectAuth = Nothing
    }

-- |Opens a connection to a Redis server designated by the given 'ConnectInfo'.
connect :: ConnectInfo -> IO Connection
connect ConnInfo{..} = do
    let maxIdleTime    = 10
        maxConnections = 50
    Conn <$> createPool create destroy 1 maxIdleTime maxConnections
  where
    create = do
        h       <- connectTo connectHost connectPort
        replies <- parseReply <$> LB.hGetContents h
        newMVar (h, replies)
    
    destroy conn = withMVar conn $ \(h,_) -> do
        open <- hIsOpen h
        when open (hClose h)

------------------------------------------------------------------------------
-- The Redis Monad
--

-- |All Redis commands run in the 'Redis' monad.
newtype Redis a = Redis (RWST Handle () [Reply] IO a)
    deriving (Monad, MonadIO, Functor, Applicative)

-- |Interact with a Redis datastore specified by the given 'Connection'.
--
--  Each call of 'runRedis' takes a network connection from the 'Connection'
--  pool and runs the given 'Redis' action. Calls to 'runRedis' may thus block, --  while all connections from the pool are in use.
runRedis :: Connection -> Redis a -> IO a
runRedis (Conn pool) (Redis redis) =
    withResource pool $ \conn ->
    modifyMVar conn $ \(h,rs) -> do
        (a,rs',_) <- runRWST redis h rs
        return ((h,rs'),a)

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
