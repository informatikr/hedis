{-# LANGUAGE OverloadedStrings #-}

module Database.Redis.ManualCommands.Function
    ( functionDelete
    , functionDump
    , functionFlush
    , functionFlushOpts
    , functionKill
    , functionLoad
    , functionLoadReplace
    , FunctionRestorePolicy(..)
    , FunctionRestoreOpts(..)
    , defaultFunctionRestoreOpts
    , functionRestore
    , functionRestoreOpts
    , functionStats
    ) where

import Data.ByteString (ByteString)

import Database.Redis.Core
import Database.Redis.Protocol
import Database.Redis.Types
import Database.Redis.ManualCommands (FlushOpts, FunctionRestorePolicy(..))
import qualified Database.Redis.ManualCommands as Manual

data FunctionRestoreOpts
    = FunctionRestoreDefault
    | FunctionRestoreWithPolicy FunctionRestorePolicy
    deriving (Show, Eq)

defaultFunctionRestoreOpts :: FunctionRestoreOpts
defaultFunctionRestoreOpts = FunctionRestoreDefault

-- |Deletes a library and its functions (<https://redis.io/commands/function-delete>).
--
-- Deletes the library named by the argument together with all functions it contains.
--
-- $O(1)$
--
-- Since Redis 7.0.0
functionDelete
    :: (RedisCtx m f)
    => ByteString -- ^ Library name.
    -> m (f Status)
functionDelete = Manual.functionDelete

-- |Dumps all libraries into a serialized binary payload (<https://redis.io/commands/function-dump>).
--
-- Serializes all loaded libraries into a binary payload that can later be used with 'functionRestore'.
--
-- $O(N)$ where $N$ is the number of functions.
--
-- Since Redis 7.0.0
functionDump
    :: (RedisCtx m f)
    => m (f ByteString)
functionDump = Manual.functionDump

-- |Deletes all libraries and functions (<https://redis.io/commands/function-flush>).
--
-- Removes every library currently loaded into Redis.
--
-- $O(N)$ where $N$ is the number of functions deleted.
--
-- Since Redis 7.0.0
functionFlush
    :: (RedisCtx m f)
    => m (f Status)
functionFlush = Manual.functionFlush

-- |Deletes all libraries and functions (<https://redis.io/commands/function-flush>).
--
-- Removes every library currently loaded into Redis using the requested flushing mode.
--
-- $O(N)$ where $N$ is the number of functions deleted.
--
-- Since Redis 7.0.0
functionFlushOpts
    :: (RedisCtx m f)
    => FlushOpts -- ^ Flush mode.
    -> m (f Status)
functionFlushOpts = Manual.functionFlushOpts

-- |Terminates a function during execution (<https://redis.io/commands/function-kill>).
--
-- Terminates the currently running function, if it is marked as killable by Redis.
--
-- $O(1)$
--
-- Since Redis 7.0.0
functionKill
    :: (RedisCtx m f)
    => m (f Status)
functionKill = Manual.functionKill

-- |Creates a library (<https://redis.io/commands/function-load>).
--
-- Loads a new function library and returns its library name.
--
-- $O(N)$ where $N$ is the number of bytes in the function's source code.
--
-- Since Redis 7.0.0
functionLoad
    :: (RedisCtx m f)
    => ByteString -- ^ Library source code.
    -> m (f ByteString)
functionLoad = Manual.functionLoad

-- |Creates a library, replacing an existing one with the same name (<https://redis.io/commands/function-load>).
--
-- Loads a function library and replaces an existing library with the same name.
--
-- $O(N)$ where $N$ is the number of bytes in the function's source code.
--
-- Since Redis 7.0.0
functionLoadReplace
    :: (RedisCtx m f)
    => ByteString -- ^ Library source code.
    -> m (f ByteString)
functionLoadReplace = Manual.functionLoadReplace

-- |Restores all libraries from a payload (<https://redis.io/commands/function-restore>).
--
-- Restores all libraries from a payload previously returned by 'functionDump'.
--
-- $O(N)$ where $N$ is the number of functions restored.
--
-- Since Redis 7.0.0
functionRestore
    :: (RedisCtx m f)
    => ByteString -- ^ Serialized libraries payload.
    -> m (f Status)
functionRestore payload = functionRestoreOpts payload defaultFunctionRestoreOpts

-- |Restores all libraries from a payload (<https://redis.io/commands/function-restore>).
--
-- Restores all libraries from a payload previously returned by 'functionDump', optionally selecting the restore policy.
--
-- $O(N)$ where $N$ is the number of functions restored.
--
-- Since Redis 7.0.0
functionRestoreOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Serialized libraries payload.
    -> FunctionRestoreOpts -- ^ Restore options.
    -> m (f Status)
functionRestoreOpts payload opts =
    Manual.functionRestore payload restorePolicy
  where
    restorePolicy = case opts of
        FunctionRestoreDefault -> Nothing
        FunctionRestoreWithPolicy policy -> Just policy

-- |Returns information about a function during execution (<https://redis.io/commands/function-stats>).
--
-- Returns execution statistics and runtime information for the function engine.
--
-- $O(1)$
--
-- Since Redis 7.0.0
functionStats
    :: (RedisCtx m f)
    => m (f Reply)
functionStats = Manual.functionStats
