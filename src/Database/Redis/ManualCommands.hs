{-# LANGUAGE OverloadedStrings #-}

module Database.Redis.ManualCommands where

import Data.ByteString
import Database.Redis.Types
import Database.Redis.Internal

objectRefcount :: (RedisResult a)
    => ByteString -- ^ key
    -> Redis a
objectRefcount key = sendRequest ["OBJECT", "refcount", key]

objectIdletime :: (RedisResult a)
    => ByteString -- ^ key
    -> Redis a
objectIdletime key = sendRequest ["OBJECT", "idletime", key]

objectEncoding :: (RedisResult a)
    => ByteString -- ^ key
    -> Redis a
objectEncoding key = sendRequest ["OBJECT", "encoding", key]

linsertBefore :: (RedisResult a)
    => ByteString -- ^ key
    -> ByteString -- ^ pivot
    -> ByteString -- ^ value
    -> Redis a
linsertBefore key pivot value =
    sendRequest ["LINSERT", key, "BEFORE", pivot, value]

linsertAfter :: (RedisResult a)
    => ByteString -- ^ key
    -> ByteString -- ^ pivot
    -> ByteString -- ^ value
    -> Redis a
linsertAfter key pivot value =
        sendRequest ["LINSERT", key, "AFTER", pivot, value]

getType :: (RedisResult a)
        => ByteString -- ^ key
        -> Redis a
getType key = sendRequest ["TYPE", key]
