{-# LANGUAGE RecordWildCards #-}

module Database.Redis.Connection (
    HostName,PortID(..),
    ConnectInfo(..),defaultConnectInfo,
    Connection(), connect
) where

import Control.Applicative
import Control.Monad.Reader
import Control.Concurrent
import qualified Data.Attoparsec as P
import qualified Data.ByteString as B
import Data.IORef
import Data.Pool
import Data.Time
import Network (HostName, PortID(..), connectTo)
import System.IO (Handle, hClose, hIsOpen, hSetBinaryMode,hFlush)
import System.IO.Unsafe (unsafeInterleaveIO)

import Database.Redis.Core
import Database.Redis.Commands (auth)
import Database.Redis.Reply

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

-- |Opens a connection to a Redis server designated by the given 'ConnectInfo'.
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

hGetReplies :: Handle -> IO [Reply]
hGetReplies h = lazyRead (Right B.empty)
  where
    lazyRead rest = unsafeInterleaveIO $ do
        parseResult <- either continueParse readAndParse rest
        case parseResult of
            P.Fail _ _ _   -> error "Redis: Connection closed"
            P.Partial cont -> lazyRead (Left cont)
            P.Done rest' r -> do
                rs <- lazyRead (Right rest')
                return (r:rs)    
    
    continueParse cont = cont <$> B.hGetSome h 4096
    
    readAndParse rest  = do    
        s <- if B.null rest
            then do
                hFlush h -- send any pending requests
                s <- B.hGetSome h 4096
                when (B.null s) $ errConnClosed
                return s
            else return rest
        return $ P.parse reply s

    errConnClosed = error "Redis: Connection closed"