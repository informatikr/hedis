{-# LANGUAGE OverloadedStrings #-}

module Database.Redis (

    -- * The Redis Monad
    Redis(), runRedis,
    
    -- * Connection
    Connection, connect,
    ConnectInfo(..),defaultConnectInfo,
    HostName,PortID(..),
    
    -- * Commands
	module Database.Redis.Commands,

    -- * Pub\/Sub
    module Database.Redis.PubSub,

    -- * Low-Level Command API
    sendRequest,
    -- |'sendRequest' can be used to implement commands from experimental
    --  versions of Redis. An example of how to implement a command is given
    --  below.
    --
    -- @
    -- -- |Redis DEBUG OBJECT command
    -- debugObject :: ByteString -> 'Redis' (Either 'Reply' ByteString)
    -- debugObject key = 'sendRequest' [\"DEBUG\", \"OBJECT\", 'encode' key]
    -- @
    --
    Reply(..),Status(..),RedisResult(..)
    
) where

import Database.Redis.Core
import Database.Redis.Connection
import Database.Redis.PubSub
import Database.Redis.Reply
import Database.Redis.Types

import Database.Redis.Commands
