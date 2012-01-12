{-# LANGUAGE RecordWildCards #-}

module Database.Redis.Connection (
    HostName,PortID(..),
    ConnectInfo(..),defaultConnectInfo,
    Connection(), connect
) where

import Control.Applicative
import Control.Monad.Reader
import Control.Concurrent
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy.Char8 as LB
import Data.IORef
import Data.Pool
import Network (HostName, PortID(..), connectTo)
import System.IO (hClose, hIsOpen, hSetBinaryMode)

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
        h   <- connectTo connectHost connectPort
        rs' <- parseReply <$> {-# SCC "LB.hgetContents" #-} LB.hGetContents h
        rs  <- newIORef rs'
        let conn = (h,rs)
        maybe (return ())
            (\pass -> runRedisInternal conn (auth pass) >> return ())
            connectAuth
        hSetBinaryMode h True
        newMVar conn

    destroy conn = withMVar conn $ \(h,_) -> do
        open <- hIsOpen h
        when open (hClose h)
