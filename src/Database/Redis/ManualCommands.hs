{-# LANGUAGE OverloadedStrings #-}

module Database.Redis.ManualCommands where

import Control.Applicative
import Data.ByteString
import Database.Redis.Types
import Database.Redis.Internal

objectRefcount :: (RedisReturnInt a)
    => ByteString -- ^ key
    -> Redis (Maybe a)
objectRefcount key = decodeInt <$> sendRequest ["OBJECT", "refcount", key]

objectIdletime :: (RedisReturnInt a)
    => ByteString -- ^ key
    -> Redis (Maybe a)
objectIdletime key = decodeInt <$> sendRequest ["OBJECT", "idletime", key]

objectEncoding :: (RedisReturnString a)
    => ByteString -- ^ key
    -> Redis (Maybe a)
objectEncoding key = decodeString <$> sendRequest ["OBJECT", "encoding", key]

linsertBefore :: (RedisReturnInt a)
    => ByteString -- ^ key
    -> ByteString -- ^ pivot
    -> ByteString -- ^ value
    -> Redis (Maybe a)
linsertBefore key pivot value =
    decodeInt <$> sendRequest ["LINSERT", key, "BEFORE", pivot, value]

linsertAfter :: (RedisReturnInt a)
    => ByteString -- ^ key
    -> ByteString -- ^ pivot
    -> ByteString -- ^ value
    -> Redis (Maybe a)
linsertAfter key pivot value =
        decodeInt <$> sendRequest ["LINSERT", key, "AFTER", pivot, value]

getType :: (RedisReturnStatus a)
        => ByteString -- ^ key
        -> Redis (Maybe a)
getType key = decodeStatus <$> sendRequest ["TYPE", key]
