{-# LANGUAGE OverloadedStrings #-}

module Database.Redis.ManualCommands where

import Prelude () -- Avoid name-shadowing warning.
import Database.Redis.Types
import Database.Redis.Internal

objectRefcount :: (RedisArg key, RedisResult a)
    => key -- ^
    -> Redis a
objectRefcount key = sendRequest ["OBJECT", "refcount", encode key]

objectIdletime :: (RedisArg key, RedisResult a)
    => key -- ^
    -> Redis a
objectIdletime key = sendRequest ["OBJECT", "idletime", encode key]

objectEncoding :: (RedisArg key, RedisResult a)
    => key -- ^
    -> Redis a
objectEncoding key = sendRequest ["OBJECT", "encoding", encode key]

linsertBefore :: (RedisArg key, RedisArg pivot, RedisArg value, RedisResult a)
    => key -- ^
    -> pivot -- ^
    -> value -- ^
    -> Redis a
linsertBefore key pivot value =
    sendRequest ["LINSERT", encode key, "BEFORE", encode pivot, encode value]

linsertAfter :: (RedisArg key, RedisArg pivot, RedisArg value, RedisResult a)
    => key -- ^
    -> pivot -- ^
    -> value -- ^
    -> Redis a
linsertAfter key pivot value =
        sendRequest ["LINSERT", encode key, "AFTER", encode pivot, encode value]

getType :: (RedisArg key, RedisResult a)
        => key -- ^
        -> Redis a
getType key = sendRequest ["TYPE", encode key]

slowlogGet :: (RedisArg cnt, RedisResult a)
    => cnt -- ^
    -> Redis a
slowlogGet n = sendRequest ["SLOWLOG", "GET", encode n]

slowlogLen :: (RedisResult a) => Redis a
slowlogLen = sendRequest ["SLOWLOG", "LEN"]

slowlogReset :: (RedisResult a) => Redis a
slowlogReset = sendRequest ["SLOWLOG", "RESET"]

zrange :: (RedisArg key, RedisArg start, RedisArg stop, RedisResult a)
    => key -- ^
    -> start -- ^
    -> stop -- ^
    -> Redis a
zrange key start stop =
    sendRequest ["ZRANGE", encode key, encode start, encode stop]

zrangeWithscores :: (RedisArg key, RedisArg start, RedisArg stop, RedisResult a)
    => key -- ^
    -> start -- ^
    -> stop -- ^
    -> Redis a
zrangeWithscores key start stop =
    sendRequest ["ZRANGE", encode key, encode start, encode stop, "WITHSCORES"]

zrevrange :: (RedisArg key, RedisArg start, RedisArg stop, RedisResult a)
    => key -- ^
    -> start -- ^
    -> stop -- ^
    -> Redis a
zrevrange key start stop =
    sendRequest ["ZRANGE", encode key, encode start, encode stop]

zrevrangeWithscores
    :: (RedisArg key, RedisArg start, RedisArg stop, RedisResult a)
    => key -- ^
    -> start -- ^
    -> stop -- ^
    -> Redis a
zrevrangeWithscores key start stop =
    sendRequest ["ZRANGE", encode key, encode start, encode stop, "WITHSCORES"]

zrangebyscore :: (RedisArg key, RedisArg min, RedisArg max, RedisResult a)
    => key -- ^
    -> min -- ^
    -> max -- ^
    -> Redis a
zrangebyscore key min max =
    sendRequest ["ZRANGEBYSCORE", encode key, encode min, encode max]

zrangebyscoreWithscores
    :: (RedisArg key, RedisArg min, RedisArg max, RedisResult a)
    => key -- ^
    -> min -- ^
    -> max -- ^
    -> Redis a
zrangebyscoreWithscores key min max =
    sendRequest ["ZRANGEBYSCORE", encode key, encode min, encode max
                ,"WITHSCORES"]

zrangebyscoreLimit
    :: (RedisArg key, RedisArg min, RedisArg max,
        RedisArg offset, RedisArg count, RedisResult a)
    => key -- ^
    -> min -- ^
    -> max -- ^
    -> offset -- ^
    -> count -- ^
    -> Redis a
zrangebyscoreLimit key min max offset count =
    sendRequest ["ZRANGEBYSCORE", encode key, encode min, encode max
                ,"LIMIT", encode offset, encode count]

zrangebyscoreWithscoresLimit
    :: (RedisArg key, RedisArg min, RedisArg max,
        RedisArg offset, RedisArg count, RedisResult a)
    => key -- ^
    -> min -- ^
    -> max -- ^
    -> offset -- ^
    -> count -- ^
    -> Redis a
zrangebyscoreWithscoresLimit key min max offset count =
    sendRequest ["ZRANGEBYSCORE", encode key, encode min, encode max
                ,"WITHSCORES","LIMIT", encode offset, encode count]

zrevrangebyscore :: (RedisArg key, RedisArg min, RedisArg max, RedisResult a)
    => key -- ^
    -> min -- ^
    -> max -- ^
    -> Redis a
zrevrangebyscore key min max =
    sendRequest ["ZREVRANGEBYSCORE", encode key, encode min, encode max]

zrevrangebyscoreWithscores
    :: (RedisArg key, RedisArg min, RedisArg max, RedisResult a)
    => key -- ^
    -> min -- ^
    -> max -- ^
    -> Redis a
zrevrangebyscoreWithscores key min max =
    sendRequest ["ZREVRANGEBYSCORE", encode key, encode min, encode max
                ,"WITHSCORES"]

zrevrangebyscoreLimit
    :: (RedisArg key, RedisArg min, RedisArg max,
        RedisArg offset, RedisArg count, RedisResult a)
    => key -- ^
    -> min -- ^
    -> max -- ^
    -> offset -- ^
    -> count -- ^
    -> Redis a
zrevrangebyscoreLimit key min max offset count =
    sendRequest ["ZREVRANGEBYSCORE", encode key, encode min, encode max
                ,"LIMIT", encode offset, encode count]

zrevrangebyscoreWithscoresLimit
    :: (RedisArg key, RedisArg min, RedisArg max,
        RedisArg offset, RedisArg count, RedisResult a)
    => key -- ^
    -> min -- ^
    -> max -- ^
    -> offset -- ^
    -> count -- ^
    -> Redis a
zrevrangebyscoreWithscoresLimit key min max offset count =
    sendRequest ["ZREVRANGEBYSCORE", encode key, encode min, encode max
                ,"WITHSCORES","LIMIT", encode offset, encode count]
