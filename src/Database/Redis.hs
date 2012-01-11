{-# LANGUAGE OverloadedStrings, CPP #-}

module Database.Redis (
    
    -- * The Redis Monad
    Redis(), runRedis,
    
    -- * Connection
    RedisConn, connect, disconnect,
    HostName,PortID(..),defaultPort,
    
    -- * Commands
	module Database.Redis.Commands,

    -- * Pub\/Sub
    module Database.Redis.PubSub,

    -- * Low-Level Requests and Replies
    sendRequest,
    -- |'sendRequest' can be used to implement one of the unimplemented 
    --  commands, as shown below.
    --
    -- @
    -- -- |Redis DEBUG OBJECT command
    -- debugObject :: ByteString -> 'Redis' (Either 'Reply' ByteString)
    -- debugObject key = 'sendRequest' [\"DEBUG\", \"OBJECT\", 'encode' key]
    -- @
    --
    Reply(..),Status(..),RedisResult(..)
    
) where

import Database.Redis.Internal
import Database.Redis.PubSub
import Database.Redis.Reply
import Database.Redis.Types

import Database.Redis.Commands
