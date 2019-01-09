{-# LANGUAGE OverloadedStrings, GeneralizedNewtypeDeriving, RecordWildCards,
    MultiParamTypeClasses, FunctionalDependencies, FlexibleInstances, CPP,
    DeriveDataTypeable #-}

module Database.Redis.Core (
    Connection(..), ConnectError(..), connect, checkedConnect, disconnect,
    withConnect, withCheckedConnect,
    defaultRedisPort,
    ConnectInfo(..), defaultConnectInfo,
    Redis(), runRedis, unRedis, reRedis,
    RedisCtx(..), MonadRedis(..),
    send, recv, sendRequest,
    auth, select, ping
) where

import Prelude
#if __GLASGOW_HASKELL__ < 710
import Control.Applicative
#endif
import Control.Exception
import Control.Monad.Reader
import qualified Data.ByteString as B
import Data.IORef
import Data.Pool
import Data.Time
import Data.Typeable
import qualified Network.Socket as NS
import Network.TLS (ClientParams)

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
newtype Redis a = Redis (ReaderT RedisEnv IO a)
    deriving (Monad, MonadIO, Functor, Applicative)

data RedisEnv = Env { envConn :: PP.Connection, envLastReply :: IORef Reply }

-- |This class captures the following behaviour: In a context @m@, a command
--  will return its result wrapped in a \"container\" of type @f@.
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

-- |Deconstruct Redis constructor.
--
--  'unRedis' and 'reRedis' can be used to define instances for
--  arbitrary typeclasses.
-- 
--  WARNING! These functions are considered internal and no guarantee
--  is given at this point that they will not break in future.
unRedis :: Redis a -> ReaderT RedisEnv IO a
unRedis (Redis r) = r

-- |Reconstruct Redis constructor.
reRedis :: ReaderT RedisEnv IO a -> Redis a
reRedis r = Redis r

-- |Internal version of 'runRedis' that does not depend on the 'Connection'
--  abstraction. Used to run the AUTH command when connecting.
runRedisInternal :: PP.Connection -> Redis a -> IO a
runRedisInternal conn (Redis redis) = do
  -- Dummy reply in case no request is sent.
  ref <- newIORef (SingleLine "nobody will ever see this")
  r <- runReaderT redis (Env conn ref)
  -- Evaluate last reply to keep lazy IO inside runRedis.
  readIORef ref >>= (`seq` return ())
  return r

setLastReply :: Reply -> ReaderT RedisEnv IO ()
setLastReply r = do
  ref <- asks envLastReply
  lift (writeIORef ref r)

recv :: (MonadRedis m) => m Reply
recv = liftRedis $ Redis $ do
  conn <- asks envConn
  r <- liftIO (PP.recv conn)
  setLastReply r
  return r

send :: (MonadRedis m) => [B.ByteString] -> m ()
send req = liftRedis $ Redis $ do
    conn <- asks envConn
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
    r' <- liftRedis $ Redis $ do
        conn <- asks envConn
        r <- liftIO $ PP.request conn (renderRequest req)
        setLastReply r
        return r
    returnDecode r'


--------------------------------------------------------------------------------
-- Connection
--

-- |A threadsafe pool of network connections to a Redis server. Use the
--  'connect' function to create one.
newtype Connection = Conn (Pool PP.Connection)

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
    { connectSockAddr       :: NS.SockAddr
    , connectAuth           :: Maybe B.ByteString
    -- ^ When the server is protected by a password, set 'connectAuth' to 'Just'
    --   the password. Each connection will then authenticate by the 'auth'
    --   command.
    , connectDatabase       :: Integer
    -- ^ Each connection will 'select' the database with the given index.
    , connectMaxConnections :: Int
    -- ^ Maximum number of connections to keep open. The smallest acceptable
    --   value is 1.
    , connectMaxIdleTime    :: NominalDiffTime
    -- ^ Amount of time for which an unused connection is kept open. The
    --   smallest acceptable value is 0.5 seconds. If the @timeout@ value in
    --   your redis.conf file is non-zero, it should be larger than
    --   'connectMaxIdleTime'.
    , connectTimeout        :: Maybe NominalDiffTime
    -- ^ Optional timeout until connection to Redis gets
    --   established. 'ConnectTimeoutException' gets thrown if no socket
    --   get connected in this interval of time.
    , connectTLSParams      :: Maybe ClientParams
    -- ^ Optional TLS parameters. TLS will be enabled if this is provided.
    } deriving Show

data ConnectError = ConnectAuthError Reply
                  | ConnectSelectError Reply
    deriving (Eq, Show, Typeable)

instance Exception ConnectError

defaultRedisPort :: NS.PortNumber
defaultRedisPort = 6379

-- |Default information for connecting:
--
-- @
--  connectSockAddr       = SockAddrInet 6379 (tupleToHostAddress (127, 0, 0, 1))
                                            -- 6379 is the default Redis port
--  connectAuth           = Nothing         -- No password
--  connectDatabase       = 0               -- SELECT database 0
--  connectMaxConnections = 50              -- Up to 50 connections
--  connectMaxIdleTime    = 30              -- Keep open for 30 seconds
--  connectTimeout        = Nothing         -- Don't add timeout logic
--  connectTLSParams      = Nothing         -- Do not use TLS
-- @
--
defaultConnectInfo :: ConnectInfo
defaultConnectInfo = ConnInfo
    { connectSockAddr       = NS.SockAddrInet defaultRedisPort (NS.tupleToHostAddress (127, 0, 0, 1))
    , connectAuth           = Nothing
    , connectDatabase       = 0
    , connectMaxConnections = 50
    , connectMaxIdleTime    = 30
    , connectTimeout        = Nothing
    , connectTLSParams      = Nothing
    }

-- |Constructs a 'Connection' pool to a Redis server designated by the 
--  given 'ConnectInfo'. The first connection is not actually established
--  until the first call to the server.
connect :: ConnectInfo -> IO Connection
connect ConnInfo{..} = Conn <$>
    createPool create destroy 1 connectMaxIdleTime connectMaxConnections
  where
    create = do
        let timeoutOptUs =
              round . (1000000 *) <$> connectTimeout
        conn <- PP.connect connectSockAddr timeoutOptUs
        conn' <- case connectTLSParams of
                   Nothing -> return conn
                   Just tlsParams -> PP.enableTLS tlsParams conn
        PP.beginReceiving conn'

        runRedisInternal conn' $ do
            -- AUTH
            case connectAuth of
                Nothing   -> return ()
                Just pass -> do
                  resp <- auth pass
                  case resp of
                    Left r -> liftIO $ throwIO $ ConnectAuthError r
                    _      -> return ()
            -- SELECT
            when (connectDatabase /= 0) $ do
              resp <- select connectDatabase
              case resp of
                  Left r -> liftIO $ throwIO $ ConnectSelectError r
                  _      -> return ()
        return conn'

    destroy = PP.disconnect

-- |Constructs a 'Connection' pool to a Redis server designated by the
--  given 'ConnectInfo', then tests if the server is actually there. 
--  Throws an exception if the connection to the Redis server can't be
--  established.
checkedConnect :: ConnectInfo -> IO Connection
checkedConnect connInfo = do
    conn <- connect connInfo
    runRedis conn $ void ping
    return conn

-- |Destroy all idle resources in the pool.
disconnect :: Connection -> IO ()
disconnect (Conn pool) = destroyAllResources pool

-- | Memory bracket around 'connect' and 'disconnect'. 
withConnect :: ConnectInfo -> (Connection -> IO c) -> IO c
withConnect connInfo = bracket (connect connInfo) disconnect

-- | Memory bracket around 'checkedConnect' and 'disconnect'
withCheckedConnect :: ConnectInfo -> (Connection -> IO c) -> IO c
withCheckedConnect connInfo = bracket (checkedConnect connInfo) disconnect

-- The AUTH command. It has to be here because it is used in 'connect'.
auth
    :: B.ByteString -- ^ password
    -> Redis (Either Reply Status)
auth password = sendRequest ["AUTH", password]

-- The SELECT command. Used in 'connect'.
select
    :: RedisCtx m f
    => Integer -- ^ index
    -> m (f Status)
select ix = sendRequest ["SELECT", encode ix]

-- The PING command. Used in 'checkedConnect'.
ping
    :: (RedisCtx m f)
    => m (f Status)
ping  = sendRequest (["PING"] )
