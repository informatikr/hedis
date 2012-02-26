{-# LANGUAGE OverloadedStrings, FlexibleInstances, MultiParamTypeClasses,
    GeneralizedNewtypeDeriving #-}

module Database.Redis.Transactions (
    watch, unwatch, multiExec,
    Queued(), RedisTx(),
) where

import Control.Applicative
import Control.Monad.State
import Data.ByteString (ByteString)

import Database.Redis.Core
import Database.Redis.Reply
import Database.Redis.Types


-- |Command-context inside of MULTI\/EXEC transactions.
newtype RedisTx a = RedisTx (StateT ([Reply] -> Reply) Redis a)
    deriving (Monad, MonadIO, Functor, Applicative)

runRedisTx :: RedisTx a -> Redis a
runRedisTx (RedisTx r) = evalStateT r head

instance MonadRedis RedisTx where
    liftRedis = RedisTx . lift

instance (RedisResult a) => RedisCtx RedisTx a (Queued a) where
    returnDecode _queued = RedisTx $ do
        f <- get
        put (f . tail)
        return $ Queued (decode . f)

-- |A 'Queued' value represents the result of a command inside a transaction. It
--  is a proxy object for the /actual/ result, which will only be available
--  after returning from a 'multiExec' transaction.
data Queued a = Queued ([Reply] -> Either Reply a)

instance Functor Queued where
    fmap f (Queued g) = Queued (fmap f . g)

instance Applicative Queued where
    pure x                = Queued (const $ Right x)
    Queued f <*> Queued x = Queued $ \rs -> do
                                        f' <- f rs
                                        x' <- x rs
                                        return (f' x')

instance Monad Queued where
    return         = pure
    Queued x >>= f = Queued $ \rs -> do
                                x' <- x rs
                                let Queued f' = f x'
                                f' rs

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
