{-# LANGUAGE OverloadedStrings, CPP #-}

module Database.Redis (
    
    -- * The Redis Monad
    Redis(), runRedis,
    
    -- * Connection
    RedisConn, connect, disconnect,
    HostName,PortID(..),
    
    -- * Low-Level Requests and Replies
    Reply(..),
    sendRequest,
    -- |'sendRequest' can be used to implement one of the unimplemented 
    --  commands.
    --
    -- @
    --   sendRequest [\"DEBUG\", \"SEGFAULT\"] -- crashes the server
    -- @
    --
    
    -- * PubSub
    module Database.Redis.PubSub,
    module Database.Redis.Types,
    -- * Commands
	module Database.Redis.Commands
	
	
	-- * Unimplemented Commands
	-- #unimplementedCommands#
	-- $unimplementedCommands
) where

import Database.Redis.Internal
import Database.Redis.PubSub
import Database.Redis.Reply
import Database.Redis.Types

import Database.Redis.Commands

-- $unimplementedCommands
-- List of unimplemented commands