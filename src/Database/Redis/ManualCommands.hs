{-# LANGUAGE OverloadedStrings, RecordWildCards #-}

module Database.Redis.ManualCommands where

import Prelude hiding (min,max)
import Data.ByteString (ByteString)
import Database.Redis.Core
import Database.Redis.Reply
import Database.Redis.Types


objectRefcount
    :: ByteString -- ^ key
    -> Redis (Either Reply Integer)
objectRefcount key = sendRequest ["OBJECT", "refcount", encode key]

objectIdletime
    :: ByteString -- ^ key
    -> Redis (Either Reply Integer)
objectIdletime key = sendRequest ["OBJECT", "idletime", encode key]

objectEncoding
    :: ByteString -- ^ key
    -> Redis (Either Reply (Maybe ByteString))
objectEncoding key = sendRequest ["OBJECT", "encoding", encode key]

linsertBefore
    :: ByteString -- ^ key
    -> ByteString -- ^ pivot
    -> ByteString -- ^ value
    -> Redis (Either Reply Integer)
linsertBefore key pivot value =
    sendRequest ["LINSERT", encode key, "BEFORE", encode pivot, encode value]

linsertAfter
    :: ByteString -- ^ key
    -> ByteString -- ^ pivot
    -> ByteString -- ^ value
    -> Redis (Either Reply Integer)
linsertAfter key pivot value =
        sendRequest ["LINSERT", encode key, "AFTER", encode pivot, encode value]

getType
    :: ByteString -- ^ key
    -> Redis (Either Reply Status)
getType key = sendRequest ["TYPE", encode key]

slowlogGet
    :: Integer -- ^ cnt
    -> Redis (Either Reply Reply)
slowlogGet n = sendRequest ["SLOWLOG", "GET", encode n]

slowlogLen :: Redis (Either Reply Integer)
slowlogLen = sendRequest ["SLOWLOG", "LEN"]

slowlogReset :: Redis (Either Reply Status)
slowlogReset = sendRequest ["SLOWLOG", "RESET"]

zrange
    :: ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ stop
    -> Redis (Either Reply [ByteString])
zrange key start stop =
    sendRequest ["ZRANGE", encode key, encode start, encode stop]

zrangeWithscores
    :: ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ stop
    -> Redis (Either Reply [(ByteString,Double)])
zrangeWithscores key start stop =
    sendRequest ["ZRANGE", encode key, encode start, encode stop, "WITHSCORES"]

zrevrange
    :: ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ stop
    -> Redis (Either Reply [ByteString])
zrevrange key start stop =
    sendRequest ["ZREVRANGE", encode key, encode start, encode stop]

zrevrangeWithscores
    :: ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ stop
    -> Redis (Either Reply [(ByteString,Double)])
zrevrangeWithscores key start stop =
    sendRequest ["ZREVRANGE", encode key, encode start, encode stop
                ,"WITHSCORES"]

zrangebyscore
    :: ByteString -- ^ key
    -> Double -- ^ min
    -> Double -- ^ max
    -> Redis (Either Reply [ByteString])
zrangebyscore key min max =
    sendRequest ["ZRANGEBYSCORE", encode key, encode min, encode max]

zrangebyscoreWithscores
    :: ByteString -- ^ key
    -> Double -- ^ min
    -> Double -- ^ max
    -> Redis (Either Reply [(ByteString,Double)])
zrangebyscoreWithscores key min max =
    sendRequest ["ZRANGEBYSCORE", encode key, encode min, encode max
                ,"WITHSCORES"]

zrangebyscoreLimit
    :: ByteString -- ^ key
    -> Double -- ^ min
    -> Double -- ^ max
    -> Integer -- ^ offset
    -> Integer -- ^ count
    -> Redis (Either Reply [ByteString])
zrangebyscoreLimit key min max offset count =
    sendRequest ["ZRANGEBYSCORE", encode key, encode min, encode max
                ,"LIMIT", encode offset, encode count]

zrangebyscoreWithscoresLimit
    :: ByteString -- ^ key
    -> Double -- ^ min
    -> Double -- ^ max
    -> Integer -- ^ offset
    -> Integer -- ^ count
    -> Redis (Either Reply [(ByteString,Double)])
zrangebyscoreWithscoresLimit key min max offset count =
    sendRequest ["ZRANGEBYSCORE", encode key, encode min, encode max
                ,"WITHSCORES","LIMIT", encode offset, encode count]

zrevrangebyscore
    :: ByteString -- ^ key
    -> Double -- ^ max
    -> Double -- ^ min
    -> Redis (Either Reply [ByteString])
zrevrangebyscore key min max =
    sendRequest ["ZREVRANGEBYSCORE", encode key, encode min, encode max]

zrevrangebyscoreWithscores
    :: ByteString -- ^ key
    -> Double -- ^ max
    -> Double -- ^ min
    -> Redis (Either Reply [(ByteString,Double)])
zrevrangebyscoreWithscores key min max =
    sendRequest ["ZREVRANGEBYSCORE", encode key, encode min, encode max
                ,"WITHSCORES"]

zrevrangebyscoreLimit
    :: ByteString -- ^ key
    -> Double -- ^ max
    -> Double -- ^ min
    -> Integer -- ^ offset
    -> Integer -- ^ count
    -> Redis (Either Reply [ByteString])
zrevrangebyscoreLimit key min max offset count =
    sendRequest ["ZREVRANGEBYSCORE", encode key, encode min, encode max
                ,"LIMIT", encode offset, encode count]

zrevrangebyscoreWithscoresLimit
    :: ByteString -- ^ key
    -> Double -- ^ max
    -> Double -- ^ min
    -> Integer -- ^ offset
    -> Integer -- ^ count
    -> Redis (Either Reply [(ByteString,Double)])
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
    :: ByteString -- ^ key
    -> ByteString -- ^ destination
    -> SortOpts
    -> Redis (Either Reply Integer)
sortStore key dest = sortInternal key (Just dest)

sort
    :: ByteString -- ^ key
    -> SortOpts
    -> Redis (Either Reply [ByteString])
sort key = sortInternal key Nothing

sortInternal
    :: (RedisResult a)
    => ByteString -- ^ key
    -> Maybe ByteString -- ^ destination
    -> SortOpts
    -> Redis (Either Reply a)
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
    :: ByteString -- ^ destination
    -> [ByteString] -- ^ keys
    -> Aggregate
    -> Redis (Either Reply Integer)
zunionstore dest keys =
    zstoreInternal "ZUNIONSTORE" dest keys []

zunionstoreWeights
    :: ByteString -- ^ destination
    -> [(ByteString,Double)] -- ^ weighted keys
    -> Aggregate
    -> Redis (Either Reply Integer)
zunionstoreWeights dest kws =
    let (keys,weights) = unzip kws
    in zstoreInternal "ZUNIONSTORE" dest keys weights

zinterstore
    :: ByteString -- ^ destination
    -> [ByteString] -- ^ keys
    -> Aggregate
    -> Redis (Either Reply Integer)
zinterstore dest keys =
    zstoreInternal "ZINTERSTORE" dest keys []

zinterstoreWeights
    :: ByteString -- ^ destination
    -> [(ByteString,Double)] -- ^ weighted keys
    -> Aggregate
    -> Redis (Either Reply Integer)
zinterstoreWeights dest kws =
    let (keys,weights) = unzip kws
    in zstoreInternal "ZINTERSTORE" dest keys weights

zstoreInternal
    :: ByteString -- ^ cmd
    -> ByteString -- ^ destination
    -> [ByteString] -- ^ keys
    -> [Double] -- ^ weights
    -> Aggregate
    -> Redis (Either Reply Integer)
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
