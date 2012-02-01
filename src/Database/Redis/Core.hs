{-# LANGUAGE OverloadedStrings, GeneralizedNewtypeDeriving, RecordWildCards,
    DeriveDataTypeable #-}

module Database.Redis.Core (
    Connection(..), connect,
    ConnectInfo(..), defaultConnectInfo,
    Redis(),runRedis,
    send, recv, sendRequest,
    HostName, PortID(..),
    ConnectionLostException(..),
    auth
) where

import Prelude hiding (catch)
import Control.Applicative
import Control.Monad.Reader
import Control.Concurrent
import Control.Concurrent.STM
import Control.Exception
import qualified Data.Attoparsec as P
import qualified Data.ByteString as B
import Data.Pool
import Data.Time
import Data.Typeable
import Network
import System.IO
import System.IO.Unsafe

import Database.Redis.Reply
import Database.Redis.Request
import Database.Redis.Types


--------------------------------------------------------------------------------
-- The Redis Monad
--

-- |All Redis commands run in the 'Redis' monad.
newtype Redis a = Redis (ReaderT RedisEnv IO a)
    deriving (Monad, MonadIO, Functor, Applicative)

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


--------------------------------------------------------------------------------
-- Redis Environment.
--

-- |The per-connection environment the 'Redis' monad can read from.
--
--  Create with 'newEnv'. Modified by 'recv' and 'send'.
data RedisEnv = Env
    { envHandle   :: Handle       -- ^ Connection socket-handle.
    , envReplies  :: TVar [Reply] -- ^ Reply thunks.
    , envThunkCnt :: TVar Integer -- ^ Number of thunks in 'envThunkChan'.
    , envEvalTId  :: ThreadId     -- ^ 'ThreadID' of the evaluator thread.
    }

-- |Create a new 'RedisEnv'
newEnv :: Handle -> IO RedisEnv
newEnv envHandle = do
    replies     <- lazify <$> hGetReplies envHandle
    envReplies  <- newTVarIO replies
    envThunkCnt <- newTVarIO 0
    envEvalTId  <- forkIO $ forceThunks envThunkCnt replies
    return Env{..}
  where
    lazify rs = head rs : lazify (tail rs)

forceThunks :: TVar Integer -> [Reply] -> IO ()
forceThunks thunkCnt = go
  where
    go []     = return ()
    go (r:rs) = do
        -- wait for a thunk
        atomically $ do
            cnt <- readTVar thunkCnt
            guard (cnt > 0)
            writeTVar thunkCnt (cnt-1)
        r `seq` go rs

recv :: Redis Reply
recv = Redis $ do
    Env{..} <- ask
    liftIO $ atomically $ do
        -- limit the amount of reply-thunks per connection.
        cnt <- readTVar envThunkCnt
        guard $ cnt < 1000
        writeTVar envThunkCnt (cnt+1)
        r:rs <- readTVar envReplies
        writeTVar envReplies rs
        return r

send :: [B.ByteString] -> Redis ()
send req = Redis $ do
    h <- asks envHandle
    -- hFlushing the handle is done while reading replies.
    liftIO $ {-# SCC "send.hPut" #-} B.hPut h (renderRequest req)

sendRequest :: (RedisResult a) => [B.ByteString] -> Redis (Either Reply a)
sendRequest req = decode <$> (send req >> recv)


--------------------------------------------------------------------------------
-- Connection
--

-- |A threadsafe pool of network connections to a Redis server. Use the
--  'connect' function to create one.
newtype Connection = Conn (Pool (MVar RedisEnv))

data ConnectionLostException = ConnectionLost
    deriving (Show, Typeable)

instance Exception ConnectionLostException

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
    --   smallest acceptable value is 0.5 seconds.
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
        h <- connectTo connectHost connectPort
        hSetBinaryMode h True
        conn <- newEnv h
        maybe (return ())
            (\pass -> runRedisInternal conn (auth pass) >> return ())
            connectAuth
        newMVar conn

    destroy conn = withMVar conn $ \Env{..} -> do
        open <- hIsOpen envHandle
        when open (hClose envHandle)
        killThread envEvalTId

-- |Read all the 'Reply's from the Handle and return them as a lazy list.
--
--  The actual reading and parsing of each 'Reply' is deferred until the spine
--  of the list is evaluated up to that 'Reply'. Each 'Reply' is cons'd in front
--  of the (unevaluated) list of all remaining replies.
--
--  'unsafeInterleaveIO' only evaluates it's result once, making this function 
--  thread-safe. 'Handle' as implemented by GHC is also threadsafe, it is safe
--  to call 'hFlush' here. The list constructor '(:)' must be called from
--  /within/ unsafeInterleaveIO, to keep the replies in correct order.
hGetReplies :: Handle -> IO [Reply]
hGetReplies h = go B.empty
  where
    go rest = unsafeInterleaveIO $ do        
        parseResult <- P.parseWith readMore reply rest
        case parseResult of
            P.Fail _ _ _   -> errConnClosed
            P.Partial _    -> error "Hedis: parseWith returned Partial"
            P.Done rest' r -> do
                rs <- go rest'
                return (r:rs)

    readMore = do
        hFlush h -- send any pending requests
        B.hGetSome h maxRead `catchIOError` const errConnClosed

    maxRead       = 4*1024
    errConnClosed = throwIO ConnectionLost

    catchIOError :: IO a -> (IOError -> IO a) -> IO a
    catchIOError = catch

-- The AUTH command. It has to be here because it is used in 'connect'.
auth
    :: B.ByteString -- ^ password
    -> Redis (Either Reply Status)
auth password = sendRequest ["AUTH", password]
