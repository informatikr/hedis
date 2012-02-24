{-# LANGUAGE OverloadedStrings #-}

module Database.Redis.Transactions (
    watch, unwatch, multiExec,
) where

import Control.Applicative
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


multiExec :: RedisTx (Queued a) -> Redis (Either Reply a)
multiExec rtx = do
    _        <- multi
    Queued f <- runRedisTx rtx
    r        <- exec
    case r of
        MultiBulk rs -> return $ maybe (Left r) f rs
        _            -> error $ "hedis: EXEC returned " ++ show r

multi :: Redis (Either Reply Status)
multi = sendRequest ["MULTI"]

exec :: Redis Reply
exec = either id id <$> sendRequest ["EXEC"]
