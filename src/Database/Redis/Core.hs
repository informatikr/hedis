{-# LANGUAGE OverloadedStrings, GeneralizedNewtypeDeriving, RecordWildCards,
    MultiParamTypeClasses, FunctionalDependencies, FlexibleInstances, CPP,
    DeriveDataTypeable, StandaloneDeriving, UndecidableInstances #-}

module Database.Redis.Core (
    Redis(), unRedis, reRedis,
    RedisCtx(..), MonadRedis(..),
    Hooks(..), SendRequestHook, SendPubSubHook, CallbackHook, SendHook, ReceiveHook, 
    send, recv, sendRequest,
    runRedisInternal,
    runRedisClusteredInternal,
    defaultHooks,
    RedisEnv(..),
) where

import Prelude
#if __GLASGOW_HASKELL__ < 710
import Control.Applicative
#endif
import Control.Monad.Reader
import qualified Data.ByteString as B
import Data.IORef
import Database.Redis.Core.Internal
import Database.Redis.Protocol
import qualified Database.Redis.ProtocolPipelining as PP
import Database.Redis.Types
import Database.Redis.Cluster(ShardMap)
import qualified Database.Redis.Cluster as Cluster
import Database.Redis.Hooks

--------------------------------------------------------------------------------
-- The Redis Monad
--

-- |This class captures the following behaviour: In a context @m@, a command
--  will return its result wrapped in a \"container\" of type @f@.
--
--  Please refer to the Command Type Signatures section of this page for more
--  information.
class (MonadRedis m) => RedisCtx m f | m -> f where
    returnDecode :: RedisResult a => Reply -> m (f a)

class (Monad m) => MonadRedis m where
    liftRedis :: Redis a -> m a

instance {-# OVERLAPPABLE #-}
  ( MonadTrans t
  , MonadRedis m
  , Monad (t m)
  ) => MonadRedis (t m) where
  liftRedis = lift . liftRedis

instance RedisCtx Redis (Either Reply) where
    returnDecode = return . decode

instance MonadRedis Redis where
    liftRedis = id

-- |Deconstruct Redis constructor.
--
--  'unRedis' and 'reRedis' can be used to define instances for
--  arbitrary typeclasses.
--
--  WARNING! These functions are considered internal and no guarantee
--  is given at this point that they will not break in future.
unRedis :: Redis a -> ReaderT RedisEnv IO a
unRedis (Redis r) = r

-- |Reconstruct Redis constructor.
reRedis :: ReaderT RedisEnv IO a -> Redis a
reRedis r = Redis r

-- |Internal version of 'runRedis' that does not depend on the 'Connection'
--  abstraction. Used to run the AUTH command when connecting.
runRedisInternal :: PP.Connection -> Redis a -> IO a
runRedisInternal conn (Redis redis) = do
  -- Dummy reply in case no request is sent.
  ref <- newIORef (SingleLine "nobody will ever see this")
  r <- runReaderT redis (NonClusteredEnv conn ref)
  -- Evaluate last reply to keep lazy IO inside runRedis.
  readIORef ref >>= (`seq` return ())
  return r

runRedisClusteredInternal :: Cluster.Connection -> IO ShardMap -> Redis a -> IO a
runRedisClusteredInternal connection refreshShardmapAction (Redis redis) = do
    r <- runReaderT redis (ClusteredEnv refreshShardmapAction connection)
    r `seq` return ()
    return r

setLastReply :: Reply -> ReaderT RedisEnv IO ()
setLastReply r = do
  ref <- asks envLastReply
  lift (writeIORef ref r)

recv :: (MonadRedis m) => m Reply
recv = liftRedis $ Redis $ do
  conn <- asks envConn
  r <- liftIO (PP.recv conn)
  setLastReply r
  return r

send :: (MonadRedis m) => [B.ByteString] -> m ()
send req = liftRedis $ Redis $ do
    conn <- asks envConn
    liftIO $ PP.send conn (renderRequest req)

-- |'sendRequest' can be used to implement commands from experimental
--  versions of Redis. An example of how to implement a command is given
--  below.
--
-- @
-- -- |Redis DEBUG OBJECT command
-- debugObject :: ByteString -> 'Redis' (Either 'Reply' ByteString)
-- debugObject key = 'sendRequest' [\"DEBUG\", \"OBJECT\", key]
-- @
--
sendRequest :: (RedisCtx m f, RedisResult a)
    => [B.ByteString] -> m (f a)
sendRequest req = do
    r' <- liftRedis $ Redis $ do
        env <- ask
        case env of
            NonClusteredEnv{..} -> do
                r <- liftIO $ sendRequestHook (PP.hooks envConn) (PP.request envConn . renderRequest) req
                setLastReply r
                return r
            ClusteredEnv{..} -> liftIO $ sendRequestHook (Cluster.hooks connection) (Cluster.requestPipelined refreshAction connection) req
    returnDecode r'
