{-# LANGUAGE OverloadedStrings #-}

module Database.Redis.ManualCommands where

import Database.Redis.Types
import Database.Redis.Internal

objectRefcount :: (RedisArg key, RedisResult a)
    => key
    -> Redis a
objectRefcount key = sendRequest ["OBJECT", "refcount", encode key]

objectIdletime :: (RedisArg key, RedisResult a)
    => key
    -> Redis a
objectIdletime key = sendRequest ["OBJECT", "idletime", encode key]

objectEncoding :: (RedisArg key, RedisResult a)
    => key
    -> Redis a
objectEncoding key = sendRequest ["OBJECT", "encoding", encode key]

linsertBefore :: (RedisArg key, RedisArg pivot, RedisArg value, RedisResult a)
    => key
    -> pivot
    -> value
    -> Redis a
linsertBefore key pivot value =
    sendRequest ["LINSERT", encode key, "BEFORE", encode pivot, encode value]

linsertAfter :: (RedisArg key, RedisArg pivot, RedisArg value, RedisResult a)
    => key
    -> pivot
    -> value
    -> Redis a
linsertAfter key pivot value =
        sendRequest ["LINSERT", encode key, "AFTER", encode pivot, encode value]

getType :: (RedisArg key, RedisResult a)
        => key
        -> Redis a
getType key = sendRequest ["TYPE", encode key]

slowlogGet :: (RedisArg cnt, RedisResult a)
    => cnt
    -> Redis a
slowlogGet n = sendRequest ["SLOWLOG", "GET", encode n]

slowlogLen :: (RedisResult a) => Redis a
slowlogLen = sendRequest ["SLOWLOG", "LEN"]

slowlogReset :: (RedisResult a) => Redis a
slowlogReset = sendRequest ["SLOWLOG", "RESET"]
