{-# LANGUAGE OverloadedStrings, GeneralizedNewtypeDeriving, RecordWildCards,
    MultiParamTypeClasses, FunctionalDependencies, FlexibleInstances #-}

module Database.Redis.Core (
    Connection, connect,
    ConnectInfo(..), defaultConnectInfo,
    Redis(),runRedis,
    RedisCtx(..), MonadRedis(..),
    send, recv, sendRequest,
    auth
) where

import Prelude hiding (catch)
import Control.Applicative
import Control.Monad.Reader
import qualified Data.ByteString as B
import Data.Pool
import Data.Time
import Network

import Database.Redis.Protocol
import qualified Database.Redis.ProtocolPipelining as PP
import Database.Redis.Types


--------------------------------------------------------------------------------
-- The Redis Monad
--

-- |Context for normal command execution, outside of transactions. Use
--  'runRedis' to run actions of this type.
--
--  In this context, each result is wrapped in an 'Either' to account for the
--  possibility of Redis returning an 'Error' reply.
newtype Redis a = Redis (ReaderT (PP.Connection Reply) IO a)
    deriving (Monad, MonadIO, Functor, Applicative)

-- |This class captures the following behaviour: In a context @m@, a command
--  will return it's result wrapped in a \"container\" of type @f@.
--
--  Please refer to the Command Type Signatures section of this page for more
--  information.
class (MonadRedis m) => RedisCtx m f | m -> f where
    returnDecode :: RedisResult a => Reply -> m (f a)

instance RedisCtx Redis (Either Reply) where
    returnDecode = return . decode

class (Monad m) => MonadRedis m where
    liftRedis :: Redis a -> m a

instance MonadRedis Redis where
    liftRedis = id

-- |Interact with a Redis datastore specified by the given 'Connection'.
--
--  Each call of 'runRedis' takes a network connection from the 'Connection'
--  pool and runs the given 'Redis' action. Calls to 'runRedis' may thus block
--  while all connections from the pool are in use.
runRedis :: Connection -> Redis a -> IO a
runRedis (Conn pool) redis =
    withResource pool $ \conn -> runRedisInternal conn redis

-- |Internal version of 'runRedis' that does not depend on the 'Connection'
--  abstraction. Used to run the AUTH command when connecting. 
runRedisInternal :: PP.Connection Reply -> Redis a -> IO a
runRedisInternal env (Redis redis) = runReaderT redis env


recv :: (MonadRedis m) => m Reply
recv = liftRedis $ Redis $ ask >>= liftIO . PP.recv

send :: (MonadRedis m) => [B.ByteString] -> m ()
send req = liftRedis $ Redis $ do
    conn <- ask
    liftIO $ PP.send conn (renderRequest req)

-- |'sendRequest' can be used to implement commands from experimental
--  versions of Redis. An example of how to implement a command is given
--  below.
--
-- @
-- -- |Redis DEBUG OBJECT command
-- debugObject :: ByteString -> 'Redis' (Either 'Reply' ByteString)
-- debugObject key = 'sendRequest' [\"DEBUG\", \"OBJECT\", key]
-- @
--
sendRequest :: (RedisCtx m f, RedisResult a)
    => [B.ByteString] -> m (f a)
sendRequest req = do
    r <- liftRedis $ Redis $ do
        conn <- ask
        liftIO $ PP.request conn (renderRequest req)
    returnDecode r


--------------------------------------------------------------------------------
-- Connection
--

-- |A threadsafe pool of network connections to a Redis server. Use the
--  'connect' function to create one.
newtype Connection = Conn (Pool (PP.Connection Reply))

-- |Information for connnecting to a Redis server.
--
-- It is recommended to not use the 'ConnInfo' data constructor directly.
-- Instead use 'defaultConnectInfo' and update it with record syntax. For
-- example to connect to a password protected Redis server running on localhost
-- and listening to the default port:
-- 
-- @
-- myConnectInfo :: ConnectInfo
-- myConnectInfo = defaultConnectInfo {connectAuth = Just \"secret\"}
-- @
--
data ConnectInfo = ConnInfo
    { connectHost           :: HostName
    , connectPort           :: PortID
    , connectAuth           :: Maybe B.ByteString
    -- ^ When the server is protected by a password, set 'connectAuth' to 'Just'
    --   the password. Each connection will then authenticate by the 'auth'
    --   command.
    , connectMaxConnections :: Int
    -- ^ Maximum number of connections to keep open. The smallest acceptable
    --   value is 1.
    , connectMaxIdleTime    :: NominalDiffTime
    -- ^ Amount of time for which an unused connection is kept open. The
    --   smallest acceptable value is 0.5 seconds. If the @timeout@ value in
    --   your redis.conf file is non-zero, it should be larger than
    --   'connectMaxIdleTime'.
    }

-- |Default information for connecting:
--
-- @
--  connectHost           = \"localhost\"
--  connectPort           = PortNumber 6379 -- Redis default port
--  connectAuth           = Nothing         -- No password
--  connectMaxConnections = 50              -- Up to 50 connections
--  connectMaxIdleTime    = 30              -- Keep open for 30 seconds
-- @
--
defaultConnectInfo :: ConnectInfo
defaultConnectInfo = ConnInfo
    { connectHost           = "localhost"
    , connectPort           = PortNumber 6379
    , connectAuth           = Nothing
    , connectMaxConnections = 50
    , connectMaxIdleTime    = 30
    }

-- |Opens a 'Connection' to a Redis server designated by the given
--  'ConnectInfo'.
connect :: ConnectInfo -> IO Connection
connect ConnInfo{..} = Conn <$>
    createPool create destroy 1 connectMaxIdleTime connectMaxConnections
  where
    create = do
        conn <- PP.connect connectHost connectPort reply
        maybe (return ())
            (void . runRedisInternal conn . auth)
            connectAuth
        return conn

    destroy = PP.disconnect

-- The AUTH command. It has to be here because it is used in 'connect'.
auth
    :: B.ByteString -- ^ password
    -> Redis (Either Reply Status)
auth password = sendRequest ["AUTH", password]
