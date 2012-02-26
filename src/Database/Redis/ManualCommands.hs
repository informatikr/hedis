{-# LANGUAGE OverloadedStrings, RecordWildCards, FlexibleContexts #-}

module Database.Redis.ManualCommands where

import Prelude hiding (min,max)
import Data.ByteString (ByteString)
import Database.Redis.Core
import Database.Redis.Reply
import Database.Redis.Types


objectRefcount
    :: (RedisCtx m Integer a)
    => ByteString -- ^ key
    -> m a
objectRefcount key = sendRequest ["OBJECT", "refcount", encode key]

objectIdletime
    :: (RedisCtx m Integer a)
    => ByteString -- ^ key
    -> m a
objectIdletime key = sendRequest ["OBJECT", "idletime", encode key]

objectEncoding
    :: (RedisCtx m ByteString a)
    => ByteString -- ^ key
    -> m a
objectEncoding key = sendRequest ["OBJECT", "encoding", encode key]

linsertBefore
    :: (RedisCtx m Integer a)
    => ByteString -- ^ key
    -> ByteString -- ^ pivot
    -> ByteString -- ^ value
    -> m a
linsertBefore key pivot value =
    sendRequest ["LINSERT", encode key, "BEFORE", encode pivot, encode value]

linsertAfter
    :: (RedisCtx m Integer a)
    => ByteString -- ^ key
    -> ByteString -- ^ pivot
    -> ByteString -- ^ value
    -> m a
linsertAfter key pivot value =
        sendRequest ["LINSERT", encode key, "AFTER", encode pivot, encode value]

getType
    :: (RedisCtx m Status a)
    => ByteString -- ^ key
    -> m a
getType key = sendRequest ["TYPE", encode key]

slowlogGet
    :: (RedisCtx m Reply a)
    => Integer -- ^ cnt
    -> m a
slowlogGet n = sendRequest ["SLOWLOG", "GET", encode n]

slowlogLen :: (RedisCtx m Integer a) => m a
slowlogLen = sendRequest ["SLOWLOG", "LEN"]

slowlogReset :: (RedisCtx m Status a) => m a
slowlogReset = sendRequest ["SLOWLOG", "RESET"]

zrange
    :: (RedisCtx m [ByteString] a)
    => ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ stop
    -> m a
zrange key start stop =
    sendRequest ["ZRANGE", encode key, encode start, encode stop]

zrangeWithscores
    :: (RedisCtx m [(ByteString,Double)] a)
    => ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ stop
    -> m a
zrangeWithscores key start stop =
    sendRequest ["ZRANGE", encode key, encode start, encode stop, "WITHSCORES"]

zrevrange
    :: (RedisCtx m [ByteString] a)
    => ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ stop
    -> m a
zrevrange key start stop =
    sendRequest ["ZREVRANGE", encode key, encode start, encode stop]

zrevrangeWithscores
    :: (RedisCtx m [(ByteString,Double)] a)
    => ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ stop
    -> m a
zrevrangeWithscores key start stop =
    sendRequest ["ZREVRANGE", encode key, encode start, encode stop
                ,"WITHSCORES"]

zrangebyscore
    :: (RedisCtx m [ByteString] a)
    => ByteString -- ^ key
    -> Double -- ^ min
    -> Double -- ^ max
    -> m a
zrangebyscore key min max =
    sendRequest ["ZRANGEBYSCORE", encode key, encode min, encode max]

zrangebyscoreWithscores
    :: (RedisCtx m [(ByteString,Double)] a)
    => ByteString -- ^ key
    -> Double -- ^ min
    -> Double -- ^ max
    -> m a
zrangebyscoreWithscores key min max =
    sendRequest ["ZRANGEBYSCORE", encode key, encode min, encode max
                ,"WITHSCORES"]

zrangebyscoreLimit
    :: (RedisCtx m [ByteString] a)
    => ByteString -- ^ key
    -> Double -- ^ min
    -> Double -- ^ max
    -> Integer -- ^ offset
    -> Integer -- ^ count
    -> m a
zrangebyscoreLimit key min max offset count =
    sendRequest ["ZRANGEBYSCORE", encode key, encode min, encode max
                ,"LIMIT", encode offset, encode count]

zrangebyscoreWithscoresLimit
    :: (RedisCtx m [(ByteString,Double)] a)
    => ByteString -- ^ key
    -> Double -- ^ min
    -> Double -- ^ max
    -> Integer -- ^ offset
    -> Integer -- ^ count
    -> m a
zrangebyscoreWithscoresLimit key min max offset count =
    sendRequest ["ZRANGEBYSCORE", encode key, encode min, encode max
                ,"WITHSCORES","LIMIT", encode offset, encode count]

zrevrangebyscore
    :: (RedisCtx m [ByteString] a)
    => ByteString -- ^ key
    -> Double -- ^ max
    -> Double -- ^ min
    -> m a
zrevrangebyscore key min max =
    sendRequest ["ZREVRANGEBYSCORE", encode key, encode min, encode max]

zrevrangebyscoreWithscores
    :: (RedisCtx m [(ByteString,Double)] a)
    => ByteString -- ^ key
    -> Double -- ^ max
    -> Double -- ^ min
    -> m a
zrevrangebyscoreWithscores key min max =
    sendRequest ["ZREVRANGEBYSCORE", encode key, encode min, encode max
                ,"WITHSCORES"]

zrevrangebyscoreLimit
    :: (RedisCtx m [ByteString] a)
    => ByteString -- ^ key
    -> Double -- ^ max
    -> Double -- ^ min
    -> Integer -- ^ offset
    -> Integer -- ^ count
    -> m a
zrevrangebyscoreLimit key min max offset count =
    sendRequest ["ZREVRANGEBYSCORE", encode key, encode min, encode max
                ,"LIMIT", encode offset, encode count]

zrevrangebyscoreWithscoresLimit
    :: (RedisCtx m [(ByteString,Double)] a)
    => ByteString -- ^ key
    -> Double -- ^ max
    -> Double -- ^ min
    -> Integer -- ^ offset
    -> Integer -- ^ count
    -> m a
zrevrangebyscoreWithscoresLimit key min max offset count =
    sendRequest ["ZREVRANGEBYSCORE", encode key, encode min, encode max
                ,"WITHSCORES","LIMIT", encode offset, encode count]

-- |Options for the 'sort' command.
data SortOpts = SortOpts
    { sortBy     :: Maybe ByteString
    , sortLimit  :: (Integer,Integer)
    , sortGet    :: [ByteString]
    , sortOrder  :: SortOrder
    , sortAlpha  :: Bool
    } deriving (Show, Eq)

-- |Redis default 'SortOpts'. Equivalent to omitting all optional parameters.
--
-- @
-- SortOpts
--     { sortBy    = Nothing -- omit the BY option
--     , sortLimit = (0,-1)  -- return entire collection
--     , sortGet   = []      -- omit the GET option
--     , sortOrder = Asc     -- sort in ascending order
--     , sortAlpha = False   -- sort numerically, not lexicographically
--     }
-- @
--
defaultSortOpts :: SortOpts
defaultSortOpts = SortOpts
    { sortBy    = Nothing
    , sortLimit = (0,-1)
    , sortGet   = []
    , sortOrder = Asc
    , sortAlpha = False
    }

data SortOrder = Asc | Desc deriving (Show, Eq)

sortStore
    :: (RedisCtx m Integer a)
    => ByteString -- ^ key
    -> ByteString -- ^ destination
    -> SortOpts
    -> m a
sortStore key dest = sortInternal key (Just dest)

sort
    :: (RedisCtx m [ByteString] a)
    => ByteString -- ^ key
    -> SortOpts
    -> m a
sort key = sortInternal key Nothing

sortInternal
    :: (RedisResult result, RedisCtx m result a)
    => ByteString -- ^ key
    -> Maybe ByteString -- ^ destination
    -> SortOpts
    -> m a
sortInternal key destination SortOpts{..} = sendRequest $
    concat [["SORT", encode key], by, limit, get, order, alpha, store]
  where
    by    = maybe [] (\pattern -> ["BY", pattern]) sortBy
    limit = let (off,cnt) = sortLimit in ["LIMIT", encode off, encode cnt]
    get   = concatMap (\pattern -> ["GET", pattern]) sortGet
    order = case sortOrder of Desc -> ["DESC"]; Asc -> ["ASC"]
    alpha = ["ALPHA" | sortAlpha]
    store = maybe [] (\dest -> ["STORE", dest]) destination


data Aggregate = Sum | Min | Max deriving (Show,Eq)

zunionstore
    :: (RedisCtx m Integer a)
    => ByteString -- ^ destination
    -> [ByteString] -- ^ keys
    -> Aggregate
    -> m a
zunionstore dest keys =
    zstoreInternal "ZUNIONSTORE" dest keys []

zunionstoreWeights
    :: (RedisCtx m Integer a)
    => ByteString -- ^ destination
    -> [(ByteString,Double)] -- ^ weighted keys
    -> Aggregate
    -> m a
zunionstoreWeights dest kws =
    let (keys,weights) = unzip kws
    in zstoreInternal "ZUNIONSTORE" dest keys weights

zinterstore
    :: (RedisCtx m Integer a)
    => ByteString -- ^ destination
    -> [ByteString] -- ^ keys
    -> Aggregate
    -> m a
zinterstore dest keys =
    zstoreInternal "ZINTERSTORE" dest keys []

zinterstoreWeights
    :: (RedisCtx m Integer a)
    => ByteString -- ^ destination
    -> [(ByteString,Double)] -- ^ weighted keys
    -> Aggregate
    -> m a
zinterstoreWeights dest kws =
    let (keys,weights) = unzip kws
    in zstoreInternal "ZINTERSTORE" dest keys weights

zstoreInternal
    :: (RedisCtx m Integer a)
    => ByteString -- ^ cmd
    -> ByteString -- ^ destination
    -> [ByteString] -- ^ keys
    -> [Double] -- ^ weights
    -> Aggregate
    -> m a
zstoreInternal cmd dest keys weights aggregate = sendRequest $
    concat [ [cmd, dest, encode . toInteger $ length keys], keys
           , if null weights then [] else "WEIGHTS" : map encode weights
           , ["AGGREGATE", aggregate']
           ]
  where
    aggregate' = case aggregate of
        Sum -> "SUM"
        Min -> "MIN"
        Max -> "MAX"
