{-# LANGUAGE OverloadedStrings #-}

module Database.Redis.ManualCommands where

import Control.Applicative
import Data.ByteString
import Database.Redis.Types
import Database.Redis.Internal

objectRefcount :: (RedisInt a)
    => ByteString -- ^ key
    -> Redis (Maybe a)
objectRefcount key = decodeInt <$> sendRequest ["OBJECT", "refcount", key]

objectIdletime :: (RedisInt a)
    => ByteString -- ^ key
    -> Redis (Maybe a)
objectIdletime key = decodeInt <$> sendRequest ["OBJECT", "idletime", key]

objectEncoding :: (RedisString a)
    => ByteString -- ^ key
    -> Redis (Maybe a)
objectEncoding key = decodeString <$> sendRequest ["OBJECT", "encoding", key]

linsertBefore :: (RedisInt a)
    => ByteString -- ^ key
    -> ByteString -- ^ pivot
    -> ByteString -- ^ value
    -> Redis (Maybe a)
linsertBefore key pivot value =
    decodeInt <$> sendRequest ["INSERT", key, "BEFORE", pivot, value]

linsertAfter :: (RedisInt a)
    => ByteString -- ^ key
    -> ByteString -- ^ pivot
    -> ByteString -- ^ value
    -> Redis (Maybe a)
linsertAfter key pivot value =
        decodeInt <$> sendRequest ["INSERT", key, "AFTER", pivot, value]

getType :: (RedisStatus a)
        => ByteString -- ^ key
        -> Redis (Maybe a)
getType key = decodeStatus <$> sendRequest ["TYPE", key]
