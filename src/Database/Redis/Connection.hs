{-# LANGUAGE RecordWildCards, DeriveDataTypeable #-}

module Database.Redis.Connection (
    HostName,PortID(PortNumber,UnixSocket),
    ConnectInfo(..),defaultConnectInfo,
    Connection(), connect,
    ConnectionLostException(..)
) where

import Prelude hiding (catch)
import Control.Applicative
import Control.Monad.Reader
import Control.Concurrent
import Control.Exception (Exception, catch, throwIO)
import qualified Data.Attoparsec as P
import qualified Data.ByteString as B
import Data.IORef
import Data.Pool
import Data.Time
import Data.Typeable
import Network (HostName, PortID(..), connectTo)
import System.IO (Handle, hClose, hIsOpen, hSetBinaryMode, hFlush)
import System.IO.Unsafe (unsafeInterleaveIO)

import Database.Redis.Core
import Database.Redis.Commands (auth)
import Database.Redis.Reply

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
        h   <- connectTo connectHost connectPort
        rs  <- hGetReplies h >>= newIORef
        hSetBinaryMode h True
        let conn = (h,rs)
        maybe (return ())
            (\pass -> runRedisInternal conn (auth pass) >> return ())
            connectAuth
        newMVar conn

    destroy conn = withMVar conn $ \(h,_) -> do
        open <- hIsOpen h
        when open (hClose h)

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
hGetReplies h = lazyRead B.empty
  where
    lazyRead rest = unsafeInterleaveIO $ do        
        parseResult <- P.parseWith readMore reply rest
        case parseResult of
            P.Fail _ _ _   -> error "Hedis: reply parse failed"
            P.Partial _    -> error "Hedis: parseWith returned Partial"
            P.Done rest' r -> do
                rs <- lazyRead rest'
                return (r:rs)

    readMore = do
        hFlush h -- send any pending requests
        B.hGetSome h maxRead `catchIOError` const errConnClosed

    maxRead       = 4*1024
    errConnClosed = throwIO ConnectionLost

    catchIOError :: IO a -> (IOError -> IO a) -> IO a
    catchIOError = catch
