{-# LANGUAGE OverloadedStrings #-}

module Database.Redis (
    -- * How To Use This Module
    -- |
    -- Connect to a Redis server:
    --
    -- @
    -- -- connects to localhost:6379
    -- conn <- 'connect' 'defaultConnectInfo'
    -- @
    --
    -- Send commands to the server:
    -- 
    -- @
    -- 'runRedis' conn $ do
    --      'set' \"hello\" \"hello\"
    --      set \"world\" \"world\"
    --      hello <- 'get' \"hello\"
    --      world <- get \"world\"
    --      liftIO $ print (hello,world)
    -- @

    -- ** Automatic Pipelining
    -- |Commands are automatically pipelined as much as possible. For example,
    --  in the above \"hello world\" example, all four commands are pipelined.
    --  Automatic pipelining makes use of Haskell's laziness. As long as a
    --  previous reply is not evaluated, subsequent commands can be pipelined.
    --
    
    -- ** Error Behavior
    -- |
    --  [Operations against keys holding the wrong kind of value:] If the Redis
    --    server returns an 'Error', command functions will return 'Left' the
    --    'Reply'. The library user can inspect the error message to gain 
    --    information on what kind of error occured.
    --
    --  [Connection to the server lost:] In case of a lost connection, command
    --    functions throw a 
    --    'ConnectionLostException'. It can only be caught outside of
    --    'runRedis', to make sure the connection pool can properly destroy the
    --    connection.
    
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
    Reply(..),Status(..),RedisResult(..),ConnectionLostException(..),
    
) where

import Database.Redis.Core
import Database.Redis.PubSub
import Database.Redis.Reply
import Database.Redis.Types

import Database.Redis.Commands
