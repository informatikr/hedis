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


-- |Run commands inside a transaction. For documentation on the semantics of
--  Redis transaction see <http://redis.io/topics/transactions>.
--
--  Inside the transaction block, command functions return their result wrapped
--  in a 'Queued'. The 'Queued' result is a proxy object for the actual
--  command's result, which will only be available after @EXEC@ing the
--  transaction.
--
--  Example usage (note how 'Queued' \'s 'Applicative' instance is used to
--  combine the two individual results):
--
--  @
--  runRedis conn $ do
--      set \"hello\" \"hello\"
--      set \"world\" \"world\"
--      helloworld <- 'multiExec' $ do
--          hello <- get \"hello\"
--          world <- get \"world\"
--          return $ (,) \<$\> hello \<*\> world
--      liftIO (print helloworld)
--  @
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
