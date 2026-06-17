{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Database.Redis.ManualCommands.Wait
  ( WaitAofResult(..)
  , wait
  , waitaof
  ) where

import Database.Redis.Core
import Database.Redis.Types

data WaitAofResult = WaitAofResult
    { waitAofLocal :: Integer
      -- ^ Number of local Redis instances (0 or 1) that fsynced all preceding writes to AOF.
    , waitAofReplicas :: Integer
      -- ^ Number of replicas that fsynced all preceding writes to AOF.
    } deriving (Show, Eq)

instance RedisResult WaitAofResult where
    decode response = do
        (waitAofLocal, waitAofReplicas) <- decode response
        pure WaitAofResult{..}

-- |
-- /O(1)/ Wait for preceding writes to be acknowledged by a given number of replicas (<https://redis.io/commands/wait>).
--
-- Blocks until the asynchronous replication of all preceding write commands sent by the connection is completed.
--
-- Since Redis 3.0.0
wait
    :: (RedisCtx m f)
    => Integer -- ^ Number of replicas to wait for.
    -> Integer -- ^ Maximum time to wait in milliseconds. @0@ means wait forever.
    -> m (f Integer)
wait numReplicas timeout =
    sendRequest ["WAIT", encode numReplicas, encode timeout]

-- |
-- /O(1)/ Wait for preceding writes to be fsynced to the append-only file locally and\/or on replicas (<https://redis.io/commands/waitaof>).
--
-- Blocks until all of the preceding write commands sent by the connection are written to the append-only file of the master and\/or replicas.
--
-- Since Redis 7.2.0
waitaof
    :: (RedisCtx m f)
    => Integer -- ^ Number of local Redis instances to wait for AOF fsync on (@0@ or @1@).
    -> Integer -- ^ Number of replicas to wait for AOF fsync on.
    -> Integer -- ^ Maximum time to wait in milliseconds. @0@ means wait forever.
    -> m (f WaitAofResult)
waitaof numLocal numReplicas timeout =
    sendRequest ["WAITAOF", encode numLocal, encode numReplicas, encode timeout]
