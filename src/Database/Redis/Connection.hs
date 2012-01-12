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

import Database.Redis.Core (runRedis')
import Database.Redis.Commands (auth)
import Database.Redis.Reply
import Database.Redis.Types

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
        h   <- connectTo connectHost connectPort
        rs' <- parseReply <$> {-# SCC "LB.hgetContents" #-} LB.hGetContents h
        rs  <- newIORef rs'
        let conn = (h,rs)
        maybe (return ())
            (\pass -> runRedis' conn (auth pass) >> return ())
            connectAuth
        hSetBinaryMode h True
        newMVar conn

    destroy conn = withMVar conn $ \(h,_) -> do
        open <- hIsOpen h
        when open (hClose h)
