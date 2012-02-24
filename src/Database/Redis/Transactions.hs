{-# LANGUAGE OverloadedStrings #-}

module Database.Redis.Transactions (
    watch, unwatch, multiExec,
) where

import Data.ByteString

import Database.Redis.Core
import Database.Redis.Reply
import Database.Redis.Types

-- |Watch the given keys to determine execution of the MULTI\/EXEC block
--  (<http://redis.io/commands/watch>).
watch
    :: [ByteString] -- ^ key
    -> Redis (Either Reply Status)
watch key = sendRequest ("WATCH" : key)

-- |Forget about all watched keys (<http://redis.io/commands/unwatch>).
unwatch :: Redis (Either Reply Status)
unwatch  = sendRequest ["UNWATCH"]


multiExec :: RedisTx (Queued a) -> Redis (Either Reply Reply)
multiExec (RedisTx tx) = do
    _ <- multi
    _ <- tx
    exec

multi :: Redis (Either Reply Status)
multi = sendRequest ["MULTI"]

exec :: Redis (Either Reply Reply)
exec = sendRequest ["EXEC"]
