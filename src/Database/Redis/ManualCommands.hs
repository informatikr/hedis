{-# LANGUAGE CPP, OverloadedStrings, RecordWildCards, FlexibleContexts #-}

module Database.Redis.ManualCommands where

import Prelude hiding (min, max)
import Data.ByteString (ByteString, empty, append)
import qualified Data.ByteString.Char8 as Char8
import qualified Data.ByteString as BS
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE
import Data.Maybe (maybeToList, catMaybes, fromMaybe)
#if __GLASGOW_HASKELL__ < 808
import Data.Semigroup ((<>))
#endif



import Database.Redis.Core
import Database.Redis.Protocol
import Database.Redis.Types
import qualified Database.Redis.Cluster.Command as CMD

-- |Inspect the internals of Redis objects (<http://redis.io/commands/object>). The Redis command @OBJECT@ is split up into 'objectRefcount', 'objectEncoding', 'objectIdletime'. Since Redis 2.2.3
objectRefcount
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f Integer)
objectRefcount key = sendRequest ["OBJECT", "refcount", key]

objectIdletime
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f Integer)
objectIdletime key = sendRequest ["OBJECT", "idletime", key]

-- |Inspect the internals of Redis objects (<http://redis.io/commands/object>). The Redis command @OBJECT@ is split up into 'objectRefcount', 'objectEncoding', 'objectIdletime'. Since Redis 2.2.3
objectEncoding
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f ByteString)
objectEncoding key = sendRequest ["OBJECT", "encoding", key]

-- |Insert an element before or after another element in a list (<http://redis.io/commands/linsert>). The Redis command @LINSERT@ is split up into 'linsertBefore', 'linsertAfter'. Since Redis 2.2.0
linsertBefore
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ pivot
    -> ByteString -- ^ value
    -> m (f Integer)
linsertBefore key pivot value =
    sendRequest ["LINSERT", key, "BEFORE", pivot, value]

-- |Insert an element before or after another element in a list (<http://redis.io/commands/linsert>). The Redis command @LINSERT@ is split up into 'linsertBefore', 'linsertAfter'. Since Redis 2.2.0
linsertAfter
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ pivot
    -> ByteString -- ^ value
    -> m (f Integer)
linsertAfter key pivot value =
        sendRequest ["LINSERT", encode key, "AFTER", encode pivot, encode value]

data ListDirection = ListLeft | ListRight deriving (Show, Eq)

instance RedisArg ListDirection where
    encode ListLeft = "LEFT"
    encode ListRight = "RIGHT"

data LPosOpts = LPosOpts
    { lposRank :: Maybe Integer
    , lposMaxlen :: Maybe Integer
    } deriving (Show, Eq)

defaultLPosOpts :: LPosOpts
defaultLPosOpts = LPosOpts
    { lposRank = Nothing -- ^ The RANK option specifies the "rank" of the first element to return, in case there are multiple matches. A rank of 1 means to return the first match, 2 to return the second match, and so forth.
    , lposMaxlen = Nothing -- ^ The MAXLEN option limits the number of elements to examine, which can improve performance for large lists.
    }

-- |Returns the index of the first matching element in a list (<https://redis.io/commands/lpos>).
--
-- $O(N)$ where $N$ is the number of elements in the list, for the average case. When searching for elements near the head or the tail of the list, or when the MAXLEN option is provided, the command may run in constant time.
--
-- Since Redis 6.0.6
lpos
    :: (RedisCtx m f)
    => ByteString
    -> ByteString
    -> m (f (Maybe Integer))
lpos key element = lposOpts key element defaultLPosOpts

-- |Returns the index of the first matching element in a list (<https://redis.io/commands/lpos>).
--
-- $O(N)$ where $N$ is the number of elements in the list, for the average case. When searching for elements near the head or the tail of the list, or when the MAXLEN option is provided, the command may run in constant time.
--
-- Since Redis 6.0.6
lposOpts
    :: (RedisCtx m f)
    => ByteString
    -> ByteString
    -> LPosOpts
    -> m (f (Maybe Integer))
lposOpts key element opts =
    sendRequest $ ["LPOS", key, element] ++ lposOptsToArgs opts

-- |Returns the indexes of matching elements in a list (<https://redis.io/commands/lpos>).
--
-- $O(N)$ where $N$ is the number of elements in the list, for the average case. When searching for elements near the head or the tail of the list, or when the MAXLEN option is provided, the command may run in constant time.
--
-- Since Redis 6.0.6
lposCount
    :: (RedisCtx m f)
    => ByteString
    -> ByteString
    -> Integer
    -> m (f [Integer])
lposCount key element count = lposCountOpts key element count defaultLPosOpts

-- |Returns the indexes of matching elements in a list (<https://redis.io/commands/lpos>).
--
-- $O(N)$ where $N$ is the number of elements in the list, for the average case. When searching for elements near the head or the tail of the list, or when the MAXLEN option is provided, the command may run in constant time.
--
-- Since Redis 6.0.6
lposCountOpts
    :: (RedisCtx m f)
    => ByteString
    -> ByteString
    -> Integer
    -> LPosOpts
    -> m (f [Integer])
lposCountOpts key element count opts =
    sendRequest $ ["LPOS", key, element] ++ rankArg ++ ["COUNT", encode count] ++ maxlenArg
  where
    (rankArg, maxlenArg) = lposOptsParts opts

lposOptsToArgs :: LPosOpts -> [ByteString]
lposOptsToArgs opts =
    rankArg ++ maxlenArg
  where
    (rankArg, maxlenArg) = lposOptsParts opts

lposOptsParts :: LPosOpts -> ([ByteString], [ByteString])
lposOptsParts LPosOpts{..} =
    ( rankArg
    , maxlenArg
    )
  where
    rankArg = maybe [] (\rank -> ["RANK", encode rank]) lposRank
    maxlenArg = maybe [] (\maxlen -> ["MAXLEN", encode maxlen]) lposMaxlen

-- |Move an element after taking it from one list and pushing it to another (<https://redis.io/commands/lmove>).
--
-- In clustered environments source and destination keys must be in the same hash slot, which can be ensured by using hash tags (e.g. @{tag}source@ and @{tag}destination@).
-- $O(1)$
--
-- Since Redis 6.2.0
lmove
    :: (RedisCtx m f)
    => ByteString    -- ^ Source
    -> ByteString    -- ^ Destination
    -> ListDirection -- ^ Direction where to get the element from in the source list
    -> ListDirection -- ^ Direction where to push the element to in the destination list
    -> m (f (Maybe ByteString))
lmove source destination from to =
    sendRequest ["LMOVE", source, destination, encode from, encode to]

-- |Move an element after taking it from one list and pushing it to another, or blocks until one is available (<https://redis.io/commands/blmove>).
--
-- In clustered environments source and destination keys must be in the same hash slot, which can be ensured by using hash tags (e.g. @{tag}source@ and @{tag}destination@).
--
-- $O(1)$
--
-- Since Redis 6.2.0
blmove
    :: (RedisCtx m f)
    => ByteString    -- ^ Source
    -> ByteString    -- ^ Destination
    -> ListDirection -- ^ Direction where to get the element from in the source list
    -> ListDirection -- ^ Direction where to push the element to in the destination list
    -> Integer
    -> m (f (Maybe ByteString))
blmove source destination from to timeout =
    sendRequest ["BLMOVE", source, destination, encode from, encode to, encode timeout]

-- |Pops one or more elements from the first non-empty list from a list of keys (<https://redis.io/commands/lmpop>).
--
-- $O(N+M)$ where $N$ is the number of provided keys and $M$ is the number of elements returned.
--
-- Since Redis 7.0.0
lmpop
    :: (RedisCtx m f)
    => NonEmpty ByteString
    -> ListDirection
    -> m (f (Maybe (ByteString, [ByteString])))
lmpop keys direction = lmpopCount keys direction 1

-- |Pops one or more elements from the first non-empty list from a list of keys (<https://redis.io/commands/lmpop>).
--
-- $O(N+M)$ where $N$ is the number of provided keys and $M$ is the number of elements returned.
--
-- Since Redis 7.0.0
lmpopCount
    :: (RedisCtx m f)
    => NonEmpty ByteString
    -> ListDirection
    -> Integer
    -> m (f (Maybe (ByteString, [ByteString])))
lmpopCount keys direction count =
    sendRequest $ ["LMPOP", encode (toInteger $ NE.length keys)] ++ NE.toList keys ++ [encode direction, "COUNT", encode count]

-- |Pops one or more elements from the first non-empty list from a list of keys, or blocks until one is available (<https://redis.io/commands/blmpop>).
--
-- $O(N+M)$ where $N$ is the number of provided keys and $M$ is the number of elements returned.
--
-- Since Redis 7.0.0
blmpop
    :: (RedisCtx m f)
    => Double
    -> NonEmpty ByteString
    -> ListDirection
    -> m (f (Maybe (ByteString, [ByteString])))
blmpop timeout keys direction = blmpopCount timeout keys direction 1

-- |Pops one or more elements from the first non-empty list from a list of keys, or blocks until one is available (<https://redis.io/commands/blmpop>).
--
-- $O(N+M)$ where $N$ is the number of provided keys and $M$ is the number of elements returned.
--
-- Since Redis 7.0.0
blmpopCount
    :: (RedisCtx m f)
    => Double
    -> NonEmpty ByteString
    -> ListDirection
    -> Integer
    -> m (f (Maybe (ByteString, [ByteString])))
blmpopCount timeout keys direction count =
    sendRequest $ ["BLMPOP", encode timeout, encode (toInteger $ NE.length keys)] ++ NE.toList keys ++ [encode direction, "COUNT", encode count]

-- |Determine the type stored at key (<http://redis.io/commands/type>). Since Redis 1.0.0
getType
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f RedisType)
getType key = sendRequest ["TYPE", key]

-- |A single entry from the slowlog.
data Slowlog = Slowlog
    { slowlogId        :: Integer
      -- ^ A unique progressive identifier for every slow log entry.
    , slowlogTimestamp :: Integer
      -- ^ The unix timestamp at which the logged command was processed.
    , slowlogMicros    :: Integer
      -- ^ The amount of time needed for its execution, in microseconds.
    , slowlogCmd       :: [ByteString]
      -- ^ The command and it's arguments.
    , slowlogClientIpAndPort :: Maybe ByteString
    , slowlogClientName :: Maybe ByteString
    } deriving (Show, Eq)

instance RedisResult Slowlog where
    decode (MultiBulk (Just [logId,timestamp,micros,cmd])) = do
        slowlogId        <- decode logId
        slowlogTimestamp <- decode timestamp
        slowlogMicros    <- decode micros
        slowlogCmd       <- decode cmd
        let slowlogClientIpAndPort = Nothing
            slowlogClientName = Nothing
        return Slowlog{..}
    decode (MultiBulk (Just [logId,timestamp,micros,cmd,ip,cname])) = do
        slowlogId        <- decode logId
        slowlogTimestamp <- decode timestamp
        slowlogMicros    <- decode micros
        slowlogCmd       <- decode cmd
        slowlogClientIpAndPort <- Just <$> decode ip
        slowlogClientName <- Just <$> decode cname
        return Slowlog{..}
    decode r = Left r

slowlogGet
    :: (RedisCtx m f)
    => Integer -- ^ cnt
    -> m (f [Slowlog])
slowlogGet n = sendRequest ["SLOWLOG", "GET", encode n]

slowlogLen :: (RedisCtx m f) => m (f Integer)
slowlogLen = sendRequest ["SLOWLOG", "LEN"]

slowlogReset :: (RedisCtx m f) => m (f Status)
slowlogReset = sendRequest ["SLOWLOG", "RESET"]

-- |Return a range of members in a sorted set, by index (<http://redis.io/commands/zrange>). The Redis command @ZRANGE@ is split up into 'zrange', 'zrangeWithscores'. Since Redis 1.2.0
zrange
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ stop
    -> m (f [ByteString])
zrange key start stop =
    sendRequest ["ZRANGE", encode key, encode start, encode stop]

-- |Return a range of members in a sorted set, by index (<http://redis.io/commands/zrange>). The Redis command @ZRANGE@ is split up into 'zrange', 'zrangeWithscores'. Since Redis 1.2.0
zrangeWithscores
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ stop
    -> m (f [(ByteString, Double)])
zrangeWithscores key start stop =
    sendRequest ["ZRANGE", encode key, encode start, encode stop, "WITHSCORES"]

zrevrange
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ stop
    -> m (f [ByteString])
zrevrange key start stop =
    sendRequest ["ZREVRANGE", encode key, encode start, encode stop]

zrevrangeWithscores
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ stop
    -> m (f [(ByteString, Double)])
zrevrangeWithscores key start stop =
    sendRequest ["ZREVRANGE", encode key, encode start, encode stop
                ,"WITHSCORES"]

zrangebyscore
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Double -- ^ min
    -> Double -- ^ max
    -> m (f [ByteString])
zrangebyscore key min max =
    sendRequest ["ZRANGEBYSCORE", encode key, encode min, encode max]

zrangebyscoreWithscores
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Double -- ^ min
    -> Double -- ^ max
    -> m (f [(ByteString, Double)])
zrangebyscoreWithscores key min max =
    sendRequest ["ZRANGEBYSCORE", encode key, encode min, encode max
                ,"WITHSCORES"]

zrangebyscoreLimit
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Double -- ^ min
    -> Double -- ^ max
    -> Integer -- ^ offset
    -> Integer -- ^ count
    -> m (f [ByteString])
zrangebyscoreLimit key min max offset count =
    sendRequest ["ZRANGEBYSCORE", encode key, encode min, encode max
                ,"LIMIT", encode offset, encode count]

zrangebyscoreWithscoresLimit
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Double -- ^ min
    -> Double -- ^ max
    -> Integer -- ^ offset
    -> Integer -- ^ count
    -> m (f [(ByteString, Double)])
zrangebyscoreWithscoresLimit key min max offset count =
    sendRequest ["ZRANGEBYSCORE", encode key, encode min, encode max
                ,"WITHSCORES","LIMIT", encode offset, encode count]

zrevrangebyscore
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Double -- ^ max
    -> Double -- ^ min
    -> m (f [ByteString])
zrevrangebyscore key min max =
    sendRequest ["ZREVRANGEBYSCORE", encode key, encode min, encode max]

zrevrangebyscoreWithscores
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Double -- ^ max
    -> Double -- ^ min
    -> m (f [(ByteString, Double)])
zrevrangebyscoreWithscores key min max =
    sendRequest ["ZREVRANGEBYSCORE", encode key, encode min, encode max
                ,"WITHSCORES"]

zrevrangebyscoreLimit
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Double -- ^ max
    -> Double -- ^ min
    -> Integer -- ^ offset
    -> Integer -- ^ count
    -> m (f [ByteString])
zrevrangebyscoreLimit key min max offset count =
    sendRequest ["ZREVRANGEBYSCORE", encode key, encode min, encode max
                ,"LIMIT", encode offset, encode count]

zrevrangebyscoreWithscoresLimit
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Double -- ^ max
    -> Double -- ^ min
    -> Integer -- ^ offset
    -> Integer -- ^ count
    -> m (f [(ByteString, Double)])
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

-- |Sort the elements in a list, set or sorted set (<http://redis.io/commands/sort>). The Redis command @SORT@ is split up into 'sort', 'sortStore'. Since Redis 1.0.0
sortStore
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ destination
    -> SortOpts
    -> m (f Integer)
sortStore key dest = sortInternal key (Just dest)

-- |Sort the elements in a list, set or sorted set (<http://redis.io/commands/sort>). The Redis command @SORT@ is split up into 'sort', 'sortStore'. Since Redis 1.0.0
sort
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> SortOpts
    -> m (f [ByteString])
sort key = sortInternal key Nothing

sortInternal
    :: (RedisResult a, RedisCtx m f)
    => ByteString -- ^ key
    -> Maybe ByteString -- ^ destination
    -> SortOpts
    -> m (f a)
sortInternal key destination SortOpts{..} = sendRequest $
    concat [["SORT", encode key], by, limit, get, order, alpha, store]
  where
    by    = maybe [] (\pattern -> ["BY", pattern]) sortBy
    limit = let (off,cnt) = sortLimit in ["LIMIT", encode off, encode cnt]
    get   = concatMap (\pattern -> ["GET", pattern]) sortGet
    order = case sortOrder of Desc -> ["DESC"]; Asc -> ["ASC"]
    alpha = ["ALPHA" | sortAlpha]
    store = maybe [] (\dest -> ["STORE", dest]) destination


data Aggregate = Sum | Min | Max deriving (Show,Eq)

zunionstore
    :: (RedisCtx m f)
    => ByteString -- ^ destination
    -> [ByteString] -- ^ keys
    -> Aggregate
    -> m (f Integer)
zunionstore dest keys =
    zstoreInternal "ZUNIONSTORE" dest keys []

zunionstoreWeights
    :: (RedisCtx m f)
    => ByteString -- ^ destination
    -> [(ByteString,Double)] -- ^ weighted keys
    -> Aggregate
    -> m (f Integer)
zunionstoreWeights dest kws =
    let (keys,weights) = unzip kws
    in zstoreInternal "ZUNIONSTORE" dest keys weights

-- |Intersect multiple sorted sets and store the resulting sorted set in a new key (<http://redis.io/commands/zinterstore>). The Redis command @ZINTERSTORE@ is split up into 'zinterstore', 'zinterstoreWeights'. Since Redis 2.0.0
zinterstore
    :: (RedisCtx m f)
    => ByteString -- ^ destination
    -> NonEmpty ByteString -- ^ keys
    -> Aggregate
    -> m (f Integer)
zinterstore dest (key_:|keys_) =
    zstoreInternal "ZINTERSTORE" dest (key_:keys_) []

-- |Intersect multiple sorted sets and store the resulting sorted set in a new key (<http://redis.io/commands/zinterstore>). The Redis command @ZINTERSTORE@ is split up into 'zinterstore', 'zinterstoreWeights'. Since Redis 2.0.0
zinterstoreWeights
    :: (RedisCtx m f)
    => ByteString -- ^ destination
    -> NonEmpty (ByteString,Double) -- ^ weighted keys
    -> Aggregate
    -> m (f Integer)
zinterstoreWeights dest kws =
    let (keys,weights) = unzip (NE.toList kws)
    in zstoreInternal "ZINTERSTORE" dest keys weights

zstoreInternal
    :: (RedisCtx m f)
    => ByteString -- ^ cmd
    -> ByteString -- ^ destination
    -> [ByteString] -- ^ keys
    -> [Double] -- ^ weights
    -> Aggregate
    -> m (f Integer)
zstoreInternal cmd dest keys weights aggregate = sendRequest $
    concat [ [cmd, dest, encode . toInteger $ length keys ], keys
           , if null weights then [] else "WEIGHTS" : map encode weights
           , ["AGGREGATE", aggregate']
           ]
  where
    aggregate' = case aggregate of
        Sum -> "SUM"
        Min -> "MIN"
        Max -> "MAX"

-- |Returns the difference between multiple sorted sets (<https://redis.io/commands/zdiff>).
--
-- $O(L + (N - K)\log(N))$ worst case where $L$ is the total number of elements in all the sorted sets, $N$ is the size of the first sorted set, and $K$ is the size of the result set.
--
-- In clustered environment, commands must operate on keys within the same hash slot.
--
-- Since Redis 6.2.0
zdiff
    :: (RedisCtx m f)
    => NonEmpty ByteString
    -> m (f [ByteString])
zdiff keys = sendRequest $ zAggregateKeysArgs "ZDIFF" keys

-- |Returns the difference between multiple sorted sets with scores (<https://redis.io/commands/zdiff>).
--
-- $O(L + (N - K)\log(N))$ worst case where $L$ is the total number of elements in all the sorted sets, $N$ is the size of the first sorted set, and $K$ is the size of the result set.
--
-- In clustered environment, commands must operate on keys within the same hash slot.
--
-- Since Redis 6.2.0
zdiffWithscores
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ Sorted set keys.
    -> m (f [(ByteString, Double)])
zdiffWithscores keys = sendRequest $ zAggregateKeysArgs "ZDIFF" keys ++ ["WITHSCORES"]

-- |Stores the difference of multiple sorted sets in a key (<https://redis.io/commands/zdiffstore>).
--
-- $O(L + (N - K)\log(N))$ worst case where $L$ is the total number of elements in all the sorted sets, $N$ is the size of the first sorted set, and $K$ is the size of the result set.
--
-- In clustered environment, commands must operate on keys within the same hash slot.
--
-- Keys that do not exist are considered to be empty sets.
--
-- If destination already exists, it is overwritten.
--
-- Since Redis 6.2.0
zdiffstore
    :: (RedisCtx m f)
    => ByteString -- ^ Destination key.
    -> NonEmpty ByteString -- ^ Sorted set keys.
    -> m (f Integer)
zdiffstore destination keys =
    sendRequest $ ["ZDIFFSTORE", destination] ++ tail (zAggregateKeysArgs "ZDIFF" keys)

-- |Returns the intersection of multiple sorted sets (<https://redis.io/commands/zinter>).
--
-- $O(NK) + O(M\log(M))$ worst case with $N$ being the smallest input sorted set, $K$ being the number of input sorted sets and $M$ being the number of elements in the resulting sorted set.
--
-- In clustered environment, commands must operate on keys within the same hash slot.
--
-- Since Redis 6.2.0
zinter
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ Sorted set keys.
    -> m (f [ByteString])
zinter keys = zinterOpts keys defaultZAggregateOpts


data ZAggregateOpts = ZAggregateOpts
    { zAggregateWeights :: [Double] -- ^ WEIGHTS option, it is possible to specify a multiplication factor for each input sorted set. Each element's score is multiplied by its corresponding weight before aggregation. When WEIGHTS is not given, the multiplication factors default to 1.
    , zAggregateAggregate :: Aggregate -- ^ AGGREGATE option, it is possible to specify how the results of the union are aggregated
    } deriving (Show, Eq)

defaultZAggregateOpts :: ZAggregateOpts
defaultZAggregateOpts = ZAggregateOpts
    { zAggregateWeights = []
    , zAggregateAggregate = Sum
    }

-- |Returns the intersection of multiple sorted sets with scores (<https://redis.io/commands/zinter>).
--
-- $O(NK) + O(M\log(M))$ worst case with $N$ being the smallest input sorted set, $K$ being the number of input sorted sets and $M$ being the number of elements in the resulting sorted set.
--
-- In clustered environment, commands must operate on keys within the same hash slot.
--
-- Since Redis 6.2.0
zinterWithscores
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ Sorted set keys.
    -> m (f [(ByteString, Double)])
zinterWithscores keys = zinterWithscoresOpts keys defaultZAggregateOpts

-- |Returns the intersection of multiple sorted sets (<https://redis.io/commands/zinter>).
--
-- $O(NK) + O(M\log(M))$ worst case with $N$ being the smallest input sorted set, $K$ being the number of input sorted sets and $M$ being the number of elements in the resulting sorted set.
--
-- In clustered environment, commands must operate on keys within the same hash slot.
--
-- Since Redis 6.2.0
zinterOpts
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ Sorted set keys.
    -> ZAggregateOpts
    -> m (f [ByteString])
zinterOpts keys opts = sendRequest $ zAggregateInternalArgs "ZINTER" keys opts False

-- |Returns the intersection of multiple sorted sets with scores (<https://redis.io/commands/zinter>).
--
-- $O(NK) + O(M\log(M))$ worst case with $N$ being the smallest input sorted set, $K$ being the number of input sorted sets and $M$ being the number of elements in the resulting sorted set.
--
-- In clustered environment, commands must operate on keys within the same hash slot.
--
-- Since Redis 6.2.0
zinterWithscoresOpts
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ Sorted set keys.
    -> ZAggregateOpts
    -> m (f [(ByteString, Double)])
zinterWithscoresOpts keys opts = sendRequest $ zAggregateInternalArgs "ZINTER" keys opts True

-- |Returns the union of multiple sorted sets (<https://redis.io/commands/zunion>).
--
-- $O(N) + O(M\log(M))$ with $N$ being the sum of the sizes of the input sorted sets, and $M$ being the number of elements in the resulting sorted set.
--
-- Since Redis 6.2.0
zunion
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ Sorted set keys.
    -> m (f [ByteString])
zunion keys = zunionOpts keys defaultZAggregateOpts

-- |Returns the union of multiple sorted sets with scores (<https://redis.io/commands/zunion>).
--
-- $O(N) + O(M\log(M))$ with $N$ being the sum of the sizes of the input sorted sets, and $M$ being the number of elements in the resulting sorted set.
--
-- Since Redis 6.2.0
zunionWithscores
    :: (RedisCtx m f)
    => NonEmpty ByteString
    -> m (f [(ByteString, Double)])
zunionWithscores keys = zunionWithscoresOpts keys defaultZAggregateOpts

-- |Returns the union of multiple sorted sets (<https://redis.io/commands/zunion>).
--
-- $O(N) + O(M\log(M))$ with $N$ being the sum of the sizes of the input sorted sets, and $M$ being the number of elements in the resulting sorted set.
--
-- Since Redis 6.2.0
zunionOpts
    :: (RedisCtx m f)
    => NonEmpty ByteString
    -> ZAggregateOpts
    -> m (f [ByteString])
zunionOpts keys opts = sendRequest $ zAggregateInternalArgs "ZUNION" keys opts False

-- |Returns the union of multiple sorted sets with scores (<https://redis.io/commands/zunion>).
--
-- $O(N) + O(M\log(M))$ with $N$ being the sum of the sizes of the input sorted sets, and $M$ being the number of elements in the resulting sorted set.
--
-- Since Redis 6.2.0
zunionWithscoresOpts
    :: (RedisCtx m f)
    => NonEmpty ByteString
    -> ZAggregateOpts
    -> m (f [(ByteString, Double)])
zunionWithscoresOpts keys opts = sendRequest $ zAggregateInternalArgs "ZUNION" keys opts True

zAggregateKeysArgs :: ByteString -> NonEmpty ByteString -> [ByteString]
zAggregateKeysArgs cmd keys =
    [cmd, encode . toInteger $ NE.length keys] ++ NE.toList keys

zAggregateInternalArgs :: ByteString -> NonEmpty ByteString -> ZAggregateOpts -> Bool -> [ByteString]
zAggregateInternalArgs cmd keys ZAggregateOpts{..} withScores =
    zAggregateKeysArgs cmd keys ++ weightsArg ++ aggregateArg ++ withScoresArg
  where
    weightsArg = ["WEIGHTS" | not (null zAggregateWeights)] ++ map encode zAggregateWeights
    aggregateArg = ["AGGREGATE", aggregateValue zAggregateAggregate]
    withScoresArg = ["WITHSCORES" | withScores]
    aggregateValue Sum = "SUM"
    aggregateValue Min = "MIN"
    aggregateValue Max = "MAX"

-- |Execute a Lua script server side (<http://redis.io/commands/eval>). Since Redis 2.6.0
eval
    :: (RedisCtx m f, RedisResult a)
    => ByteString -- ^ script
    -> [ByteString] -- ^ keys
    -> [ByteString] -- ^ args
    -> m (f a)
eval script keys args =
    sendRequest $ ["EVAL", script, encode numkeys] ++ keys ++ args
  where
    numkeys = toInteger (length keys)

-- | Works like 'eval', but sends the SHA1 hash of the script instead of the script itself.
-- Fails if the server does not recognise the hash, in which case, 'eval' should be used instead.
evalsha
    :: (RedisCtx m f, RedisResult a)
    => ByteString -- ^ base16-encoded sha1 hash of the script
    -> [ByteString] -- ^ keys
    -> [ByteString] -- ^ args
    -> m (f a)
evalsha script keys args =
    sendRequest $ ["EVALSHA", script, encode numkeys] ++ keys ++ args
  where
    numkeys = toInteger (length keys)

-- |Invokes a function (<https://redis.io/commands/fcall>).
--
-- Complexity depends on the function that is executed.
--
-- Since Redis 7.0.0
fcall
    :: (RedisCtx m f, RedisResult a)
    => ByteString
    -> [ByteString]
    -> [ByteString]
    -> m (f a)
fcall functionName keys args =
    sendRequest $ ["FCALL", functionName, encode numkeys] ++ keys ++ args
  where
    numkeys = toInteger (length keys)

-- |Invokes a read-only function (<https://redis.io/commands/fcall_ro>).
--
-- Complexity depends on the function that is executed.
--
-- Since Redis 7.0.0
fcallReadonly
    :: (RedisCtx m f, RedisResult a)
    => ByteString
    -> [ByteString]
    -> [ByteString]
    -> m (f a)
fcallReadonly functionName keys args =
    sendRequest $ ["FCALL_RO", functionName, encode numkeys] ++ keys ++ args
  where
    numkeys = toInteger (length keys)

data FunctionListOpts = FunctionListOpts
    { functionListLibraryName :: Maybe ByteString
    , functionListWithCode :: Bool
    } deriving (Show, Eq)

defaultFunctionListOpts :: FunctionListOpts
defaultFunctionListOpts = FunctionListOpts
    { functionListLibraryName = Nothing
    , functionListWithCode = False
    }

data FunctionRestorePolicy
    = FunctionRestoreAppend
    | FunctionRestoreFlush
    | FunctionRestoreReplace
    deriving (Show, Eq)

instance RedisArg FunctionRestorePolicy where
    encode FunctionRestoreAppend = "APPEND"
    encode FunctionRestoreFlush = "FLUSH"
    encode FunctionRestoreReplace = "REPLACE"

-- |Deletes a library and its functions (<https://redis.io/commands/function-delete>).
--
-- $O(1)$
--
-- Since Redis 7.0.0
functionDelete
    :: (RedisCtx m f)
    => ByteString
    -> m (f Status)
functionDelete libraryName = sendRequest ["FUNCTION", "DELETE", libraryName]

-- |Dumps all libraries into a serialized binary payload (<https://redis.io/commands/function-dump>).
--
-- $O(N)$ where $N$ is the number of functions.
--
-- Since Redis 7.0.0
functionDump
    :: (RedisCtx m f)
    => m (f ByteString)
functionDump = sendRequest ["FUNCTION", "DUMP"]

-- |Deletes all libraries and functions (<https://redis.io/commands/function-flush>).
--
-- $O(N)$ where $N$ is the number of functions deleted.
--
-- Since Redis 7.0.0
functionFlush
    :: (RedisCtx m f)
    => m (f Status)
functionFlush = sendRequest ["FUNCTION", "FLUSH"]

-- |Deletes all libraries and functions (<https://redis.io/commands/function-flush>).
--
-- $O(N)$ where $N$ is the number of functions deleted.
--
-- Since Redis 7.0.0
functionFlushOpts
    :: (RedisCtx m f)
    => FlushOpts
    -> m (f Status)
functionFlushOpts opts = sendRequest ["FUNCTION", "FLUSH", encode opts]

-- |Returns helpful text about FUNCTION subcommands (<https://redis.io/commands/function-help>).
--
-- $O(1)$
--
-- Since Redis 7.0.0
functionHelp
    :: (RedisCtx m f)
    => m (f [ByteString])
functionHelp = sendRequest ["FUNCTION", "HELP"]

-- |Terminates a function during execution (<https://redis.io/commands/function-kill>).
--
-- $O(1)$
--
-- Since Redis 7.0.0
functionKill
    :: (RedisCtx m f)
    => m (f Status)
functionKill = sendRequest ["FUNCTION", "KILL"]

-- |Returns information about all libraries (<https://redis.io/commands/function-list>).
--
-- $O(N)$ where $N$ is the number of functions.
--
-- Since Redis 7.0.0
functionList
    :: (RedisCtx m f)
    => m (f Reply)
functionList = functionListOpts defaultFunctionListOpts

-- |Returns information about all libraries (<https://redis.io/commands/function-list>).
--
-- $O(N)$ where $N$ is the number of functions.
--
-- Since Redis 7.0.0
functionListOpts
    :: (RedisCtx m f)
    => FunctionListOpts
    -> m (f Reply)
functionListOpts FunctionListOpts{..} =
    sendRequest $ ["FUNCTION", "LIST"] ++ libraryArg ++ withCodeArg
  where
    libraryArg = maybe [] (\libraryName -> ["LIBRARYNAME", libraryName]) functionListLibraryName
    withCodeArg = ["WITHCODE" | functionListWithCode]

-- |Creates a library (<https://redis.io/commands/function-load>).
--
-- $O(N)$ where $N$ is the number of bytes in the function's source code.
--
-- Since Redis 7.0.0
functionLoad
    :: (RedisCtx m f)
    => ByteString
    -> m (f ByteString)
functionLoad libraryCode = sendRequest ["FUNCTION", "LOAD", libraryCode]

-- |Creates a library, replacing an existing one with the same name (<https://redis.io/commands/function-load>).
--
-- $O(N)$ where $N$ is the number of bytes in the function's source code.
--
-- Since Redis 7.0.0
functionLoadReplace
    :: (RedisCtx m f)
    => ByteString
    -> m (f ByteString)
functionLoadReplace libraryCode = sendRequest ["FUNCTION", "LOAD", "REPLACE", libraryCode]

-- |Restores all libraries from a payload (<https://redis.io/commands/function-restore>).
--
-- $O(N)$ where $N$ is the number of functions restored.
--
-- Since Redis 7.0.0
functionRestore
    :: (RedisCtx m f)
    => ByteString
    -> Maybe FunctionRestorePolicy
    -> m (f Status)
functionRestore payload restorePolicy =
    sendRequest $ ["FUNCTION", "RESTORE", payload] ++ maybe [] (\policy -> [encode policy]) restorePolicy

-- |Returns information about a function during execution (<https://redis.io/commands/function-stats>).
--
-- $O(1)$
--
-- Since Redis 7.0.0
functionStats
    :: (RedisCtx m f)
    => m (f Reply)
functionStats = sendRequest ["FUNCTION", "STATS"]

bitcount
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f Integer)
bitcount key = sendRequest ["BITCOUNT", key]

bitcountRange
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ end
    -> m (f Integer)
bitcountRange key start end =
    sendRequest ["BITCOUNT", key, encode start, encode end]

bitopAnd
    :: (RedisCtx m f)
    => ByteString -- ^ destkey
    -> [ByteString] -- ^ srckeys
    -> m (f Integer)
bitopAnd dst srcs = bitop "AND" (dst:srcs)

bitopOr
    :: (RedisCtx m f)
    => ByteString -- ^ destkey
    -> [ByteString] -- ^ srckeys
    -> m (f Integer)
bitopOr dst srcs = bitop "OR" (dst:srcs)

bitopXor
    :: (RedisCtx m f)
    => ByteString -- ^ destkey
    -> [ByteString] -- ^ srckeys
    -> m (f Integer)
bitopXor dst srcs = bitop "XOR" (dst:srcs)

bitopNot
    :: (RedisCtx m f)
    => ByteString -- ^ destkey
    -> ByteString -- ^ srckey
    -> m (f Integer)
bitopNot dst src = bitop "NOT" [dst, src]

bitop
    :: (RedisCtx m f)
    => ByteString -- ^ operation
    -> [ByteString] -- ^ keys
    -> m (f Integer)
bitop op ks = sendRequest $ "BITOP" : op : ks

data VAddQuantization
    = VAddNoQuant
    | VAddQ8
    | VAddBin
    deriving (Show, Eq)

instance RedisArg VAddQuantization where
    encode VAddNoQuant = "NOQUANT"
    encode VAddQ8 = "Q8"
    encode VAddBin = "BIN"

data VAddOpts = VAddOpts
    { vAddReduceDim :: Maybe Integer
    , vAddCas :: Bool
    , vAddQuantization :: Maybe VAddQuantization
    , vAddBuildExplorationFactor :: Maybe Integer
    , vAddAttributes :: Maybe ByteString
    , vAddNumLinks :: Maybe Integer
    } deriving (Show, Eq)

data VQuantization
    = VQuantizationFP32
    | VQuantizationBin
    | VQuantizationQ8
    deriving (Show, Eq)

instance RedisArg VQuantization where
    encode VQuantizationFP32 = "FP32"
    encode VQuantizationBin = "BIN"
    encode VQuantizationQ8 = "Q8"

instance RedisResult VQuantization where
    decode (SingleLine "fp32") = Right VQuantizationFP32
    decode (SingleLine "f32") = Right VQuantizationFP32
    decode (SingleLine "bin") = Right VQuantizationBin
    decode (SingleLine "q8") = Right VQuantizationQ8
    decode (SingleLine "int8") = Right VQuantizationQ8
    decode (Bulk (Just "fp32")) = Right VQuantizationFP32
    decode (Bulk (Just "f32")) = Right VQuantizationFP32
    decode (Bulk (Just "bin")) = Right VQuantizationBin
    decode (Bulk (Just "q8")) = Right VQuantizationQ8
    decode (Bulk (Just "int8")) = Right VQuantizationQ8
    decode r = Left r

data VEmbRawResponse = VEmbRawResponse
    { vEmbRawQuantization :: VQuantization
    , vEmbRawData :: ByteString
    , vEmbRawNorm :: Double
    , vEmbRawRange :: Maybe Double
    } deriving (Show, Eq)

instance RedisResult VEmbRawResponse where
    decode (MultiBulk (Just [quantizationReply, rawDataReply, normReply])) =
        VEmbRawResponse
            <$> decode quantizationReply
            <*> decode rawDataReply
            <*> decode normReply
            <*> pure Nothing
    decode (MultiBulk (Just [quantizationReply, rawDataReply, normReply, rangeReply])) =
        VEmbRawResponse
            <$> decode quantizationReply
            <*> decode rawDataReply
            <*> decode normReply
            <*> (Just <$> decode rangeReply)
    decode r = Left r

data VInfoResponse = VInfoResponse
    { vInfoQuantization :: Maybe ByteString
    , vInfoVectorDim :: Maybe Integer
    , vInfoSize :: Maybe Integer
    , vInfoMaxLevel :: Maybe Integer
    , vInfoUid :: Maybe Integer
    , vInfoHnswMaxNodeUid :: Maybe Integer
    } deriving (Show, Eq)

instance RedisResult VInfoResponse where
    decode r@(MultiBulk (Just replies)) =
        parsePairs replies >>= buildInfo
      where
        parsePairs [] = Right []
        parsePairs (keyReply:valueReply:rest) =
            (:) <$> ((,) <$> decode keyReply <*> pure valueReply) <*> parsePairs rest
        parsePairs _ = Left r

        buildInfo pairs = Right VInfoResponse
            { vInfoQuantization = lookupDecoded "quant-type" pairs
            , vInfoVectorDim = lookupDecoded "vector-dim" pairs
            , vInfoSize = lookupDecoded "size" pairs
            , vInfoMaxLevel = lookupDecoded "max-level" pairs
            , vInfoUid = lookupDecoded "vset-uid" pairs
            , vInfoHnswMaxNodeUid = lookupDecoded "hnsw-max-node-uid" pairs
            }

        lookupDecoded :: RedisResult a => ByteString -> [(ByteString, Reply)] -> Maybe a
        lookupDecoded key pairs = lookup key pairs >>= either (const Nothing) Just . decode
    decode r = Left r

newtype VLinksResponse = VLinksResponse
    { vLinksLayers :: [[ByteString]]
    } deriving (Show, Eq)

instance RedisResult VLinksResponse where
    decode (MultiBulk (Just layers)) = VLinksResponse <$> mapM decode layers
    decode r = Left r

newtype VLinksWithScoresResponse = VLinksWithScoresResponse
    { vLinksWithScoresLayers :: [[(ByteString, Double)]]
    } deriving (Show, Eq)

instance RedisResult VLinksWithScoresResponse where
    decode r@(MultiBulk (Just layers)) =
        VLinksWithScoresResponse <$> mapM decodeLayer layers
      where
        decodeLayer (MultiBulk (Just entries)) = pairs entries
        decodeLayer badReply = Left badReply

        pairs [] = Right []
        pairs (nameReply:scoreReply:rest) =
            (:) <$> ((,) <$> decode nameReply <*> decode scoreReply) <*> pairs rest
        pairs _ = Left r
    decode r = Left r

data VSimQuery
    = VSimByElement ByteString
    | VSimByFp32 ByteString
    | VSimByValues (NonEmpty Double)
    deriving (Show, Eq)

data VSimOpts = VSimOpts
    { vSimCount :: Maybe Integer
    , vSimEpsilon :: Maybe Double
    , vSimEf :: Maybe Integer
    , vSimFilter :: Maybe ByteString
    , vSimFilterEf :: Maybe Integer
    , vSimTruth :: Bool
    , vSimNoThread :: Bool
    } deriving (Show, Eq)

defaultVSimOpts :: VSimOpts
defaultVSimOpts = VSimOpts
    { vSimCount = Nothing
    , vSimEpsilon = Nothing
    , vSimEf = Nothing
    , vSimFilter = Nothing
    , vSimFilterEf = Nothing
    , vSimTruth = False
    , vSimNoThread = False
    }

data VSimWithAttribsResult = VSimWithAttribsResult
    { vSimResultElement :: ByteString
    , vSimResultScore :: Double
    , vSimResultAttributes :: Maybe ByteString
    } deriving (Show, Eq)

instance RedisResult VSimWithAttribsResult where
    decode (MultiBulk (Just [elementReply, scoreReply, Bulk Nothing])) =
        VSimWithAttribsResult
            <$> decode elementReply
            <*> decode scoreReply
            <*> pure Nothing
    decode (MultiBulk (Just [elementReply, scoreReply, attributesReply])) =
        VSimWithAttribsResult
            <$> decode elementReply
            <*> decode scoreReply
            <*> (Just <$> decode attributesReply)
    decode r = Left r

newtype VSimWithAttribsResponse = VSimWithAttribsResponse
    { vSimWithAttribsResults :: [VSimWithAttribsResult]
    } deriving (Show, Eq)

instance RedisResult VSimWithAttribsResponse where
    decode r@(MultiBulk (Just replies)) =
        VSimWithAttribsResponse <$> triples replies
      where
        triples [] = Right []
        triples (elementReply:scoreReply:Bulk Nothing:rest) = do
            result <- VSimWithAttribsResult
                <$> decode elementReply
                <*> decode scoreReply
                <*> pure Nothing
            (result :) <$> triples rest
        triples (elementReply:scoreReply:attributesReply:rest) = do
            result <- VSimWithAttribsResult
                <$> decode elementReply
                <*> decode scoreReply
                <*> (Just <$> decode attributesReply)
            (result :) <$> triples rest
        triples _ = Left r
    decode r = Left r

-- |Redis default 'VAddOpts'. Equivalent to omitting all optional parameters.
defaultVAddOpts :: VAddOpts
defaultVAddOpts = VAddOpts
    { vAddReduceDim = Nothing
    , vAddCas = False
    , vAddQuantization = Nothing
    , vAddBuildExplorationFactor = Nothing
    , vAddAttributes = Nothing
    , vAddNumLinks = Nothing
    }

-- |Adds a new element to a vector set, or updates its vector if it already exists (<https://redis.io/commands/vadd>).
--
-- $O(log(N))$ for each element added, where $N$ is the number of elements in the vector set.
--
-- Since Redis 8.0.0
vadd
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that will hold the vector set data.
    -> NonEmpty Double
    {- ^ The vector values as floating point numbers.

       This uses the `VALUES` argument form and automatically supplies the number of vector elements.
     -}
    -> ByteString -- ^ The name of the element that is being added to the vector set.
    -> m (f Bool)
vadd key vector element = vaddOpts key vector element defaultVAddOpts

-- |Adds a new element to a vector set, or updates its vector if it already exists (<https://redis.io/commands/vadd>).
--
-- $O(log(N))$ for each element added, where $N$ is the number of elements in the vector set.
--
-- Since Redis 8.0.0
vaddOpts
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that will hold the vector set data.
    -> NonEmpty Double -- ^ The vector values as floating point numbers.
    -> ByteString -- ^ The name of the element that is being added to the vector set.
    -> VAddOpts
    {- ^ Additional parameters.

       `REDUCE dim` reduces the dimensionality of the vector using random projection.
       `CAS` performs the slow neighbor candidate collection in the background.
       `NOQUANT`, `Q8`, and `BIN` control quantization and are mutually exclusive.
       `EF` sets the build exploration factor.
       `SETATTR` associates attributes with the entry.
       `M` sets the maximum number of graph links per node.
     -}
    -> m (f Bool)
vaddOpts key vector element VAddOpts{..} =
    sendRequest $
        ["VADD", key]
            ++ reduceArg
            ++ ["VALUES", encode (toInteger $ NE.length vector)]
            ++ map encode (NE.toList vector)
            ++ [element]
            ++ casArg
            ++ quantizationArg
            ++ efArg
            ++ attributesArg
            ++ numLinksArg
  where
    reduceArg = maybe [] (\dim -> ["REDUCE", encode dim]) vAddReduceDim
    casArg = ["CAS" | vAddCas]
    quantizationArg = maybe [] (\quantization -> [encode quantization]) vAddQuantization
    efArg = maybe [] (\ef -> ["EF", encode ef]) vAddBuildExplorationFactor
    attributesArg = maybe [] (\attributes -> ["SETATTR", attributes]) vAddAttributes
    numLinksArg = maybe [] (\numLinks -> ["M", encode numLinks]) vAddNumLinks

-- |Return the number of elements in the specified vector set (<https://redis.io/commands/vcard>).
--
-- $O(1)$
--
-- Since Redis 8.0.0
vcard
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that holds the vector set.
    -> m (f Integer)
vcard key = sendRequest ["VCARD", key]

-- |Return the number of dimensions of the vectors in the specified vector set (<https://redis.io/commands/vdim>).
--
-- $O(1)$
--
-- Since Redis 8.0.0
vdim
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that holds the vector set.
    -> m (f Integer)
vdim key = sendRequest ["VDIM", key]

-- |Return the approximate vector associated with a given element in the vector set (<https://redis.io/commands/vemb>).
--
-- $O(1)$
--
-- Since Redis 8.0.0
vemb
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that holds the vector set.
    -> ByteString -- ^ The name of the element whose vector you want to retrieve.
    -> m (f [Double])
vemb key element = sendRequest ["VEMB", key, element]

-- |Return the raw internal representation of the vector associated with a given element in the vector set (<https://redis.io/commands/vemb>).
--
-- $O(1)$
--
-- Since Redis 8.0.0
vembRaw
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that holds the vector set.
    -> ByteString -- ^ The name of the element whose vector you want to retrieve.
    -> m (f (Maybe VEmbRawResponse))
vembRaw key element = sendRequest ["VEMB", key, element, "RAW"]

-- |Retrieve the JSON attributes of an element in a vector set (<https://redis.io/commands/vgetattr>).
--
-- $O(1)$
--
-- Since Redis 8.0.0
vgetattr
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that holds the vector set.
    -> ByteString -- ^ The name of the element whose attributes you want to retrieve.
    -> m (f (Maybe ByteString))
vgetattr key element = sendRequest ["VGETATTR", key, element]

-- |Return metadata and internal details about a vector set (<https://redis.io/commands/vinfo>).
--
-- $O(1)$
--
-- Since Redis 8.0.0
vinfo
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that holds the vector set.
    -> m (f (Maybe VInfoResponse))
vinfo key = sendRequest ["VINFO", key]

-- |Check if an element exists in a vector set (<https://redis.io/commands/vismember>).
--
-- $O(1)$
--
-- Since Redis 8.0.0
vismember
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that holds the vector set.
    -> ByteString -- ^ The name of the element to check.
    -> m (f Bool)
vismember key element = sendRequest ["VISMEMBER", key, element]

-- |Return the neighbors of a specified element in a vector set (<https://redis.io/commands/vlinks>).
--
-- $O(1)$
--
-- Since Redis 8.0.0
vlinks
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that holds the vector set.
    -> ByteString -- ^ The name of the element whose HNSW neighbors you want to inspect.
    -> m (f (Maybe VLinksResponse))
vlinks key element = sendRequest ["VLINKS", key, element]

-- |Return the neighbors of a specified element in a vector set together with their similarity scores (<https://redis.io/commands/vlinks>).
--
-- $O(1)$
--
-- Since Redis 8.0.0
vlinksWithScores
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that holds the vector set.
    -> ByteString -- ^ The name of the element whose HNSW neighbors you want to inspect.
    -> m (f (Maybe VLinksWithScoresResponse))
vlinksWithScores key element = sendRequest ["VLINKS", key, element, "WITHSCORES"]

-- |Return one random element from a vector set (<https://redis.io/commands/vrandmember>).
--
-- $O(N)$ where $N$ is the absolute value of the count argument.
--
-- Since Redis 8.0.0
vrandmember
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that holds the vector set.
    -> m (f (Maybe ByteString))
vrandmember key = sendRequest ["VRANDMEMBER", key]

-- |Return one or multiple random elements from a vector set (<https://redis.io/commands/vrandmember>).
--
-- $O(N)$ where $N$ is the absolute value of the count argument.
--
-- Since Redis 8.0.0
vrandmemberCount
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that holds the vector set.
    -> Integer
    {- ^ The number of elements to return.

       Positive values return distinct elements; negative values allow duplicates.
     -}
    -> m (f [ByteString])
vrandmemberCount key count = sendRequest ["VRANDMEMBER", key, encode count]

-- |Returns elements in a lexicographical range (<https://redis.io/commands/vrange>).
--
-- $O(log(K)+M)$ where $K$ is the number of elements in the start prefix, and $M$ is the number of elements returned. In practical terms, the command is just $O(M)$.
--
-- Since Redis 8.4.0
vrange
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the vector set key from which to retrieve elements.
    -> ByteString
    {- ^ The starting point of the lexicographical range.

       Use a value prefixed with `[` for an inclusive bound, a value prefixed with `(` for an exclusive bound, or `-` for the minimum element.
     -}
    -> ByteString
    {- ^ The ending point of the lexicographical range.

       Use a value prefixed with `[` for an inclusive bound, a value prefixed with `(` for an exclusive bound, or `+` for the maximum element.
     -}
    -> m (f [ByteString])
vrange key start end = sendRequest ["VRANGE", key, start, end]

-- |Returns elements in a lexicographical range (<https://redis.io/commands/vrange>).
--
-- $O(log(K)+M)$ where $K$ is the number of elements in the start prefix, and $M$ is the number of elements returned. In practical terms, the command is just $O(M)$.
--
-- Since Redis 8.4.0
vrangeCount
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the vector set key from which to retrieve elements.
    -> ByteString -- ^ The starting point of the lexicographical range.
    -> ByteString -- ^ The ending point of the lexicographical range.
    -> Integer
    {- ^ The maximum number of elements to return.

       If `count` is negative, the command returns all elements in the specified range.
     -}
    -> m (f [ByteString])
vrangeCount key start end count =
    sendRequest ["VRANGE", key, start, end, encode count]

-- |Remove an element from a vector set (<https://redis.io/commands/vrem>).
--
-- $O(log(N))$ for each element removed, where $N$ is the number of elements in the vector set.
--
-- Since Redis 8.0.0
vrem
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that holds the vector set.
    -> ByteString -- ^ The name of the element to remove from the vector set.
    -> m (f Bool)
vrem key element = sendRequest ["VREM", key, element]

-- |Associate or remove the JSON attributes of an element in a vector set (<https://redis.io/commands/vsetattr>).
--
-- $O(1)$
--
-- Since Redis 8.0.0
vsetattr
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that holds the vector set.
    -> ByteString -- ^ The name of the element in the vector set.
    -> ByteString
    {- ^ The attributes as a JSON object string.

       Use the empty string to remove existing attributes.
     -}
    -> m (f Bool)
vsetattr key element attributes = sendRequest ["VSETATTR", key, element, attributes]

-- |Return elements similar to a given vector or element (<https://redis.io/commands/vsim>).
--
-- $O(log(N))$ where $N$ is the number of elements in the vector set.
--
-- Since Redis 8.0.0
vsim
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that holds the vector set data.
    -> VSimQuery
    {- ^ Query vector source.

       Use `VSimByElement` to refer to an existing element, `VSimByFp32` for binary float format, or `VSimByValues` for a list of float values.
     -}
    -> m (f [ByteString])
vsim key query = vsimOpts key query defaultVSimOpts

-- |Return elements similar to a given vector or element (<https://redis.io/commands/vsim>).
--
-- $O(log(N))$ where $N$ is the number of elements in the vector set.
--
-- Since Redis 8.0.0
vsimOpts
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that holds the vector set data.
    -> VSimQuery -- ^ Query vector source.
    -> VSimOpts
    {- ^ Additional search options.

       `COUNT` limits the number of returned results.
       `EPSILON` filters out elements that are too far from the query vector.
       `EF` controls the exploration factor.
       `FILTER` applies a filtering expression and `FILTER-EF` limits filtering effort.
       `TRUTH` forces an exact linear scan.
       `NOTHREAD` executes the search in the main thread.
     -}
    -> m (f [ByteString])
vsimOpts key query opts =
    sendRequest $ ["VSIM", key] ++ vSimQueryArgs query ++ vSimOptsArgs opts

-- |Return elements similar to a given vector or element together with their similarity scores (<https://redis.io/commands/vsim>).
--
-- $O(log(N))$ where $N$ is the number of elements in the vector set.
--
-- Since Redis 8.0.0
vsimWithScores
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that holds the vector set data.
    -> VSimQuery -- ^ Query vector source.
    -> m (f [(ByteString, Double)])
vsimWithScores key query = vsimWithScoresOpts key query defaultVSimOpts

-- |Return elements similar to a given vector or element together with their similarity scores (<https://redis.io/commands/vsim>).
--
-- $O(log(N))$ where $N$ is the number of elements in the vector set.
--
-- Since Redis 8.0.0
vsimWithScoresOpts
    :: (RedisCtx m f)
    => ByteString
    -> VSimQuery
    -> VSimOpts
    -> m (f [(ByteString, Double)])
vsimWithScoresOpts key query opts =
    sendRequest $ ["VSIM", key] ++ vSimQueryArgs query ++ ["WITHSCORES"] ++ vSimOptsArgs opts

-- |Return elements similar to a given vector or element together with their similarity scores and JSON attributes (<https://redis.io/commands/vsim>).
--
-- $O(log(N))$ where $N$ is the number of elements in the vector set.
--
-- Since Redis 8.2.0
vsimWithScoresWithAttribs
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key that holds the vector set data.
    -> VSimQuery -- ^ Query vector source.
    -> m (f VSimWithAttribsResponse)
vsimWithScoresWithAttribs key query =
    vsimWithScoresWithAttribsOpts key query defaultVSimOpts

-- |Return elements similar to a given vector or element together with their similarity scores and JSON attributes (<https://redis.io/commands/vsim>).
--
-- $O(log(N))$ where $N$ is the number of elements in the vector set.
--
-- Since Redis 8.2.0
vsimWithScoresWithAttribsOpts
    :: (RedisCtx m f)
    => ByteString
    -> VSimQuery
    -> VSimOpts
    -> m (f VSimWithAttribsResponse)
vsimWithScoresWithAttribsOpts key query opts =
    sendRequest $ ["VSIM", key] ++ vSimQueryArgs query ++ ["WITHSCORES", "WITHATTRIBS"] ++ vSimOptsArgs opts

vSimQueryArgs :: VSimQuery -> [ByteString]
vSimQueryArgs query =
    case query of
        VSimByElement element -> ["ELE", element]
        VSimByFp32 rawVector -> ["FP32", rawVector]
        VSimByValues values ->
            ["VALUES", encode (toInteger $ NE.length values)] ++ map encode (NE.toList values)

vSimOptsArgs :: VSimOpts -> [ByteString]
vSimOptsArgs VSimOpts{..} =
    countArg ++ epsilonArg ++ efArg ++ filterArg ++ filterEfArg ++ truthArg ++ noThreadArg
  where
    countArg = maybe [] (\count -> ["COUNT", encode count]) vSimCount
    epsilonArg = maybe [] (\epsilon -> ["EPSILON", encode epsilon]) vSimEpsilon
    efArg = maybe [] (\ef -> ["EF", encode ef]) vSimEf
    filterArg = maybe [] (\expression -> ["FILTER", expression]) vSimFilter
    filterEfArg = maybe [] (\filterEf -> ["FILTER-EF", encode filterEf]) vSimFilterEf
    truthArg = ["TRUTH" | vSimTruth]
    noThreadArg = ["NOTHREAD" | vSimNoThread]

-- |Atomically transfer a key from a Redis instance to another one (<http://redis.io/commands/migrate>). The Redis command @MIGRATE@ is split up into 'migrate', 'migrateMultiple'. Since Redis 2.6.0
migrate
    :: (RedisCtx m f)
    => ByteString -- ^ host
    -> ByteString -- ^ port
    -> ByteString -- ^ key
    -> Integer -- ^ destinationDb
    -> Integer -- ^ timeout
    -> m (f Status)
migrate host port key destinationDb timeout =
  sendRequest ["MIGRATE", host, port, key, encode destinationDb, encode timeout]

data MigrateAuth
  = MigrateAuth ByteString
  | MigrateAuth2 ByteString ByteString
  deriving (Show, Eq)

-- |Options for the 'migrate' command.
data MigrateOpts = MigrateOpts
    { migrateCopy    :: Bool
    , migrateReplace :: Bool
    , migrateAuth :: Maybe MigrateAuth
    } deriving (Show, Eq)

-- |Redis default 'MigrateOpts'. Equivalent to omitting all optional parameters.
--
-- @
-- MigrateOpts
--     { migrateCopy    = False -- remove the key from the local instance
--     , migrateReplace = False -- don't replace existing key on the remote instance
--     , migrateAuth = Nothing
--     }
-- @
--
defaultMigrateOpts :: MigrateOpts
defaultMigrateOpts = MigrateOpts
    { migrateCopy    = False
    , migrateReplace = False
    , migrateAuth = Nothing
    }

-- |Atomically transfer a key from a Redis instance to another one (<http://redis.io/commands/migrate>). The Redis command @MIGRATE@ is split up into 'migrate', 'migrateMultiple'. Since Redis 2.6.0
migrateMultiple
    :: (RedisCtx m f)
    => ByteString   -- ^ host
    -> ByteString   -- ^ port
    -> Integer      -- ^ destinationDb
    -> Integer      -- ^ timeout
    -> MigrateOpts
    -> [ByteString] -- ^ keys
    -> m (f Status)
migrateMultiple host port destinationDb timeout MigrateOpts{..} keys =
    sendRequest $
    concat [["MIGRATE", host, port, empty, encode destinationDb, encode timeout],
            auth_, copyArg, replace, keys]
  where
    copyArg = ["COPY" | migrateCopy]
    replace = ["REPLACE" | migrateReplace]
    auth_ = case migrateAuth of
     Nothing -> []
     Just (MigrateAuth pass)  -> ["AUTH", pass]
     Just (MigrateAuth2 user pass)  -> ["AUTH2", user, pass]


-- |Create a key using the provided serialized value, previously obtained using DUMP (<http://redis.io/commands/restore>). The Redis command @RESTORE@ is split up into 'restore', 'restoreReplace'. Since Redis 2.6.0
restore
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ timeToLive
    -> ByteString -- ^ serializedValue
    -> m (f Status)
restore key timeToLive serializedValue =
  sendRequest ["RESTORE", key, encode timeToLive, serializedValue]

data RestoreOpts = RestoreOpts
  { restoreOptsReplace :: Bool
  , restoreOptsAbsTTL :: Bool
  , restoreOptsIdle  :: Maybe Integer
  , restoreOptsFreq :: Maybe Integer
  }

-- |Create a key using the provided serialized value, previously obtained using DUMP (<http://redis.io/commands/restore>). The Redis command @RESTORE@ is split up into 'restore', 'restoreReplace'. Since Redis 2.6.0
restoreOpts
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ timeToLive
    -> ByteString -- ^ serializedValue
    -> RestoreOpts -- ^ restore options
    -> m (f Status)
restoreOpts key timeToLive serializedValue RestoreOpts{..} =
  sendRequest ("RESTORE": key: encode timeToLive: serializedValue:rest) where
  rest =  replace <> absttl <> idle <> freq
  replace = ["REPLACE" | restoreOptsReplace]
  absttl  = ["ABSTTL" | restoreOptsAbsTTL]
  idle    = maybe [] (\i -> ["IDLE", encode i]) restoreOptsIdle
  freq    = maybe [] (\f -> ["FREQ", encode f]) restoreOptsFreq

-- |Create a key using the provided serialized value, previously obtained using DUMP (<http://redis.io/commands/restore>). The Redis command @RESTORE@ is split up into 'restore', 'restoreReplace'. Since Redis 2.6.0

restoreReplace
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ timeToLive
    -> ByteString -- ^ serializedValue
    -> m (f Status)
restoreReplace key timeToLive serializedValue =
  sendRequest ["RESTORE", key, encode timeToLive, serializedValue, "REPLACE"]

data CopyOpts = CopyOpts
  { copyDestinationDb :: Maybe Integer
  , copyReplace :: Bool
  } deriving (Show, Eq)

defaultCopyOpts :: CopyOpts
defaultCopyOpts = CopyOpts
  { copyDestinationDb = Nothing
  , copyReplace = False
  }

-- |Copies the value of a key to a new key (<https://redis.io/commands/copy>).
--
-- $O(N)$ worst case for collections, where $N$ is the number of nested items. $O(1)$ for string values.
--
-- Since Redis 6.2.0
copy
    :: (RedisCtx m f)
    => ByteString
    -> ByteString
    -> m (f Bool)
copy source destination = copyOpts source destination defaultCopyOpts

-- |Copies the value of a key to a new key (<https://redis.io/commands/copy>).
--
-- $O(N)$ worst case for collections, where $N$ is the number of nested items. $O(1)$ for string values.
--
-- Since Redis 6.2.0
copyOpts
    :: (RedisCtx m f)
    => ByteString
    -> ByteString
    -> CopyOpts
    -> m (f Bool)
copyOpts source destination CopyOpts{..} =
    sendRequest $ ["COPY", source, destination] ++ dbArg ++ replaceArg
  where
    dbArg = maybe [] (\destinationDb -> ["DB", encode destinationDb]) copyDestinationDb
    replaceArg = ["REPLACE" | copyReplace]

-- |Returns the expiration time of a key as a Unix timestamp (<https://redis.io/commands/expiretime>).
--
-- Returns @-2@ if the key does not exist; @-1@ if the key exists but has no associated expiration.
--
-- $O(1)$. Since Redis 7.0.0
expiretime
    :: (RedisCtx m f)
    => ByteString
    -> m (f Integer)
expiretime key = sendRequest ["EXPIRETIME", key]

-- |Returns the expiration time of a key as a Unix timestamp in milliseconds (<https://redis.io/commands/pexpiretime>).
--
-- Returns @-2@ if the key does not exist; @-1@ if the key exists but has no associated expiration.
--
-- $O(1)$. Since Redis 7.0.0
pexpiretime
    :: (RedisCtx m f)
    => ByteString
    -> m (f Integer)
pexpiretime key = sendRequest ["PEXPIRETIME", key]


set
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ value
    -> m (f Status)
set key value = sendRequest ["SET", key, value]


data Condition =
  Nx | -- ^ Only set the key if it does not already exist.
  Xx   -- ^ Only set the key if it already exists.
   deriving (Show, Eq)


instance RedisArg Condition where
  encode Nx = "NX"
  encode Xx = "XX"


data SetOpts = SetOpts
  { setSeconds           :: Maybe Integer -- ^ Set the specified expire time, in seconds.
  , setMilliseconds      :: Maybe Integer -- ^ Set the specified expire time, in milliseconds.
  , setUnixSeconds       :: Maybe Integer
  {- ^ Set the specified Unix time at which the key will expire, in seconds.

  Since Redis 6.2
  -}
  , setUnixMilliseconds  :: Maybe Integer
  {- ^ Set the specified Unix time at which the key will expire, in milliseconds.
  -}
  , setCondition         :: Maybe Condition -- ^ Set the key on condition
  , setKeepTTL           :: Bool
  {- ^ Retain the time to live associated with the key.

  Since Redis 6.0
  -}
  } deriving (Show, Eq)

-- |Redis default 'SetOpts'. Equivalent to omitting all optional parameters.
defaultSetOpts :: SetOpts
defaultSetOpts = SetOpts
  { setSeconds = Nothing
  , setMilliseconds = Nothing
  , setUnixSeconds = Nothing
  , setUnixMilliseconds = Nothing
  , setCondition = Nothing
  , setKeepTTL = False
  }

internalSetOptsToArgs :: SetOpts -> [ByteString]
internalSetOptsToArgs SetOpts{..} = concat [ex, px, exat, pxat, keepttl, condition]
  where
    ex   = maybe [] (\s -> ["EX",   encode s]) setSeconds
    px   = maybe [] (\s -> ["PX",   encode s]) setMilliseconds
    exat = maybe [] (\s -> ["EXAT", encode s]) setUnixSeconds
    pxat = maybe [] (\s -> ["PXAT", encode s]) setUnixMilliseconds
    keepttl = ["KEEPTTL" | setKeepTTL]
    condition = map encode $ maybeToList setCondition

setOpts
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ value
    -> SetOpts
    -> m (f Status)
setOpts key value opts = sendRequest $ ["SET", key, value] ++ internalSetOptsToArgs opts

setGet
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ value
    -> m (f ByteString)
setGet key value = sendRequest ["SET", key, value, "GET"]

setGetOpts
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ value
    -> SetOpts
    -> m (f ByteString)
setGetOpts key value opts = sendRequest $ ["SET", key, value, "GET"] ++ internalSetOptsToArgs opts

-- |Atomically sets multiple string keys with an optional shared expiration in a single operation (<https://redis.io/commands/msetex>).
--
-- $O(N)$ where $N$ is the number of keys to set.
--
-- Since Redis 8.4.0
msetex
    :: (RedisCtx m f)
    => NonEmpty (ByteString, ByteString) -- ^ A series of key/value pairs.
    -> m (f Bool)
msetex keyValues = msetexOpts keyValues defaultSetOpts

-- |Atomically sets multiple string keys with an optional shared expiration in a single operation (<https://redis.io/commands/msetex>).
--
-- $O(N)$ where $N$ is the number of keys to set.
--
-- Since Redis 8.4.0
msetexOpts
    :: (RedisCtx m f)
    => NonEmpty (ByteString, ByteString) -- ^ A series of key/value pairs.
    -> SetOpts
    {- ^ Shared condition and expiration flags.

       The `MSETEX` command supports a set of options that modify its behavior:
       `NX` sets the keys and their expiration time only if none of the specified keys exist.
       `XX` sets the keys and their expiration time only if all of the specified keys already exist.
       `EX`/`PX`/`EXAT`/`PXAT` set the shared expiration for the specified keys.
       `KEEPTTL` retains the time to live associated with the keys.
     -}
    -> m (f Bool)
msetexOpts keyValues opts =
    sendRequest $
        ["MSETEX", encode (toInteger $ NE.length keyValues)]
            ++ concatMap (\(key, value) -> [key, value]) (NE.toList keyValues)
            ++ internalSetOptsToArgs opts

data GetExOpts = GetExOpts
  { getExSeconds :: Maybe Integer
  , getExMilliseconds :: Maybe Integer
  , getExUnixSeconds :: Maybe Integer
  , getExUnixMilliseconds :: Maybe Integer
  , getExPersist :: Bool
  } deriving (Show, Eq)

defaultGetExOpts :: GetExOpts
defaultGetExOpts = GetExOpts
  { getExSeconds = Nothing
  , getExMilliseconds = Nothing
  , getExUnixSeconds = Nothing
  , getExUnixMilliseconds = Nothing
  , getExPersist = False
  }

-- |Returns the string value of a key after deleting the key (<https://redis.io/commands/getdel>).
--
-- $O(1)$
--
-- Since Redis 6.2.0
getdel
    :: (RedisCtx m f)
    => ByteString
    -> m (f (Maybe ByteString))
getdel key = sendRequest ["GETDEL", key]

data DelexCondition
    = DelexIfEq ByteString
    | DelexIfNe ByteString
    | DelexIfDigestEq ByteString
    | DelexIfDigestNe ByteString
    deriving (Show, Eq)

delexConditionToArgs :: DelexCondition -> [ByteString]
delexConditionToArgs condition =
    case condition of
        DelexIfEq value -> ["IFEQ", value]
        DelexIfNe value -> ["IFNE", value]
        DelexIfDigestEq digestValue -> ["IFDEQ", digestValue]
        DelexIfDigestNe digestValue -> ["IFDNE", digestValue]

-- |Conditionally removes the specified key based on value or hash digest comparison (<https://redis.io/commands/delex>).
--
-- $O(1)$ for /IFEQ/ and /IFNE/. $O(N)$ for /IFDEQ/ and /IFDNE/, where $N$ is the length of the string value.
--
-- Since Redis 8.4.0
delex
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the string.
    -> m (f Bool)
delex key = sendRequest ["DELEX", key]

-- |Conditionally removes the specified key based on value or hash digest comparison (<https://redis.io/commands/delex>).
--
-- $O(1)$ for /IFEQ/ and /IFNE/. $O(N)$ for /IFDEQ/ and /IFDNE/, where $N$ is the length of the string value.
--
-- Since Redis 8.4.0
delexWhen
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the string.
    -> DelexCondition
    {- ^ Condition to enforce.

       The `DELEX` command supports a set of options that modify its behavior.
       Only one option can be specified:
       `IFEQ` removes the key if the value is equal to the specified value.
       `IFNE` removes the key if the value is not equal to the specified value.
       `IFDEQ` removes the key if its hash digest is equal to the specified hash digest.
       `IFDNE` removes the key if its hash digest is not equal to the specified hash digest.
     -}
    -> m (f Bool)
delexWhen key condition =
    sendRequest $ ["DELEX", key] ++ delexConditionToArgs condition

-- |Returns the hash digest of a string value (<https://redis.io/commands/digest>).
--
-- $O(N)$ where $N$ is the length of the string value.
--
-- Since Redis 8.4.0
digest
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the string.
    -> m (f (Maybe ByteString))
digest key = sendRequest ["DIGEST", key]

-- |Returns the string value of a key after setting its expiration time (<https://redis.io/commands/getex>).
--
-- $O(1)$
--
-- Since Redis 6.2.0
getex
    :: (RedisCtx m f)
    => ByteString
    -> m (f (Maybe ByteString))
getex key = getexOpts key defaultGetExOpts

-- |Returns the string value of a key after setting its expiration time (<https://redis.io/commands/getex>).
--
-- $O(1)$
--
-- Since Redis 6.2.0
getexOpts
    :: (RedisCtx m f)
    => ByteString
    -> GetExOpts
    -> m (f (Maybe ByteString))
getexOpts key GetExOpts{..} =
    sendRequest $ ["GETEX", key] ++ exArg ++ pxArg ++ exatArg ++ pxatArg ++ persistArg
  where
    exArg = maybe [] (\seconds -> ["EX", encode seconds]) getExSeconds
    pxArg = maybe [] (\milliseconds -> ["PX", encode milliseconds]) getExMilliseconds
    exatArg = maybe [] (\seconds -> ["EXAT", encode seconds]) getExUnixSeconds
    pxatArg = maybe [] (\milliseconds -> ["PXAT", encode milliseconds]) getExUnixMilliseconds
    persistArg = ["PERSIST" | getExPersist]

data HGetExOpts = HGetExOpts
  { hGetExSeconds :: Maybe Integer
  , hGetExMilliseconds :: Maybe Integer
  , hGetExUnixSeconds :: Maybe Integer
  , hGetExUnixMilliseconds :: Maybe Integer
  , hGetExPersist :: Bool
  } deriving (Show, Eq)

defaultHGetExOpts :: HGetExOpts
defaultHGetExOpts = HGetExOpts
  { hGetExSeconds = Nothing
  , hGetExMilliseconds = Nothing
  , hGetExUnixSeconds = Nothing
  , hGetExUnixMilliseconds = Nothing
  , hGetExPersist = False
  }

-- |Returns the values associated with the specified fields in a hash and optionally updates the key expiration (<https://redis.io/commands/hgetex>).
--
-- $O(N)$ where $N$ is the number of specified fields.
--
-- Since Redis 8.0.0
hgetex
    :: (RedisCtx m f)
    => ByteString
    -> NonEmpty ByteString
    -> m (f [Maybe ByteString])
hgetex key fields = hgetexOpts key fields defaultHGetExOpts

-- |Returns the values associated with the specified fields in a hash and optionally updates the key expiration (<https://redis.io/commands/hgetex>).
--
-- $O(N)$ where $N$ is the number of specified fields.
--
-- Since Redis 8.0.0
hgetexOpts
    :: (RedisCtx m f)
    => ByteString
    -> NonEmpty ByteString
    -> HGetExOpts
    -> m (f [Maybe ByteString])
hgetexOpts key fields HGetExOpts{..} =
    sendRequest $ ["HGETEX", key] ++ exArg ++ pxArg ++ exatArg ++ pxatArg ++ persistArg ++ hashFieldArgs fields
  where
    exArg = maybe [] (\seconds -> ["EX", encode seconds]) hGetExSeconds
    pxArg = maybe [] (\milliseconds -> ["PX", encode milliseconds]) hGetExMilliseconds
    exatArg = maybe [] (\seconds -> ["EXAT", encode seconds]) hGetExUnixSeconds
    pxatArg = maybe [] (\milliseconds -> ["PXAT", encode milliseconds]) hGetExUnixMilliseconds
    persistArg = ["PERSIST" | hGetExPersist]

-- |Returns the values associated with the specified fields in a hash and deletes those fields (<https://redis.io/commands/hgetdel>).
--
-- $O(N)$ where $N$ is the number of specified fields.
--
-- Since Redis 8.0.0
hgetdel
    :: (RedisCtx m f)
    => ByteString
    -> NonEmpty ByteString
    -> m (f [Maybe ByteString])
hgetdel key fields =
    sendRequest $ ["HGETDEL", key] ++ hashFieldArgs fields

data HSetExCondition = HSetExFnx | HSetExFxx deriving (Show, Eq)

instance RedisArg HSetExCondition where
    encode HSetExFnx = "FNX"
    encode HSetExFxx = "FXX"

data HSetExOpts = HSetExOpts
  { hSetExSeconds :: Maybe Integer
  , hSetExMilliseconds :: Maybe Integer
  , hSetExUnixSeconds :: Maybe Integer
  , hSetExUnixMilliseconds :: Maybe Integer
  , hSetExCondition :: Maybe HSetExCondition
  , hSetExKeepTTL :: Bool
  } deriving (Show, Eq)

defaultHSetExOpts :: HSetExOpts
defaultHSetExOpts = HSetExOpts
  { hSetExSeconds = Nothing
  , hSetExMilliseconds = Nothing
  , hSetExUnixSeconds = Nothing
  , hSetExUnixMilliseconds = Nothing
  , hSetExCondition = Nothing
  , hSetExKeepTTL = False
  }

-- |Sets fields in a hash and optionally updates the key expiration (<https://redis.io/commands/hsetex>).
--
-- $O(N)$ where $N$ is the number of fields set.
--
-- Since Redis 8.0.0
hsetex
    :: (RedisCtx m f)
    => ByteString
    -> NonEmpty (ByteString, ByteString)
    -> m (f Bool)
hsetex key fieldValues = hsetexOpts key fieldValues defaultHSetExOpts

-- |Sets fields in a hash and optionally updates the key expiration (<https://redis.io/commands/hsetex>).
--
-- $O(N)$ where $N$ is the number of fields set.
--
-- Since Redis 8.0.0
hsetexOpts
    :: (RedisCtx m f)
    => ByteString
    -> NonEmpty (ByteString, ByteString)
    -> HSetExOpts
    -> m (f Bool)
hsetexOpts key fieldValues HSetExOpts{..} =
    sendRequest $ ["HSETEX", key] ++ conditionArg ++ exArg ++ pxArg ++ exatArg ++ pxatArg ++ keepTTLArg ++ ["FIELDS", encode (toInteger $ NE.length fieldValues)] ++ concatMap (\(field, value) -> [field, value]) (NE.toList fieldValues)
  where
    conditionArg = maybe [] (\condition -> [encode condition]) hSetExCondition
    exArg = maybe [] (\seconds -> ["EX", encode seconds]) hSetExSeconds
    pxArg = maybe [] (\milliseconds -> ["PX", encode milliseconds]) hSetExMilliseconds
    exatArg = maybe [] (\seconds -> ["EXAT", encode seconds]) hSetExUnixSeconds
    pxatArg = maybe [] (\milliseconds -> ["PXAT", encode milliseconds]) hSetExUnixMilliseconds
    keepTTLArg = ["KEEPTTL" | hSetExKeepTTL]

data HashFieldExpirationStatus
    = HashFieldExpirationNoSuchField
    | HashFieldExpirationConditionNotMet
    | HashFieldExpirationSet
    | HashFieldExpirationDeleted
    deriving (Show, Eq)

instance RedisResult HashFieldExpirationStatus where
    decode r = do
        value <- decode r :: Either Reply Integer
        case value of
            -2 -> Right HashFieldExpirationNoSuchField
            0 -> Right HashFieldExpirationConditionNotMet
            1 -> Right HashFieldExpirationSet
            2 -> Right HashFieldExpirationDeleted
            _ -> Left r

data HashFieldExpirationInfo
    = HashFieldExpirationInfoNoSuchField
    | HashFieldExpirationInfoNoExpiration
    | HashFieldExpirationInfo Integer
    deriving (Show, Eq)

instance RedisResult HashFieldExpirationInfo where
    decode r = do
        value <- decode r :: Either Reply Integer
        case value of
            -2 -> Right HashFieldExpirationInfoNoSuchField
            -1 -> Right HashFieldExpirationInfoNoExpiration
            n -> Right (HashFieldExpirationInfo n)

hashFieldExpirationOptsToArgs :: ExpireOpts -> [ByteString]
hashFieldExpirationOptsToArgs opts =
    [encode opts]

hashFieldArgs :: NonEmpty ByteString -> [ByteString]
hashFieldArgs fields =
    ["FIELDS", encode (toInteger $ NE.length fields)] ++ NE.toList fields

-- |Sets expiration for hash fields using relative time to expire in seconds (<https://redis.io/commands/hexpire>).
--
-- $O(N)$ where $N$ is the number of specified fields.
--
-- Set an expiration (TTL or time to live) on one or more fields of a given hash key. You must specify at least one field. Field(s) will automatically be deleted from the hash key when their TTLs expire.
--
-- Field expirations will only be cleared by commands that delete or overwrite the contents of the hash fields, including HDEL and HSET commands. This means that all the operations that conceptually alter the value stored at a hash key's field without replacing it with a new one will leave the TTL untouched.
--
-- You can clear the TTL using the 'hpersist' command, which turns the hash field back into a persistent field.
--
-- Note that calling 'hexpire'/'hpexpire' with a zero TTL or 'hexpireat'/'hpexpireat' with a time in the past will result in the hash field being deleted.
--
-- Since Redis 7.4.0
hexpire
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the hash.
    -> Integer -- ^ Seconds until expiration.
    -> NonEmpty ByteString -- ^ List of fields to set expiration for.
    -> m (f [HashFieldExpirationStatus])
hexpire key seconds fields =
    sendRequest $ ["HEXPIRE", key, encode seconds] ++ hashFieldArgs fields

-- |Sets expiration for hash fields using relative time to expire in seconds (<https://redis.io/commands/hexpire>).
--
-- $O(N)$ where $N$ is the number of specified fields.
--
-- Since Redis 7.4.0
hexpireOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the hash.
    -> Integer -- ^ Seconds until expiration.
    -> NonEmpty ByteString -- ^ List of fields to set expiration for.
    -> ExpireOpts -- ^ Expiration options.
    -> m (f [HashFieldExpirationStatus])
hexpireOpts key seconds fields opts =
    sendRequest $ ["HEXPIRE", key, encode seconds] ++ hashFieldExpirationOptsToArgs opts ++ hashFieldArgs fields

-- |Sets expiration for hash fields using relative time to expire in milliseconds (<https://redis.io/commands/hpexpire>).
--
-- $O(N)$ where $N$ is the number of specified fields.
--
-- Since Redis 7.4.0
hpexpire
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the hash.
    -> Integer -- ^ Milliseconds until expiration.
    -> NonEmpty ByteString -- ^ List of fields to set expiration for.
    -> m (f [HashFieldExpirationStatus])
hpexpire key milliseconds fields =
    sendRequest $ ["HPEXPIRE", key, encode milliseconds] ++ hashFieldArgs fields

-- |Sets expiration for hash fields using relative time to expire in milliseconds (<https://redis.io/commands/hpexpire>).
--
-- $O(N)$ where $N$ is the number of specified fields.
--
-- Since Redis 7.4.0
hpexpireOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the hash.
    -> Integer -- ^ Milliseconds until expiration.
    -> NonEmpty ByteString -- ^ List of fields to set expiration for.
    -> ExpireOpts -- ^ Expiration options.
    -> m (f [HashFieldExpirationStatus])
hpexpireOpts key milliseconds fields opts =
    sendRequest $ ["HPEXPIRE", key, encode milliseconds] ++ hashFieldExpirationOptsToArgs opts ++ hashFieldArgs fields

-- |Sets expiration for hash fields using an absolute Unix timestamp in seconds (<https://redis.io/commands/hexpireat>).
--
-- $O(N)$ where $N$ is the number of specified fields.
--
-- Since Redis 7.4.0
hexpireat
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the hash.
    -> Integer -- ^ Absolute Unix timestamp in seconds at which the hash fields will expire.
    -> NonEmpty ByteString -- ^ List of fields to set expiration for.
    -> m (f [HashFieldExpirationStatus])
hexpireat key unixTimeSeconds fields =
    sendRequest $ ["HEXPIREAT", key, encode unixTimeSeconds] ++ hashFieldArgs fields

-- |Sets expiration for hash fields using an absolute Unix timestamp in seconds (<https://redis.io/commands/hexpireat>).
--
-- $O(N)$ where $N$ is the number of specified fields.
--
-- Since Redis 7.4.0
hexpireatOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the hash.
    -> Integer -- ^ Absolute Unix timestamp in seconds at which the hash fields will expire.
    -> NonEmpty ByteString -- ^ List of fields to set expiration for.
    -> ExpireOpts -- ^ Expiration options.
    -> m (f [HashFieldExpirationStatus])
hexpireatOpts key unixTimeSeconds fields opts =
    sendRequest $ ["HEXPIREAT", key, encode unixTimeSeconds] ++ hashFieldExpirationOptsToArgs opts ++ hashFieldArgs fields

-- |Sets expiration for hash fields using an absolute Unix timestamp in milliseconds (<https://redis.io/commands/hpexpireat>).
--
-- $O(N)$ where $N$ is the number of specified fields.
--
-- Since Redis 7.4.0
hpexpireat
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the hash.
    -> Integer -- ^ Absolute Unix timestamp in milliseconds at which the hash fields will expire.
    -> NonEmpty ByteString -- ^ List of fields to set expiration for.
    -> m (f [HashFieldExpirationStatus])
hpexpireat key unixTimeMilliseconds fields =
    sendRequest $ ["HPEXPIREAT", key, encode unixTimeMilliseconds] ++ hashFieldArgs fields

-- |Sets expiration for hash fields using an absolute Unix timestamp in milliseconds (<https://redis.io/commands/hpexpireat>).
--
-- $O(N)$ where $N$ is the number of specified fields.
--
-- Since Redis 7.4.0
hpexpireatOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the hash.
    -> Integer -- ^ Absolute Unix timestamp in milliseconds at which the hash fields will expire.
    -> NonEmpty ByteString -- ^ List of fields to set expiration for.
    -> ExpireOpts -- ^ Expiration options.
    -> m (f [HashFieldExpirationStatus])
hpexpireatOpts key unixTimeMilliseconds fields opts =
    sendRequest $ ["HPEXPIREAT", key, encode unixTimeMilliseconds] ++ hashFieldExpirationOptsToArgs opts ++ hashFieldArgs fields

-- |Returns the TTL in seconds of hash fields (<https://redis.io/commands/httl>).
--
-- $O(N)$ where $N$ is the number of specified fields.
--
-- Since Redis 7.4.0
httl
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the hash.
    -> NonEmpty ByteString -- ^ List of fields to get TTL for.
    -> m (f [HashFieldExpirationInfo])
httl key fields =
    sendRequest $ ["HTTL", key] ++ hashFieldArgs fields

-- |Returns the TTL in milliseconds of hash fields (<https://redis.io/commands/hpttl>).
--
-- $O(N)$ where $N$ is the number of specified fields.
--
-- Since Redis 7.4.0
hpttl
    :: (RedisCtx m f)
    => ByteString
    -> NonEmpty ByteString
    -> m (f [HashFieldExpirationInfo])
hpttl key fields =
    sendRequest $ ["HPTTL", key] ++ hashFieldArgs fields

-- |Returns the expiration time of hash fields as a Unix timestamp in seconds (<https://redis.io/commands/hexpiretime>).
--
-- $O(N)$ where $N$ is the number of specified fields.
--
-- Since Redis 7.4.0
hexpiretime
    :: (RedisCtx m f)
    => ByteString
    -> NonEmpty ByteString
    -> m (f [HashFieldExpirationInfo])
hexpiretime key fields =
    sendRequest $ ["HEXPIRETIME", key] ++ hashFieldArgs fields

-- |Returns the expiration time of hash fields as a Unix timestamp in milliseconds (<https://redis.io/commands/hpexpiretime>).
--
-- $O(N)$ where $N$ is the number of specified fields.
--
-- Since Redis 7.4.0
hpexpiretime
    :: (RedisCtx m f)
    => ByteString
    -> NonEmpty ByteString
    -> m (f [HashFieldExpirationInfo])
hpexpiretime key fields =
    sendRequest $ ["HPEXPIRETIME", key] ++ hashFieldArgs fields


data DebugMode = Yes | Sync | No deriving (Show, Eq)


instance RedisArg DebugMode where
  encode Yes = "YES"
  encode Sync = "SYNC"
  encode No = "NO"

-- |Set the debug mode for executed scripts (<http://redis.io/commands/script-debug>). Since Redis 3.2.0
scriptDebug
    :: (RedisCtx m f)
    => DebugMode
    -> m (f Bool)
scriptDebug mode =
    sendRequest ["SCRIPT DEBUG", encode mode]

-- |Add one or more members to a sorted set, or update its score if it already exists (<http://redis.io/commands/zadd>). The Redis command @ZADD@ is split up into 'zadd', 'zaddOpts'. Since Redis 1.2.0
zadd
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> [(Double,ByteString)] -- ^ scoreMember
    -> m (f Integer)
zadd key scoreMembers =
  zaddOpts key scoreMembers defaultZaddOpts


data SizeCondition =
    CGT | -- ^  Only update existing elements if the new score is greater than the current score. This flag doesn't prevent adding new elements.
    CLT   -- ^  Only update existing elements if the new score is less than the current score. This flag doesn't prevent adding new elements.
    deriving (Show, Eq)

instance RedisArg SizeCondition where
  encode CGT = "GT"
  encode CLT = "LT"

-- |Add one or more members to a sorted set, or update its score if it already exists (<http://redis.io/commands/zadd>). The Redis command @ZADD@ is split up into 'zadd', 'zaddOpts'. Since Redis 1.2.0
data ZaddOpts = ZaddOpts
  { zaddCondition :: Maybe Condition -- ^ Add on condition
  , zaddSizeCondition :: Maybe SizeCondition
  {- ^ Only update existing elements on condition

  Since Redis 6.2
  -}
  , zaddChange    :: Bool -- ^ Modify the return value from the number of new elements added, to the total number of elements changed
  , zaddIncrement :: Bool -- ^ When this option is specified ZADD acts like ZINCRBY. Only one score-element pair can be specified in this mode.
  } deriving (Show, Eq)


-- |Redis default 'ZaddOpts'. Equivalent to omitting all optional parameters.
--
-- @
-- ZaddOpts
--     { zaddCondition = Nothing -- omit NX and XX options
--     , zaddChange    = False   -- don't modify the return value from the number of new elements added, to the total number of elements changed
--     , zaddIncrement = False   -- don't add like ZINCRBY
--     }
-- @
--
defaultZaddOpts :: ZaddOpts
defaultZaddOpts = ZaddOpts
  { zaddCondition = Nothing
  , zaddChange    = False
  , zaddIncrement = False
  , zaddSizeCondition = Nothing
  }


zaddOpts
    :: (RedisCtx m f)
    => ByteString            -- ^ key
    -> [(Double,ByteString)] -- ^ scoreMember
    -> ZaddOpts              -- ^ options
    -> m (f Integer)
zaddOpts key scoreMembers ZaddOpts{..} =
    sendRequest $ concat [["ZADD", key], condition, sizeCondition, change, increment, scores]
  where
    scores = concatMap (\(x,y) -> [encode x,encode y]) scoreMembers
    condition = map encode $ maybeToList zaddCondition
    sizeCondition = map encode $ maybeToList zaddSizeCondition
    change = ["CH" | zaddChange]
    increment = ["INCR" | zaddIncrement]


data ReplyMode = On | Off | Skip deriving (Show, Eq)


instance RedisArg ReplyMode where
  encode On = "ON"
  encode Off = "OFF"
  encode Skip = "SKIP"

-- |Instruct the server whether to reply to commands (<http://redis.io/commands/client-reply>). Since Redis 3.2
clientReply
    :: (RedisCtx m f)
    => ReplyMode
    -> m (f Bool)
clientReply mode =
    sendRequest ["CLIENT REPLY", encode mode]

-- |Resumes processing commands from paused clients (<https://redis.io/commands/client-unpause>).
--
-- $O(N)$ where $N$ is the number of paused clients.
--
-- Since Redis 6.2.0
clientUnpause
    :: (RedisCtx m f)
    => m (f Status)
clientUnpause = sendRequest ["CLIENT", "UNPAUSE"]

-- | The CLIENT NO-TOUCH command controls whether commands sent by the client will alter the LRU/LFU of the keys they access (<https://redis.io/commands/client-notouch>).
--
-- When turned on, the current client will not change LFU/LRU stats, unless it sends the TOUCH command.
--
-- When turned off, the client touches LFU/LRU stats just as a normal client.
--
-- $O(1)$
--
-- Since Redis 7.2.0
clientNoTouch
    :: (RedisCtx m f)
    => Bool
    -> m (f Status)
clientNoTouch flag = sendRequest ["CLIENT NO-TOUCH", encodedFlag] where
    encodedFlag = if flag then "ON" else "OFF"

data ClientSetInfoOpts
    = ClientSetInfoLibName ByteString
    | ClientSetInfoLibVer ByteString
    deriving (Show, Eq)

-- | The CLIENT SETINFO command assigns various info attributes to the current connection which are displayed in the output of CLIENT LIST and CLIENT INFO (<https://redis.io/commands/client-setinfo>).
--
-- $O(1)$
--
-- Since Redis 7.2.0
clientSetinfo
  :: (RedisCtx m f)
  => ClientSetInfoOpts
  -> m (f Status)
clientSetinfo info_ = sendRequest $ "CLIENT": "SETINFO": clientSetInfoArg
  where
    clientSetInfoArg = case info_ of
      ClientSetInfoLibName s -> ["LIB-NAME", encode s]
      ClientSetInfoLibVer s -> ["LIB-VER", encode s]

-- |Get one or multiple random members from a set (<http://redis.io/commands/srandmember>). The Redis command @SRANDMEMBER@ is split up into 'srandmember', 'srandmemberN'. Since Redis 1.0.0
srandmember
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f (Maybe ByteString))
srandmember key = sendRequest ["SRANDMEMBER", key]


-- |Get one or multiple random members from a set (<http://redis.io/commands/srandmember>). The Redis command @SRANDMEMBER@ is split up into 'srandmember', 'srandmemberN'. Since Redis 1.0.0
srandmemberN
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ count
    -> m (f [ByteString])
srandmemberN key count = sendRequest ["SRANDMEMBER", key, encode count]

-- |Remove and return one or multiple random members from a set (<http://redis.io/commands/spop>). The Redis command @SPOP@ is split up into 'spop', 'spopN'. Since Redis 1.0.0
spop
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f (Maybe ByteString))
spop key = sendRequest ["SPOP", key]

-- |Remove and return one or multiple random members from a set (<http://redis.io/commands/spop>). The Redis command @SPOP@ is split up into 'spop', 'spopN'. Since Redis 1.0.0
spopN
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ count
    -> m (f [ByteString])
spopN key count = sendRequest ["SPOP", key, encode count]

-- |Determines whether multiple members belong to a set (<https://redis.io/commands/smismember>).
--
-- $O(N)$ where $N$ is the number of elements being checked for membership.
--
-- Since Redis 6.2.0
smismember
    :: (RedisCtx m f)
    => ByteString
    -> NonEmpty ByteString
    -> m (f [Bool])
smismember key (member:|members) = sendRequest ("SMISMEMBER" : key : member : members)

data SintercardOpts = SintercardOpts
    { sintercardLimit :: Maybe Integer
    } deriving (Show, Eq)

defaultSintercardOpts :: SintercardOpts
defaultSintercardOpts = SintercardOpts
    { sintercardLimit = Nothing
    }

-- |Returns the cardinality of the intersection of multiple sets (<https://redis.io/commands/sintercard>).
--
-- $O(N*M)$ worst case where $N$ is the cardinality of the smallest set and $M$ is the number of sets.
--
-- In clustered environment, commands must operate on keys within the same hash slot.
--
-- Since Redis 7.0.0
sintercard
    :: (RedisCtx m f)
    => NonEmpty ByteString
    -> m (f Integer)
sintercard keys = sintercardOpts keys defaultSintercardOpts

-- |Returns the cardinality of the intersection of multiple sets (<https://redis.io/commands/sintercard>).
--
-- $O(N*M)$ worst case where $N$ is the cardinality of the smallest set and $M$ is the number of sets.
--
-- In clustered environment, commands must operate on keys within the same hash slot.
--
-- Since Redis 7.0.0
sintercardOpts
    :: (RedisCtx m f)
    => NonEmpty ByteString
    -> SintercardOpts
    -> m (f Integer)
sintercardOpts keys SintercardOpts{..} =
    sendRequest $ ["SINTERCARD", encode (toInteger $ NE.length keys)] ++ NE.toList keys ++ limitArg
  where
    limitArg = maybe [] (\limit -> ["LIMIT", encode limit]) sintercardLimit

info
    :: (RedisCtx m f)
    => m (f ByteString)
info = sendRequest ["INFO"]


infoSection
    :: (RedisCtx m f)
    => ByteString -- ^ section
    -> m (f ByteString)
infoSection section = sendRequest ["INFO", section]

-- |Determine if a key exists (<http://redis.io/commands/exists>). Since Redis 1.0.0
exists
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f Bool)
exists key = sendRequest ["EXISTS", key]

newtype Cursor = Cursor ByteString deriving (Show, Eq)


instance RedisArg Cursor where
  encode (Cursor c) = encode c


instance RedisResult Cursor where
  decode (Bulk (Just s)) = Right $ Cursor s
  decode r               = Left r


cursor0 :: Cursor
cursor0 = Cursor "0"

-- |Incrementally iterate the keys space (<http://redis.io/commands/scan>). The Redis command @SCAN@ is split up into 'scan', 'scanOpts'. Since Redis 2.8.0
scan
    :: (RedisCtx m f)
    => Cursor
    -> m (f (Cursor, [ByteString])) -- ^ next cursor and values
scan cursor = scanOpts cursor defaultScanOpts Nothing


data ScanOpts = ScanOpts
  { scanMatch :: Maybe ByteString
  , scanCount :: Maybe Integer
  } deriving (Show, Eq)


-- |Redis default 'ScanOpts'. Equivalent to omitting all optional parameters.
--
-- @
-- ScanOpts
--     { scanMatch = Nothing -- don't match any pattern
--     , scanCount = Nothing -- don't set any requirements on number elements returned (works like value @COUNT 10@)
--     }
-- @
--
defaultScanOpts :: ScanOpts
defaultScanOpts = ScanOpts
  { scanMatch = Nothing
  , scanCount = Nothing
  }

-- | Incrementally iterate the keys space (<http://redis.io/commands/scan>). The Redis command @SCAN@ is split up into 'scan', 'scanOpts'. Since Redis 2.8.0
scanOpts
    :: (RedisCtx m f)
    => Cursor
    -> ScanOpts
    -> Maybe ByteString -- ^ types of the object to  scan
    -> m (f (Cursor, [ByteString])) -- ^ next cursor and values
scanOpts cursor opts mtype_  = sendRequest $ addScanOpts ["SCAN", encode cursor] opts
    ++ maybe [] (\type_  -> ["TYPE", type_]) mtype_


addScanOpts
    :: [ByteString] -- ^ main part of scan command
    -> ScanOpts
    -> [ByteString]
addScanOpts cmd ScanOpts{..} =
    concat [cmd, match, count]
  where
    prepend x y = [x, y]
    match       = maybe [] (prepend "MATCH") scanMatch
    count       = maybe [] ((prepend "COUNT").encode) scanCount

-- |Incrementally iterate Set elements (<http://redis.io/commands/sscan>). The Redis command @SSCAN@ is split up into 'sscan', 'sscanOpts'. Since Redis 2.8.0
sscan
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Cursor
    -> m (f (Cursor, [ByteString])) -- ^ next cursor and values
sscan key cursor = sscanOpts key cursor defaultScanOpts

-- |Incrementally iterate Set elements (<http://redis.io/commands/sscan>). The Redis command @SSCAN@ is split up into 'sscan', 'sscanOpts'. Since Redis 2.8.0
sscanOpts
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Cursor
    -> ScanOpts
    -> m (f (Cursor, [ByteString])) -- ^ next cursor and values
sscanOpts key cursor opts = sendRequest $ addScanOpts ["SSCAN", key, encode cursor] opts

-- |Incrementally iterate hash fields and associated values (<http://redis.io/commands/hscan>). The Redis command @HSCAN@ is split up into 'hscan', 'hscanOpts'. Since Redis 2.8.0
hscan
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Cursor
    -> m (f (Cursor, [(ByteString, ByteString)])) -- ^ next cursor and values
hscan key cursor = hscanOpts key cursor defaultScanOpts

-- |Incrementally iterate hash fields and associated values (<http://redis.io/commands/hscan>). The Redis command @HSCAN@ is split up into 'hscan', 'hscanOpts'. Since Redis 2.8.0
hscanOpts
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Cursor
    -> ScanOpts
    -> m (f (Cursor, [(ByteString, ByteString)])) -- ^ next cursor and values
hscanOpts key cursor opts = sendRequest $ addScanOpts ["HSCAN", key, encode cursor] opts

-- |Returns a random field from a hash (<https://redis.io/commands/hrandfield>).
--
-- $O(1)$
--
-- Since Redis 6.2.0
hrandfield
    :: (RedisCtx m f)
    => ByteString
    -> m (f (Maybe ByteString))
hrandfield key = sendRequest ["HRANDFIELD", key]

-- |Returns one or more random fields from a hash (<https://redis.io/commands/hrandfield>).
--
-- $O(N)$ where $N$ is the number of fields returned.
--
-- If the provided count argument is positive, return an array of distinct fields. The array's length is either count or the hash's number of fields (HLEN), whichever is lower.
--
-- If called with a negative count, the behavior changes and the command is allowed to return the same field multiple times. In this case, the number of returned fields is the absolute value of the specified count.
--
-- Since Redis 6.2.0
hrandfieldCount
    :: (RedisCtx m f)
    => ByteString
    -> Integer
    -> m (f [ByteString])
hrandfieldCount key count = sendRequest ["HRANDFIELD", key, encode count]

-- |Returns one or more random fields and their values from a hash (<https://redis.io/commands/hrandfield>).
--
-- $O(N)$ where $N$ is the number of fields returned.
--
-- If the provided count argument is positive, return an array of distinct fields. The array's length is either count or the hash's number of fields (HLEN), whichever is lower.
--
-- If called with a negative count, the behavior changes and the command is allowed to return the same field multiple times. In this case, the number of returned fields is the absolute value of the specified count.
--
-- Since Redis 6.2.0
hrandfieldCountWithValues
    :: (RedisCtx m f)
    => ByteString
    -> Integer
    -> m (f [(ByteString, ByteString)])
hrandfieldCountWithValues key count =
    sendRequest ["HRANDFIELD", key, encode count, "WITHVALUES"]


zscan
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Cursor
    -> m (f (Cursor, [(ByteString, Double)])) -- ^ next cursor and values
zscan key cursor = zscanOpts key cursor defaultScanOpts


zscanOpts
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Cursor
    -> ScanOpts
    -> m (f (Cursor, [(ByteString, Double)])) -- ^ next cursor and values
zscanOpts key cursor opts = sendRequest $ addScanOpts ["ZSCAN", key, encode cursor] opts

data RangeLex a = Incl a | Excl a | Minr | Maxr deriving (Show, Eq)

instance RedisArg a => RedisArg (RangeLex a) where
  encode (Incl bs) = "[" `append` encode bs
  encode (Excl bs) = "(" `append` encode bs
  encode Minr      = "-"
  encode Maxr      = "+"

-- |Return a range of members in a sorted set, by lexicographical range (<http://redis.io/commands/zrangebylex>). Since Redis 2.8.9
zrangebylex::(RedisCtx m f) =>
    ByteString             -- ^ key
    -> RangeLex ByteString -- ^ min
    -> RangeLex ByteString -- ^ max
    -> m (f [ByteString])
zrangebylex key min max =
    sendRequest ["ZRANGEBYLEX", encode key, encode min, encode max]

zrangebylexLimit
    ::(RedisCtx m f)
    => ByteString -- ^ key
    -> RangeLex ByteString -- ^ min
    -> RangeLex ByteString -- ^ max
    -> Integer             -- ^ offset
    -> Integer             -- ^ count
    -> m (f [ByteString])
zrangebylexLimit key min max offset count  =
    sendRequest ["ZRANGEBYLEX", encode key, encode min, encode max,
                 "LIMIT", encode offset, encode count]

data ZPopMinMax = ZPopMin | ZPopMax deriving (Show, Eq)

instance RedisArg ZPopMinMax where
    encode ZPopMin = "MIN"
    encode ZPopMax = "MAX"

data ZPopResponse = ZPopResponse
    { zPopResponseKey :: Maybe ByteString
    , zPopResponseValues :: [(ByteString, Double)]
    } deriving (Show, Eq)

instance RedisResult ZPopResponse where
    decode (MultiBulk (Just [Bulk (Just key), MultiBulk (Just values)])) =
        ZPopResponse (Just key) <$> mapM decode values
    decode r = Left r

-- |Removes and returns member-score pairs from the first non-empty sorted set from a list of keys (<https://redis.io/commands/zmpop>).
--
-- $O(K) + O(M\log(N))$ where $K$ is the number of provided keys, $N$ is the number of elements in the sorted set, and $M$ is the number of elements popped.
--
-- In clustered environment, commands must operate on keys within the same hash slot.
--
-- Since Redis 7.0.0
zmpop
    :: (RedisCtx m f)
    => NonEmpty ByteString
    -> ZPopMinMax
    -> m (f (Maybe ZPopResponse))
zmpop keys where_ = zmpopCount keys where_ 1

-- |Removes and returns member-score pairs from the first non-empty sorted set from a list of keys (<https://redis.io/commands/zmpop>).
--
-- $O(K) + O(M\log(N))$ where $K$ is the number of provided keys, $N$ is the number of elements in the sorted set, and $M$ is the number of elements popped.
--
-- In clustered environment, commands must operate on keys within the same hash slot.
--
-- Since Redis 7.0.0
zmpopCount
    :: (RedisCtx m f)
    => NonEmpty ByteString
    -> ZPopMinMax
    -> Integer
    -> m (f (Maybe ZPopResponse))
zmpopCount keys where_ count =
    sendRequest $ ["ZMPOP", encode (toInteger $ NE.length keys)] ++ NE.toList keys ++ [encode where_, "COUNT", encode count]

-- |Removes and returns member-score pairs from the first non-empty sorted set from a list of keys, or blocks until one is available (<https://redis.io/commands/bzmpop>).
--
-- $O(K) + O(M\log(N))$ where $K$ is the number of provided keys, $N$ is the number of elements in the sorted set, and $M$ is the number of elements popped.
--
-- In clustered environment, commands must operate on keys within the same hash slot.
--
-- Since Redis 7.0.0
bzmpop
    :: (RedisCtx m f)
    => Double
    -> NonEmpty ByteString
    -> ZPopMinMax
    -> m (f (Maybe ZPopResponse))
bzmpop timeout keys where_ = bzmpopCount timeout keys where_ 1

-- |Removes and returns member-score pairs from the first non-empty sorted set from a list of keys, or blocks until one is available (<https://redis.io/commands/bzmpop>).
--
-- $O(K) + O(M\log(N))$ where $K$ is the number of provided keys, $N$ is the number of elements in the sorted set, and $M$ is the number of elements popped.
--
-- In clustered environment, commands must operate on keys within the same hash slot.
--
-- Since Redis 7.0.0
bzmpopCount
    :: (RedisCtx m f)
    => Double
    -> NonEmpty ByteString
    -> ZPopMinMax
    -> Integer
    -> m (f (Maybe ZPopResponse))
bzmpopCount timeout keys where_ count =
    sendRequest $ ["BZMPOP", encode timeout, encode (toInteger $ NE.length keys)] ++ NE.toList keys ++ [encode where_, "COUNT", encode count]

-- |Returns the score of one or more members in a sorted set (<https://redis.io/commands/zmscore>).
--
-- $O(N)$ where $N$ is the number of members being requested.
--
-- Since Redis 6.2.0
zmscore
    :: (RedisCtx m f)
    => ByteString
    -> NonEmpty ByteString
    -> m (f [Maybe Double])
zmscore key (member:|members) = sendRequest ("ZMSCORE" : key : member : members)

-- |Returns a random member from a sorted set (<https://redis.io/commands/zrandmember>).
--
-- $O(1)$ without the optional count argument.
--
-- Since Redis 6.2.0
zrandmember
    :: (RedisCtx m f)
    => ByteString
    -> m (f (Maybe ByteString))
zrandmember key = sendRequest ["ZRANDMEMBER", key]

-- |Returns one or more random members from a sorted set (<https://redis.io/commands/zrandmember>).
--
-- $O(N)$ where $N$ is the number of members returned.
--
-- Since Redis 6.2.0
zrandmemberN
    :: (RedisCtx m f)
    => ByteString
    -> Integer
    -> m (f [ByteString])
zrandmemberN key count = sendRequest ["ZRANDMEMBER", key, encode count]

-- |Returns one or more random members and their scores from a sorted set (<https://redis.io/commands/zrandmember>).
--
-- $O(N)$ where $N$ is the number of members returned.
--
-- Since Redis 6.2.0
zrandmemberWithscores
    :: (RedisCtx m f)
    => ByteString
    -> Integer
    -> m (f [(ByteString, Double)])
zrandmemberWithscores key count =
    sendRequest ["ZRANDMEMBER", key, encode count, "WITHSCORES"]

data ZRangeStoreRange
    = ZRangeStoreByIndex Integer Integer
    | ZRangeStoreByScore Double Double
    | ZRangeStoreByLex (RangeLex ByteString) (RangeLex ByteString)
    deriving (Show, Eq)

data ZRangeStoreOpts = ZRangeStoreOpts
    { zRangeStoreRev :: Bool
    , zRangeStoreLimit :: Maybe (Integer, Integer)
    } deriving (Show, Eq)

defaultZRangeStoreOpts :: ZRangeStoreOpts
defaultZRangeStoreOpts = ZRangeStoreOpts
    { zRangeStoreRev = False
    , zRangeStoreLimit = Nothing
    }

-- |Stores a range of members from a sorted set in a destination key (<https://redis.io/commands/zrangestore>).
--
-- $O(\log(N) + M)$ with $N$ being the number of elements in the sorted set and $M$ the number of elements stored into the destination key.
--
-- Since Redis 6.2.0
zrangestore
    :: (RedisCtx m f)
    => ByteString
    -> ByteString
    -> Integer
    -> Integer
    -> m (f Integer)
zrangestore destination source start stop =
    zrangestoreOpts destination source (ZRangeStoreByIndex start stop) defaultZRangeStoreOpts

-- |Stores a range of members from a sorted set in a destination key (<https://redis.io/commands/zrangestore>).
--
-- $O(\log(N) + M)$ with $N$ being the number of elements in the sorted set and $M$ the number of elements stored into the destination key.
--
-- Since Redis 6.2.0
zrangestoreOpts
    :: (RedisCtx m f)
    => ByteString
    -> ByteString
    -> ZRangeStoreRange
    -> ZRangeStoreOpts
    -> m (f Integer)
zrangestoreOpts destination source range opts =
    sendRequest $ ["ZRANGESTORE", destination, source] ++ zRangeStoreRangeArgs range ++ zRangeStoreOptsArgs opts

zRangeStoreRangeArgs :: ZRangeStoreRange -> [ByteString]
zRangeStoreRangeArgs range = case range of
    ZRangeStoreByIndex start stop ->
        [encode start, encode stop]
    ZRangeStoreByScore minScore maxScore ->
        [encode minScore, encode maxScore, "BYSCORE"]
    ZRangeStoreByLex minMember maxMember ->
        [encode minMember, encode maxMember, "BYLEX"]

zRangeStoreOptsArgs :: ZRangeStoreOpts -> [ByteString]
zRangeStoreOptsArgs ZRangeStoreOpts{..} =
    revArg ++ limitArg
  where
    revArg = ["REV" | zRangeStoreRev]
    limitArg = maybe [] (\(offset, count) -> ["LIMIT", encode offset, encode count]) zRangeStoreLimit

-- | Trimming strategy.
--
-- @since 0.16.0
data TrimStrategy
  = TrimMaxlen Integer
    -- ^ Evicts entries as long as the stream's length exceeds the specified threshold, where threshold is a positive integer.
  | TrimMinId ByteString
   {- ^  Evicts entries with IDs lower than threshold, where threshold is a stream ID.

   Since Redis 6.2: will fail if used on ealier versions.
   -}

-- | Type of the trimming.
--
-- @since 0.16.0
data TrimType
  = TrimExact {- ^ Exact trimming -}
  | TrimApprox (Maybe Integer) {- ^ Approximate trimming. Is faster, but may leave slightly more
    elements in the stream if they can't be immediately deleted.

    Additional parameter Specifies the maximal count of entries that will be evicted. When LIMIT and count aren't specified, the default value of 100 * the number of entries in a macro node will be implicitly used as the count, @Just 0@ removes the limit entirely.
    -}

data TrimOpts = TrimOpts
  { trimOptsStrategy :: TrimStrategy
  , trimOptsType :: TrimType
  }

-- | Converts trim options to the low level parameters
internalTrimArgToList :: TrimOpts -> [ByteString]
internalTrimArgToList TrimOpts{..} = trimArg ++ limitArg
  where trimArg = case trimOptsStrategy of
           TrimMaxlen max -> ("MAXLEN":approxArg:encode max:[])
           TrimMinId i -> ("MINID":approxArg:i:[])
        (approxArg, limitArg) = case trimOptsType of
            TrimExact -> ("=", [])
            TrimApprox limit -> ("~",  maybe [] (("LIMIT":) . (:[]) . encode) limit)

trimOpts :: TrimStrategy -> TrimType -> TrimOpts
trimOpts = TrimOpts

data XAddOpts = XAddOpts {
    xAddTrimOpts :: Maybe TrimOpts, -- ^ Call XTRIM right after XADD
    xAddnoMkStream :: Bool
    {- ^ Don't create a new stream if it doesn't exist

    @since Redis 6.2
    -}
}

defaultXAddOpts :: XAddOpts
defaultXAddOpts = XAddOpts {
    xAddTrimOpts = Nothing,
    xAddnoMkStream = False
}

-- |Add a value to a stream (<https://redis.io/commands/xadd>). The Redis command @XADD@ is split up into 'xadd', 'xaddOpts'. Since Redis 5.0.0
xaddOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> ByteString -- ^ Message ID
    -> [(ByteString, ByteString)] -- ^ Message data (field, value)
    -> XAddOpts -- ^ Additional parameteers
    -> m (f ByteString) -- ^ ID of the added entry.
xaddOpts key entryId fieldValues opts = sendRequest $
    ["XADD", key] ++ noMkStreamArgs ++ trimArgs ++ [entryId] ++ fieldArgs
    where
        fieldArgs = concatMap (\(x,y) -> [x,y]) fieldValues
        noMkStreamArgs = ["NOMKSTREAM" | xAddnoMkStream opts]
        trimArgs = maybe [] (internalTrimArgToList) (xAddTrimOpts opts)

-- | /O(1)/ Adds a value to a stream (<https://redis.io/commands/xadd>). Since Redis 5.0.0
xadd
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name
    -> ByteString -- ^ Message id
    -> [(ByteString, ByteString)] -- ^ Message data (field, value)
    -> m (f ByteString)
xadd key entryId fieldValues = xaddOpts key entryId fieldValues defaultXAddOpts

-- | Additional parameters.
newtype XAutoclaimOpts = XAutoclaimOpts {
    xAutoclaimCount :: Maybe Integer -- ^  The upper limit of the number of entries that the command attempts to claim (default: 100).
}

-- | Default 'XAutoclaimOpts' value.
--
-- Prefer to use this function over direct use of constructor to preserve
-- backwards compatibility.
--
-- Defaults to @[Count 100)@
defaultXAutoclaimOpts :: XAutoclaimOpts
defaultXAutoclaimOpts = XAutoclaimOpts {
    xAutoclaimCount = Nothing
}

-- | Result of the 'xautoclaim' family of calls
data XAutoclaimResult resultFormat = XAutoclaimResult {
    xAutoclaimResultId :: ByteString,
    -- ^ ID of message that should be used in the next 'xautoclaim' call as a start parameter.
    xAutoclaimClaimedMessages :: [resultFormat],
    -- ^ List of succesfully claimed messages.
    xAutoclaimDeletedMessages :: [ByteString]
    -- ^ List of the messages that are available in the PEL but already deleted from the stream.
} deriving (Show, Eq)

instance RedisResult a => RedisResult (XAutoclaimResult a) where
    decode (MultiBulk (Just [
        Bulk (Just xAutoclaimResultId) ,
        claimedMsg,
        deletedMsg])) = do
            xAutoclaimClaimedMessages <- decode claimedMsg
            xAutoclaimDeletedMessages <- decode deletedMsg
            Right XAutoclaimResult{..}
    decode (MultiBulk (Just [
        Bulk (Just xAutoclaimResultId) ,
        MultiBulk (Just [])
        ])) = do
            let xAutoclaimClaimedMessages = []
            let xAutoclaimDeletedMessages = []
            Right XAutoclaimResult{..}
    decode a = Left a

-- | Version of the autoclaim result that contains data of the messages.
type XAutoclaimStreamsResult = XAutoclaimResult StreamsRecord
-- | Version of the autoclaim result that contains only IDs.
type XAutoclaimJustIdsResult = XAutoclaimResult ByteString

-- | /O(1)/ Transfers ownership of pending stream entries that match
-- the specified criteria. The message should be pending for more than \<min-idle-time\>
-- milliseconds and ID should be greater than \<start\>.
--
-- @XAUTOCLAIM \<stream name\> \<consumer group name\> \<min idle time\> \<start\>@
--
-- This version of function  claims no more than 100 mesages, use 'xautoclaimOpt' to
-- override this behavior.
--
-- Since Redis 7.0: fails on ealier versions.
xautoclaim
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> ByteString -- ^ Consumer group name.
    -> ByteString -- ^ Consumer name.
    -> Integer -- ^ Min idle time (ms).
    -> ByteString -- ^ ID of the message to start.
    -> m (f XAutoclaimStreamsResult)
xautoclaim key group consumer min_idle_time start = xautoclaimOpts key group consumer min_idle_time start defaultXAutoclaimOpts

-- | /O(1) if count is small/. Transfers ownership of pending stream entries that match
-- the specified criteria. See 'xautoclaim' for details.
--
-- Allows to pass additional optional parameters to set limit.
--
-- @XAUTOCLAIM \<stream name\> \<consumer group name\> \<min idle time\> \<start\> COUNT \<count\>@
--
-- Since Redis 7.0: fails on the ealier versions.
xautoclaimOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> ByteString -- ^ Consumer group name.
    -> ByteString -- ^ Consumer name.
    -> Integer -- ^ min idle time (ms).
    -> ByteString -- ^ start ID.
    -> XAutoclaimOpts -- ^ Additional parameters.
    -> m (f XAutoclaimStreamsResult)
xautoclaimOpts key group consumer min_idle_time start opts = sendRequest $
    ["XAUTOCLAIM", key, group, consumer, encode min_idle_time, start] ++ count
    where count  = maybe [] (("COUNT":) . (:[]) . encode) (xAutoclaimCount opts)

-- | /O(1)/ Transfers ownership of pending stream entries that match
-- the specified criteria. See 'xautoclaim' for more details about criteria.
--
-- This variant returns only id of the messages without data. This method
-- claims no more than 100 messages, see 'xautoclaimJustIdsOpts' for changing
-- this default.
--
-- @XAUTOCLAIM \<stream name\> \<consumer group name\> \<min idle time\> \<start\> JUSTID@
--
-- Since Redis 7.0: fails on the ealier versions.
xautoclaimJustIds
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> ByteString -- ^ Consumer group name.
    -> ByteString -- ^ Consumer name.
    -> Integer -- ^ Min idle time (ms).
    -> ByteString -- ^ start ID.
    -> m (f XAutoclaimJustIdsResult)
xautoclaimJustIds key group consumer min_idle_time start =
  xautoclaimJustIdsOpts key group consumer min_idle_time start defaultXAutoclaimOpts

-- | /O(1) if count is small/ Transfers ownership of pending stream entries that match
-- the specified criteria. See 'xautoclaim' for more details about criteria.
--
-- This variant returns only id of the messages without data and allows to set the maximum
-- number of messages to be claimed.
--
-- @XAUTOCLAIM \<stream name\> \<consumer group name\> \<min idle time\> \<start\> COUNT \<count\> JUSTID@
--
-- Since Redis 7.0: fails on the ealier versions.
xautoclaimJustIdsOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> ByteString -- ^ Consumers group name.
    -> ByteString -- ^ Consumer namee.
    -> Integer -- ^ min idle time (ms).
    -> ByteString -- ^ Start ID.
    -> XAutoclaimOpts -- ^ Additional parametres.
    -> m (f XAutoclaimJustIdsResult)
xautoclaimJustIdsOpts key group consumer min_idle_time start opts = sendRequest $
    ["XAUTOCLAIM", key, group, consumer, encode min_idle_time, start] ++ count ++ ["JUSTID"]
    where count  = maybe [] (("COUNT":) . (:[]) . encode) (xAutoclaimCount opts)

data StreamsRecord = StreamsRecord
    { recordId :: ByteString
    , keyValues :: [(ByteString, ByteString)]
    } deriving (Show, Eq)

instance RedisResult StreamsRecord where
    decode (MultiBulk (Just [Bulk (Just recordId), MultiBulk (Just rawKeyValues)])) = do
        keyValuesList <- mapM decode rawKeyValues
        let keyValues = decodeKeyValues keyValuesList
        return StreamsRecord{..}
        where
            decodeKeyValues :: [ByteString] -> [(ByteString, ByteString)]
            decodeKeyValues (x:y:rest) = (x,y):decodeKeyValues rest
            decodeKeyValues _ = []
    decode a = Left a

data XReadOpts = XReadOpts
    { block :: Maybe Integer
    , recordCount :: Maybe Integer
    } deriving (Show, Eq)

-- |Redis default 'XReadOpts'. Equivalent to omitting all optional parameters.
--
-- @
-- XReadOpts
--     { block = Nothing -- Don't block waiting for more records
--     , recordCount    = Nothing   -- no record count
--     }
-- @
--
defaultXreadOpts :: XReadOpts
defaultXreadOpts = XReadOpts { block = Nothing, recordCount = Nothing }

data XReadResponse = XReadResponse
    { stream :: ByteString
    , records :: [StreamsRecord]
    } deriving (Show, Eq)

instance RedisResult XReadResponse where
    decode (MultiBulk (Just [Bulk (Just stream), MultiBulk (Just rawRecords)])) = do
        records <- mapM decode rawRecords
        return XReadResponse{..}
    decode a = Left a

xreadOpts
    :: (RedisCtx m f)
    => [(ByteString, ByteString)] -- ^ (stream, id) pairs
    -> XReadOpts -- ^ Options
    -> m (f (Maybe [XReadResponse]))
xreadOpts streamsAndIds opts = sendRequest $
    ["XREAD"] ++ (internalXreadArgs streamsAndIds opts)

internalXreadArgs :: [(ByteString, ByteString)] -> XReadOpts -> [ByteString]
internalXreadArgs streamsAndIds XReadOpts{..} =
    concat [blockArgs, countArgs, ["STREAMS"], streams, recordIds]
    where
        blockArgs = maybe [] (\blockMillis -> ["BLOCK", encode blockMillis]) block
        countArgs = maybe [] (\countRecords -> ["COUNT", encode countRecords]) recordCount
        streams = map (\(stream, _) -> stream) streamsAndIds
        recordIds = map (\(_, recordId) -> recordId) streamsAndIds


xread
    :: (RedisCtx m f)
    => [(ByteString, ByteString)] -- ^ (stream, id) pairs
    -> m( f (Maybe [XReadResponse]))
xread streamsAndIds = xreadOpts streamsAndIds defaultXreadOpts

data XReadGroupOpts = XReadGroupOpts
    { xReadGroupBlock :: Maybe Integer
    , xReadGroupCount :: Maybe Integer
    , xReadGroupNoAck :: Bool
    } deriving (Show, Eq)

defaultXReadGroupOpts :: XReadGroupOpts
defaultXReadGroupOpts = XReadGroupOpts
    { xReadGroupBlock = Nothing
    , xReadGroupCount = Nothing
    , xReadGroupNoAck = False
    }

xreadGroupOpts
    :: (RedisCtx m f)
    => ByteString -- ^ group name
    -> ByteString -- ^ consumer name
    -> [(ByteString, ByteString)] -- ^ (stream, id) pairs
    -> XReadGroupOpts -- ^ Options
    -> m (f (Maybe [XReadResponse]))
xreadGroupOpts groupName consumerName streamsAndIds XReadGroupOpts{..} = sendRequest $
    ["XREADGROUP", "GROUP", groupName, consumerName] ++ internalXreadGroupArgs
    where
        internalXreadGroupArgs = concat [countArgs, blockArgs, noAckArgs, ["STREAMS"], streams, recordIds]
        blockArgs = maybe [] (\blockMillis -> ["BLOCK", encode blockMillis]) xReadGroupBlock
        countArgs = maybe [] (\countRecords -> ["COUNT", encode countRecords]) xReadGroupCount
        noAckArgs = ["NOACK" | xReadGroupNoAck]
        streams = map (\(stream, _) -> stream) streamsAndIds
        recordIds = map (\(_, recordId) -> recordId) streamsAndIds

xreadGroup
    :: (RedisCtx m f)
    => ByteString -- ^ group name
    -> ByteString -- ^ consumer name
    -> [(ByteString, ByteString)] -- ^ (stream, id) pairs
    -> m (f (Maybe [XReadResponse]))
xreadGroup groupName consumerName streamsAndIds = xreadGroupOpts groupName consumerName streamsAndIds defaultXReadGroupOpts

-- | Additional parameters of the XGroupCreate
data XGroupCreateOpts = XGroupCreateOpts
    { xGroupCreateMkStream :: Bool -- ^ If a stream does not exist, create it automatically with length of 0
    , xGroupCreateEntriesRead :: Maybe ByteString
    {- ^ Enable consumer group lag tracking, specify an arbitrary ID.
     An arbitrary ID is any ID that isn't the ID of the stream's first entry,
     last entry, or zero (@"0-0"@) ID. Use it to find out how many entries
     are between the arbitrary ID (excluding it) and the stream's last entry.

     Since Redis 7.0, fails if set on the ealier versions.
    -}
    } deriving (Show, Eq)

-- | Specifies default group opts.
--
-- Prefer using this method over use of constructor to preserve backwards compatibility.
defaultXGroupCreateOpts :: XGroupCreateOpts
defaultXGroupCreateOpts = XGroupCreateOpts{
    xGroupCreateEntriesRead = Nothing,
    xGroupCreateMkStream = False
}

-- | /O(1)/ Creates consumer group.
--
-- Fails if called on with the stream name that does not exist, use 'xgroupCreateOpts'
-- to override this behavior.
xgroupCreate
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> ByteString -- ^ Consumer group name.
    -> ByteString -- ^ ID of the message to start reading with.
    -> m (f Status)
xgroupCreate stream groupName startId = xgroupCreateOpts stream groupName startId defaultXGroupCreateOpts

-- | /O(1)/ Creates consumer group, accepts additional parameters.
xgroupCreateOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> ByteString -- ^ Consumer group name.
    -> ByteString -- ^ ID of the message to start reading with.
    -> XGroupCreateOpts -- ^ Additional parameters.
    -> m (f Status)
xgroupCreateOpts stream groupName startId opts = sendRequest $ ["XGROUP", "CREATE", stream, groupName, startId] ++ args
    where args = mkstream ++ entriesRead
          mkstream    = ["MKSTREAM" | xGroupCreateMkStream opts]
          entriesRead = maybe []  (("ENTRIESREAD":) . (:[])) (xGroupCreateEntriesRead opts)

-- | /O(1)/ Creates new consumer in the consumers group.
--
-- Since redis 6.2.0: fails on the ealier versions.
xgroupCreateConsumer
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> ByteString -- ^ Consumer group name.
    -> ByteString -- ^ Consumer name.
    -> m (f Bool) -- ^ Returns if the consumer was created or not.
xgroupCreateConsumer key group consumer = sendRequest ["XGROUP", "CREATECONSUMER", key, group, consumer]

-- | /O(1)/ Sets last delivered id for a consumer group.
xgroupSetId
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> ByteString -- ^ Consumr group name.
    -> ByteString -- ^ Message ID or @$@
    -> m (f Status)
xgroupSetId stream group messageId = xgroupSetIdOpts stream group messageId defaultXGroupSetIdOpts

-- | Additional parameters for the 'xgroupSetId' method
newtype XGroupSetIdOpts = XGroupSetIdOpts {
    xGroupSetIdEntriesRead :: Maybe ByteString
    {- ^ Enable consumer group lag tracking for an arbitrary ID. An arbitrary ID is any ID that isn't the ID of the stream's first entry, its last entry or the zero (@"0-0"@) ID

    @since Redis 7.0, fails if set to Just on ealier versions.
    -}
}

-- | Default value for the 'XGroupSetIdOpts'.
--
-- Prefer use this method over the raw constructor in order to preserve
-- backwards compatibility.
defaultXGroupSetIdOpts :: XGroupSetIdOpts
defaultXGroupSetIdOpts = XGroupSetIdOpts {xGroupSetIdEntriesRead = Nothing}

-- | /O(1)/ a variant of the 'xgroupSetId' that allowes to pass additional parameters.
xgroupSetIdOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> ByteString -- ^ Consumer group name.
    -> ByteString -- ^ Message id or @$S
    -> XGroupSetIdOpts -- ^ Additional parameters.
    -> m (f Status)
xgroupSetIdOpts stream group messageId opts = sendRequest $ ["XGROUP", "SETID", stream, group, messageId] ++ entriesRead
    where entriesRead = maybe [] (("ENTRIESREAD":) . (:[])) (xGroupSetIdEntriesRead opts)

-- | /O(1)/ Delete consumer.
xgroupDelConsumer
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> ByteString -- ^ Consumer group name.
    -> ByteString -- ^ Consumer name.
    -> m (f Integer) -- ^ The number of pending messages owned by the consumer.
xgroupDelConsumer stream group consumer = sendRequest ["XGROUP", "DELCONSUMER", stream, group, consumer]

-- | /O(1)/ destroys a group.
xgroupDestroy
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> ByteString -- ^ Consumer group name.
    -> m (f Bool)  -- ^ Tells if the group was destroyed or not.
xgroupDestroy stream group = sendRequest ["XGROUP", "DESTROY", stream, group]

data XRefPolicy
    = XRefPolicyKeepRef -- ^ Deletes the specified entries from the stream, but preserves existing references to these entries in all consumer groups
    | XRefPolicyDelRef -- ^ Deletes the specified entries from the stream and also removes all references to these entries from all consumer groups' pending entry lists, effectively cleaning up all traces of the messages. If an entry ID is not in the stream, but there are dangling references, XDELEX with DELREF would still remove all those references.
    | XRefPolicyAcked -- ^ Deletes the specified entries from the stream only if they have been acknowledged by all consumer groups.
    deriving (Show, Eq)

instance RedisArg XRefPolicy where
    encode XRefPolicyKeepRef = "KEEPREF"
    encode XRefPolicyDelRef = "DELREF"
    encode XRefPolicyAcked = "ACKED"

data XEntryDeletionOpts = XEntryDeletionOpts
    { xEntryDeletionRefPolicy :: XRefPolicy
    } deriving (Show, Eq)

defaultXEntryDeletionOpts :: XEntryDeletionOpts
defaultXEntryDeletionOpts = XEntryDeletionOpts
    { xEntryDeletionRefPolicy = XRefPolicyKeepRef
    }

data XCfgSetOpts = XCfgSetOpts
    { xCfgSetIdmpDuration :: Maybe Integer
      -- ^ The duration in seconds that each idempotent ID is retained.
    , xCfgSetIdmpMaxsize :: Maybe Integer
      -- ^ The maximum number of idempotent IDs tracked per producer.
    } deriving (Show, Eq)

-- |Redis default 'XCfgSetOpts'. Equivalent to omitting all optional parameters.
--
-- At least one field must be set before calling 'xcfgset'.
defaultXCfgSetOpts :: XCfgSetOpts
defaultXCfgSetOpts = XCfgSetOpts
    { xCfgSetIdmpDuration = Nothing
    , xCfgSetIdmpMaxsize = Nothing
    }

data XNackMode
    = XNackSilent
    | XNackFail
    | XNackFatal
    deriving (Show, Eq)

instance RedisArg XNackMode where
    encode XNackSilent = "SILENT"
    encode XNackFail = "FAIL"
    encode XNackFatal = "FATAL"

data XNackOpts = XNackOpts
    { xNackRetryCount :: Maybe Integer
    , xNackForce :: Bool
    } deriving (Show, Eq)

-- |Redis default 'XNackOpts'. Equivalent to omitting all optional parameters.
defaultXNackOpts :: XNackOpts
defaultXNackOpts = XNackOpts
    { xNackRetryCount = Nothing
    , xNackForce = False
    }

data XEntryDeletionResult
    = XEntryDeletionResultNotFound
    | XEntryDeletionResultDeleted
    | XEntryDeletionResultNotDeleted
    deriving (Show, Eq)

instance RedisResult XEntryDeletionResult where
    decode r = do
        result <- decode r :: Either Reply Integer
        case result of
            -1 -> Right XEntryDeletionResultNotFound
            1 -> Right XEntryDeletionResultDeleted
            2 -> Right XEntryDeletionResultNotDeleted
            _ -> Left r

xEntryDeletionOptsToArgs :: XEntryDeletionOpts -> [ByteString]
xEntryDeletionOptsToArgs XEntryDeletionOpts{..} =
    [encode xEntryDeletionRefPolicy]

xEntryIdsBlockArgs :: NonEmpty ByteString -> [ByteString]
xEntryIdsBlockArgs messageIds =
    ["IDS", encode (toInteger $ NE.length messageIds)] ++ NE.toList messageIds

xack
    :: (RedisCtx m f)
    => ByteString -- ^ stream
    -> ByteString -- ^ group name
    -> [ByteString] -- ^ message IDs
    -> m (f Integer)
xack stream groupName messageIds = sendRequest $ ["XACK", stream, groupName] ++ messageIds

-- |Acknowledges and conditionally deletes entries for a consumer group (<https://redis.io/commands/xackdel>).
--
-- $O(1)$ for each entry ID processed.
--
-- Since Redis 8.2.0
xackdel
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> ByteString -- ^ Consumer group name.
    -> NonEmpty ByteString -- ^ Entry IDs.
    -> m (f [XEntryDeletionResult])
xackdel stream groupName messageIds =
    xackdelOpts stream groupName messageIds defaultXEntryDeletionOpts

-- |Acknowledges and conditionally deletes entries for a consumer group (<https://redis.io/commands/xackdel>).
--
-- $O(1)$ for each entry ID processed.
--
-- Since Redis 8.2.0
xackdelOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> ByteString -- ^ Consumer group name.
    -> NonEmpty ByteString -- ^ Entry IDs.
    -> XEntryDeletionOpts -- ^ Additional options.
    -> m (f [XEntryDeletionResult])
xackdelOpts stream groupName messageIds opts =
    sendRequest $ ["XACKDEL", stream, groupName]
        ++ xEntryDeletionOptsToArgs opts
        ++ xEntryIdsBlockArgs messageIds

xrange
    :: (RedisCtx m f)
    => ByteString -- ^ stream
    -> ByteString -- ^ start
    -> ByteString -- ^ end
    -> Maybe Integer -- ^ COUNT
    -> m (f [StreamsRecord])
xrange stream start end count = sendRequest $ ["XRANGE", stream, start, end] ++ countArgs
    where countArgs = maybe [] (\c -> ["COUNT", encode c]) count

xrevRange
    :: (RedisCtx m f)
    => ByteString -- ^ stream
    -> ByteString -- ^ end
    -> ByteString -- ^ start
    -> Maybe Integer -- ^ COUNT
    -> m (f [StreamsRecord])
xrevRange stream end start count = sendRequest $ ["XREVRANGE", stream, end, start] ++ countArgs
    where countArgs = maybe [] (\c -> ["COUNT", encode c]) count

xlen
    :: (RedisCtx m f)
    => ByteString -- ^ stream
    -> m (f Integer)
xlen stream = sendRequest ["XLEN", stream]

data XPendingSummaryResponse = XPendingSummaryResponse
    { numPendingMessages :: Integer
    , smallestPendingMessageId :: ByteString
    , largestPendingMessageId :: ByteString
    , numPendingMessagesByconsumer :: [(ByteString, Integer)]
    } deriving (Show, Eq)

instance RedisResult XPendingSummaryResponse where
    decode (MultiBulk (Just [
        Integer numPendingMessages,
        Bulk (Just smallestPendingMessageId),
        Bulk (Just largestPendingMessageId),
        MultiBulk (Just [MultiBulk (Just rawGroupsAndCounts)])])) = do
            let groupsAndCounts = chunksOfTwo rawGroupsAndCounts
            numPendingMessagesByconsumer <- decodeGroupsAndCounts groupsAndCounts
            return XPendingSummaryResponse{..}
            where
                decodeGroupsAndCounts :: [(Reply, Reply)] -> Either Reply [(ByteString, Integer)]
                decodeGroupsAndCounts bs = sequence $ map decodeGroupCount bs
                decodeGroupCount :: (Reply, Reply) -> Either Reply (ByteString, Integer)
                decodeGroupCount (x, y) = do
                    decodedX <- decode x
                    decodedY <- decode y
                    return (decodedX, decodedY)
                chunksOfTwo (x:y:rest) = (x,y):chunksOfTwo rest
                chunksOfTwo _ = []
    decode a = Left a

-- | /O(N)/ N - number of message beign returned.
--
-- Get information about pending messages (https://redis.io/commands/xpending).
--
-- Since Redis 5.0.
xpendingSummary
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> ByteString -- ^ Stream consumer group.
    -> m (f XPendingSummaryResponse)
xpendingSummary stream group = sendRequest $ ["XPENDING", stream, group]

-- | Details about message returned by the 'xpendingDetails'
data XPendingDetailRecord = XPendingDetailRecord
    { messageId :: ByteString
    , consumer :: ByteString
    , millisSinceLastDelivered :: Integer
    , numTimesDelivered :: Integer
    } deriving (Show, Eq)

instance RedisResult XPendingDetailRecord where
    decode (MultiBulk (Just [
        Bulk (Just messageId) ,
        Bulk (Just consumer),
        Integer millisSinceLastDelivered,
        Integer numTimesDelivered])) = Right XPendingDetailRecord{..}
    decode a = Left a

-- | Additional parameters of the xpending call family
data XPendingDetailOpts = XPendingDetailOpts
  {
    xPendingDetailConsumer :: Maybe ByteString, -- ^ Fetch the messages having a specific owner.
    xPendingDetailIdle :: Maybe Integer
    {- ^  Filter pending stream entries by their idle-time, ms

    Since Redis 6.2: Just values will fail
    -}
  }

-- | Default 'XPendingOpts' values.
--
-- Prefer this method over use of the constructor in order to preserve
-- backwards compatibility.
defaultXPendingDetailOpts :: XPendingDetailOpts
defaultXPendingDetailOpts = XPendingDetailOpts {
    xPendingDetailConsumer = Nothing,
    xPendingDetailIdle     = Nothing
}

-- | /O(N)/ N - number of messages returned.
--
-- Get detailed information about pending messages (https://redis.io/commands/xpending).
xpendingDetail
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> ByteString -- ^ Consumer group name.
    -> ByteString -- ^ ID of the first interesting message.
    -> ByteString -- ^ ID of the last intersting message.
    -> Integer -- ^ Limits the numbere of messages returned from the call.
    -> XPendingDetailOpts
    -> m (f [XPendingDetailRecord])
xpendingDetail stream group startId endId count opts = sendRequest $
    ["XPENDING", stream, group] ++ idleArg ++ [startId, endId, encode count] ++ consumerArg
    where consumerArg = maybeToList (xPendingDetailConsumer opts)
          idleArg = maybe [] (("IDLE":) . (:[]) . encode) (xPendingDetailIdle opts)

data XClaimOpts = XClaimOpts
    { xclaimIdle :: Maybe Integer
    , xclaimTime :: Maybe Integer
    , xclaimRetryCount :: Maybe Integer
    , xclaimForce :: Bool
    } deriving (Show, Eq)

defaultXClaimOpts :: XClaimOpts
defaultXClaimOpts = XClaimOpts
    { xclaimIdle = Nothing
    , xclaimTime = Nothing
    , xclaimRetryCount = Nothing
    , xclaimForce = False
    }


-- |Format a request for XCLAIM.
xclaimRequest
    :: ByteString -- ^ stream
    -> ByteString -- ^ group
    -> ByteString -- ^ consumer
    -> Integer -- ^ min idle time
    -> XClaimOpts -- ^ optional arguments
    -> [ByteString] -- ^ message IDs
    -> [ByteString]
xclaimRequest stream group consumer minIdleTime XClaimOpts{..} messageIds =
    ["XCLAIM", stream, group, consumer, encode minIdleTime] ++ ( map encode messageIds ) ++ optArgs
    where optArgs = idleArg ++ timeArg ++ retryCountArg ++ forceArg
          idleArg = optArg "IDLE" xclaimIdle
          timeArg = optArg "TIME" xclaimTime
          retryCountArg = optArg "RETRYCOUNT" xclaimRetryCount
          forceArg = if xclaimForce then ["FORCE"] else []
          optArg name maybeArg = maybe [] (\x -> [name, encode x]) maybeArg

xclaim
    :: (RedisCtx m f)
    => ByteString -- ^ stream
    -> ByteString -- ^ group
    -> ByteString -- ^ consumer
    -> Integer -- ^ min idle time
    -> XClaimOpts -- ^ optional arguments
    -> [ByteString] -- ^ message IDs
    -> m (f [StreamsRecord])
xclaim stream group consumer minIdleTime opts messageIds = sendRequest $
    xclaimRequest stream group consumer minIdleTime opts messageIds

xclaimJustIds
    :: (RedisCtx m f)
    => ByteString -- ^ stream
    -> ByteString -- ^ group
    -> ByteString -- ^ consumer
    -> Integer -- ^ min idle time
    -> XClaimOpts -- ^ optional arguments
    -> [ByteString] -- ^ message IDs
    -> m (f [ByteString])
xclaimJustIds stream group consumer minIdleTime opts messageIds = sendRequest $
    (xclaimRequest stream group consumer minIdleTime opts messageIds) ++ ["JUSTID"]

data GeoUnit
    = GeoMeters
    | GeoKilometers
    | GeoFeet
    | GeoMiles
    deriving (Show, Eq)

instance RedisArg GeoUnit where
    encode GeoMeters = "m"
    encode GeoKilometers = "km"
    encode GeoFeet = "ft"
    encode GeoMiles = "mi"

data GeoOrder
    = GeoAsc
    | GeoDesc
    deriving (Show, Eq)

instance RedisArg GeoOrder where
    encode GeoAsc = "ASC"
    encode GeoDesc = "DESC"

data GeoCoordinates = GeoCoordinates
    { geoLongitude :: Double
    , geoLatitude :: Double
    } deriving (Show, Eq)

instance RedisResult GeoCoordinates where
    decode (MultiBulk (Just [lon, lat])) =
        GeoCoordinates <$> decode lon <*> decode lat
    decode r = Left r

data GeoLocation = GeoLocation
    { geoLocationMember :: ByteString
    , geoLocationDist :: Maybe Double
    , geoLocationHash :: Maybe Integer
    , geoLocationCoordinates :: Maybe GeoCoordinates
    } deriving (Show, Eq)

instance RedisResult GeoLocation where
    decode r@(Bulk (Just _)) =
        GeoLocation <$> decode r <*> pure Nothing <*> pure Nothing <*> pure Nothing
    decode r@(SingleLine _) =
        GeoLocation <$> decode r <*> pure Nothing <*> pure Nothing <*> pure Nothing
    decode (MultiBulk (Just (memberReply:details))) = do
        geoLocationMember <- decode memberReply
        (geoLocationDist, geoLocationHash, geoLocationCoordinates) <- decodeGeoLocationDetails details
        pure GeoLocation {..}
      where
        decodeGeoLocationDetails :: [Reply] -> Either Reply (Maybe Double, Maybe Integer, Maybe GeoCoordinates)
        decodeGeoLocationDetails = go Nothing Nothing Nothing

        go md mh mc [] = Right (md, mh, mc)
        go md mh mc (x:xs) = case x of
            MultiBulk _ -> do
                coord <- decode x
                go md mh (Just coord) xs
            Integer _ -> do
                hashValue <- decode x
                go md (Just hashValue) mc xs
            _ -> do
                dist <- decode x
                go (Just dist) mh mc xs
    decode r = Left r

data GeoSearchFrom
    = GeoSearchFromMember ByteString
    | GeoSearchFromLonLat Double Double
    deriving (Show, Eq)

data GeoSearchBy
    = GeoSearchByRadius Double GeoUnit
    | GeoSearchByBox Double Double GeoUnit
    deriving (Show, Eq)

data GeoSearchOpts = GeoSearchOpts
    { geoSearchWithCoord :: Bool
    , geoSearchWithDist :: Bool
    , geoSearchWithHash :: Bool
    , geoSearchCount :: Maybe Integer
    , geoSearchCountAny :: Bool
    , geoSearchOrder :: Maybe GeoOrder
    } deriving (Show, Eq)

defaultGeoSearchOpts :: GeoSearchOpts
defaultGeoSearchOpts = GeoSearchOpts
    { geoSearchWithCoord = False
    , geoSearchWithDist = False
    , geoSearchWithHash = False
    , geoSearchCount = Nothing
    , geoSearchCountAny = False
    , geoSearchOrder = Nothing
    }

data GeoSearchStoreOpts = GeoSearchStoreOpts
    { geoSearchStoreCount :: Maybe Integer
    , geoSearchStoreCountAny :: Bool
    , geoSearchStoreOrder :: Maybe GeoOrder
    , geoSearchStoreStoredist :: Bool
    } deriving (Show, Eq)

defaultGeoSearchStoreOpts :: GeoSearchStoreOpts
defaultGeoSearchStoreOpts = GeoSearchStoreOpts
    { geoSearchStoreCount = Nothing
    , geoSearchStoreCountAny = False
    , geoSearchStoreOrder = Nothing
    , geoSearchStoreStoredist = False
    }

-- |Adds one or more members to a geospatial index (<https://redis.io/commands/geoadd>). The Redis command @GEOADD@ is split up into 'geoadd' and 'geoAddOpts'. Since Redis 3.2.0
data GeoAddOpts = GeoAddOpts
    { geoAddCondition :: Maybe Condition
    , geoAddChange :: Bool
    {- ^ Modify the return value from the number of new elements added, to the number of elements changed.

    Since Redis 6.2.0
    -}
    } deriving (Show, Eq)

-- |Redis default 'GeoAddOpts'. Equivalent to omitting all optional parameters.
defaultGeoAddOpts :: GeoAddOpts
defaultGeoAddOpts = GeoAddOpts
    { geoAddCondition = Nothing
    , geoAddChange = False
    }

-- |Adds one or more members to a geospatial index (<https://redis.io/commands/geoadd>).
-- The Redis command @GEOADD@ is split up into 'geoadd' and 'geoAddOpts'.
--
-- Note: there is no @geodel@ command because you can use 'zrem' to remove elements.
-- The Geo index structure is just a sorted set.
--
-- Since Redis 3.2.0
--
-- Redis tags: write, geo, slow
geoadd
    :: (RedisCtx m f)
    => ByteString
    -> [(Double, Double, ByteString)]
    -> m (f Integer)
geoadd key values = geoaddOpts key values defaultGeoAddOpts

-- |Adds one or more members to a geospatial index (<https://redis.io/commands/geoadd>).
-- The Redis command @GEOADD@ is split up into 'geoadd' and 'geoAddOpts'.
--
-- Since Redis 6.2.0
geoaddOpts
    :: (RedisCtx m f)
    => ByteString
    -> [(Double, Double, ByteString)]
    -> GeoAddOpts
    -> m (f Integer)
geoaddOpts key values GeoAddOpts{..} =
    sendRequest $ ["GEOADD", key] ++ conditionArg ++ changeArg ++ concatMap encodeGeoValue values
  where
    conditionArg = foldMap (\condition -> [encode condition]) geoAddCondition
    changeArg = ["CH" | geoAddChange]
    encodeGeoValue (lon, lat, member) = [encode lon, encode lat, member]

-- |Returns the distance between two members of a geospatial index (<https://redis.io/commands/geodist>). Since Redis 3.2.0
--
-- Redis tags: read, geo, slow
geodist
    :: (RedisCtx m f)
    => ByteString
    -> ByteString
    -> ByteString
    -> Maybe GeoUnit
    -> m (f (Maybe Double))
geodist key member1 member2 munit =
    sendRequest $ ["GEODIST", key, member1, member2] ++ maybeToList (encode <$> munit)

-- |Returns the longitude and latitude of members from a geospatial index (<https://redis.io/commands/geopos>). Since Redis 3.2.0
--
-- ACL categories: @read, @geo, @slow.
geopos
    :: (RedisCtx m f)
    => ByteString
    -> [ByteString]
    -> m (f [Maybe GeoCoordinates])
geopos key members = sendRequest $ ["GEOPOS", key] ++ members

-- |Queries a geospatial index for members inside an area of a box or a circle (<https://redis.io/commands/geosearch>). Since Redis 6.2.0
--
-- $O(N+\log(M))$ where N is the number of elements in the grid-aligned bounding box area around the shape provided as the filter and M is the number of items inside the shape
--
-- ACL: @read, @geo, @slow
--
-- Since: Redis 6.2.0
geoSearch
    :: (RedisCtx m f)
    => ByteString
    -> GeoSearchFrom
    -> GeoSearchBy
    -> GeoSearchOpts
    -> m (f [GeoLocation])
geoSearch key from by opts =
    sendRequest $ ["GEOSEARCH", key] ++ geoSearchFromArgs from ++ geoSearchByArgs by ++ geoSearchOptsArgs opts

-- |Queries a geospatial index for members inside an area of a box or a circle, optionally stores the result (<https://redis.io/commands/geosearchstore>). Since Redis 6.2.0
geoSearchStore
    :: (RedisCtx m f)
    => ByteString
    -> ByteString
    -> GeoSearchFrom
    -> GeoSearchBy
    -> GeoSearchStoreOpts
    -> m (f Integer)
geoSearchStore destination source from by opts =
    sendRequest $ ["GEOSEARCHSTORE", destination, source] ++ geoSearchFromArgs from ++ geoSearchByArgs by ++ geoSearchStoreOptsArgs opts

geoSearchFromArgs :: GeoSearchFrom -> [ByteString]
geoSearchFromArgs (GeoSearchFromMember member) = ["FROMMEMBER", member]
geoSearchFromArgs (GeoSearchFromLonLat lon lat) = ["FROMLONLAT", encode lon, encode lat]

geoSearchByArgs :: GeoSearchBy -> [ByteString]
geoSearchByArgs (GeoSearchByRadius radius unit) = ["BYRADIUS", encode radius, encode unit]
geoSearchByArgs (GeoSearchByBox width height unit) = ["BYBOX", encode width, encode height, encode unit]

geoSearchOptsArgs :: GeoSearchOpts -> [ByteString]
geoSearchOptsArgs GeoSearchOpts{..} =
    orderArg ++ countArg ++ withCoord ++ withDist ++ withHash
  where
    orderArg = maybe [] (\order -> [encode order]) geoSearchOrder
    countArg = maybe [] (\count -> ["COUNT", encode count] ++ ["ANY" | geoSearchCountAny]) geoSearchCount
    withCoord = ["WITHCOORD" | geoSearchWithCoord]
    withDist = ["WITHDIST" | geoSearchWithDist]
    withHash = ["WITHHASH" | geoSearchWithHash]

geoSearchStoreOptsArgs :: GeoSearchStoreOpts -> [ByteString]
geoSearchStoreOptsArgs GeoSearchStoreOpts{..} =
    orderArg ++ countArg ++ storeDistArg
  where
    orderArg = maybe [] (\order -> [encode order]) geoSearchStoreOrder
    countArg = maybe [] (\count -> ["COUNT", encode count] ++ ["ANY" | geoSearchStoreCountAny]) geoSearchStoreCount
    storeDistArg = ["STOREDIST" | geoSearchStoreStoredist]

-- | Data structure that is returned as a result of  'xinfoConsumers'
data XInfoConsumersResponse = XInfoConsumersResponse
    { xinfoConsumerName :: ByteString -- ^ The name of the consumer.
    , xinfoConsumerNumPendingMessages :: Integer -- ^ The number of entries in the PEL (pending elemeent list): pending messages for the consumer, which are messages that were delivered but are yet to be acknowledged
    , xinfoConsumerIdleTime :: Integer -- ^ The number of milliseconds that have passed since the consumer's last attempted interaction (Examples: 'xreadGroup', 'xclam', 'xautoclaim')
    , xinfoConsumerInactive :: Maybe Integer
    {- ^ The number of milliseconds that have passed since the consumer's last successful interaction (Examples: 'xreadGroup' that actually read some entries into the PEL, 'xclaim'/'xautoclaim' that actually claimed some entries)

    @since Redis 7.0: always @Nothing@ for previous versions.
    -}
    } deriving (Show, Eq)

instance RedisResult XInfoConsumersResponse where
    decode = decodeRedis6 <> decodeRedis7
      where decodeRedis6 (MultiBulk (Just [
                Bulk (Just "name"),
                Bulk (Just xinfoConsumerName),
                Bulk (Just "pending"),
                Integer xinfoConsumerNumPendingMessages,
                Bulk (Just "idle"),
                Integer xinfoConsumerIdleTime])) = Right XInfoConsumersResponse{xinfoConsumerInactive = Nothing, ..}
            decodeRedis6 a = Left a

            decodeRedis7 (MultiBulk (Just [
                Bulk (Just "name"),
                Bulk (Just xinfoConsumerName),
                Bulk (Just "pending"),
                Integer xinfoConsumerNumPendingMessages,
                Bulk (Just "idle"),
                Integer xinfoConsumerIdleTime,
                Bulk (Just "inactive"),
                Integer xinfoConsumerInactive])) = Right XInfoConsumersResponse{xinfoConsumerInactive = Just xinfoConsumerInactive, ..}
            decodeRedis7 a = Left a

-- | /O(1)/
-- Returns information about the list of the consumers beloging to the consumer group.
--
-- Available since Redis 5.0.0
--
-- Wrapper over @XINFO CONSUMERS \<stream name\> \<group name\>@
xinfoConsumers
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> ByteString -- ^ Group name.
    -> m (f [XInfoConsumersResponse])
xinfoConsumers stream group = sendRequest $ ["XINFO", "CONSUMERS", stream, group]

-- | Result of the 'xinfoGroups' call.
data XInfoGroupsResponse = XInfoGroupsResponse
    { xinfoGroupsGroupName :: ByteString -- ^ Name of the consumer group.
    , xinfoGroupsNumConsumers :: Integer -- ^ The number of consumers in the group.
    , xinfoGroupsNumPendingMessages :: Integer -- ^ The length of the group's pending entries list (PEL), which are messages that were delivered but are yet to be acknowledged.
    , xinfoGroupsLastDeliveredMessageId :: ByteString -- ^ The ID of the last entry delivered to the group's consumers.
    , xinfoGroupsEntriesRead :: Maybe Integer
    {- ^ The logical "read counter" of the last entry delivered to group's consumers.

    Since Redis 7.0: always @Nothing@ on the previous versions.
    -}
    , xinfoGroupsLag :: Maybe Integer
    {- ^ the number of entries in the stream that are still waiting to be delivered to the group's consumers, or a Nothing when that number can't be determined.

    Since Redis 7.0: always @Nothing@ on the previous versions.
    -}
    } deriving (Show, Eq)

instance RedisResult XInfoGroupsResponse where
    decode = decodeRedis6 <> decodeRedis7
      where decodeRedis6 (MultiBulk (Just [
              Bulk (Just "name"),      Bulk (Just xinfoGroupsGroupName),
              Bulk (Just "consumers"), Integer xinfoGroupsNumConsumers,
              Bulk (Just "pending"),   Integer xinfoGroupsNumPendingMessages,
              Bulk (Just "last-delivered-id"),
              Bulk (Just xinfoGroupsLastDeliveredMessageId)])) =
                Right XInfoGroupsResponse{
                      xinfoGroupsEntriesRead = Nothing
                    , xinfoGroupsLag         = Nothing
                    , ..}
            decodeRedis6 a = Left a

            decodeRedis7 (MultiBulk (Just [
              Bulk (Just "name"),              Bulk (Just xinfoGroupsGroupName),
              Bulk (Just "consumers"),         Integer xinfoGroupsNumConsumers,
              Bulk (Just "pending"),           Integer xinfoGroupsNumPendingMessages,
              Bulk (Just "last-delivered-id"), Bulk (Just xinfoGroupsLastDeliveredMessageId),
              Bulk (Just "entries-read"),      Integer xinfoGroupsEntriesRead,
              Bulk (Just "lag"),               Integer xinfoGroupsLag])) =
                Right XInfoGroupsResponse{
                      xinfoGroupsEntriesRead = Just xinfoGroupsEntriesRead
                    , xinfoGroupsLag         = Just xinfoGroupsLag
                    , ..}
            decodeRedis7 a = Left a

-- | /O(1)/ Returns information about the groups.
--
-- Available since: Redis 5.0.0
--
-- Wrapper around @XINFO GROUPS \<stream name\>@ call.
xinfoGroups
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> m (f [XInfoGroupsResponse])
xinfoGroups stream = sendRequest ["XINFO", "GROUPS", stream]

data XInfoStreamResponse
    = XInfoStreamResponse
    { xinfoStreamLength :: Integer -- ^ The number of entries in the stream.
    , xinfoStreamRadixTreeKeys :: Integer -- ^ The number of keys in the underlying radix data structure.
    , xinfoStreamRadixTreeNodes :: Integer -- ^ The number of nodes in the underlying radix data structure.
    , xinfoMaxDeletedEntryId :: Maybe ByteString
    {- ^ The maximal entry ID that was deleted from the stream

    Since Redis 7.0: always returns @Nothing@ on the previous versions.
    -}
    , xinfoEntriesAdded :: Maybe Integer
    {- ^ The count of all entries added to the stream during its lifetime

    Since Redis 7.0: always returns @Nothing@ on the previous versions.
    -}
    , xinfoRecordedFirstEntryId :: Maybe ByteString
    {- ^ ID of first recorded entry.

    Since Redis 7.0: always returns @Nothing@ on the previous versions.
    -}
    , xinfoStreamNumGroups :: Integer -- ^ The number of consumer groups defined for the stream.
    , xinfoStreamLastEntryId :: ByteString -- ^ ID of the last entry in the stream.
    , xinfoStreamFirstEntry :: StreamsRecord -- ^ ID and field-value tuples of the first entry in the stream.
    , xinfoStreamLastEntry :: StreamsRecord -- ^ ID and field-value tuples of the last entry in the stream.
    }
    | XInfoStreamEmptyResponse
    { xinfoStreamLength :: Integer -- ^ The number of entries in the stream.
    , xinfoStreamRadixTreeKeys :: Integer -- ^ The number of keys in the underlying radix data structure.
    , xinfoStreamRadixTreeNodes :: Integer -- ^ The number of nodes in the underlying radix data structure.
    , xinfoMaxDeletedEntryId :: Maybe ByteString
    {- ^ The maximal entry ID that was deleted from the stream.

    Since Redis 7.0: always returns @Nothing@ on the previous versions.
    -}
    , xinfoEntriesAdded :: Maybe Integer
    {- ^ The count of all entries added to the stream during its lifetime

    Since Redis 7.0: always returns @Nothing@ on the previous versions.
    -}
    , xinfoRecordedFirstEntryId :: Maybe ByteString
    {- ^ ID of first recorded entry.

    Since Redis 7.0: always returns @Nothing@ on the previous versions.
    -}
    , xinfoStreamNumGroups :: Integer -- ^ The number of consumer groups defined for the stream.
    , xinfoStreamLastEntryId :: ByteString -- ^ The ID of the last entry in the stream.
    }
    deriving (Show, Eq)

instance RedisResult XInfoStreamResponse where
    decode = decodeRedis5 <> decodeRedis6 <> decodeRedis7
        where
            decodeRedis5 (MultiBulk (Just [
                 Bulk (Just "length"),            Integer xinfoStreamLength,
                 Bulk (Just "radix-tree-keys"),   Integer xinfoStreamRadixTreeKeys,
                 Bulk (Just "radix-tree-nodes"),  Integer xinfoStreamRadixTreeNodes,
                 Bulk (Just "groups"),            Integer xinfoStreamNumGroups,
                 Bulk (Just "last-generated-id"), Bulk (Just xinfoStreamLastEntryId),
                 Bulk (Just "first-entry"),       Bulk Nothing ,
                 Bulk (Just "last-entry"),        Bulk Nothing ])) = do
                    return XInfoStreamEmptyResponse{
                          xinfoMaxDeletedEntryId    = Nothing
                        , xinfoEntriesAdded         = Nothing
                        , xinfoRecordedFirstEntryId = Nothing
                        , ..}
            decodeRedis5 (MultiBulk (Just [
                Bulk (Just "length"),            Integer xinfoStreamLength,
                Bulk (Just "radix-tree-keys"),   Integer xinfoStreamRadixTreeKeys,
                Bulk (Just "radix-tree-nodes"),  Integer xinfoStreamRadixTreeNodes,
                Bulk (Just "groups"),            Integer xinfoStreamNumGroups,
                Bulk (Just "last-generated-id"), Bulk (Just xinfoStreamLastEntryId),
                Bulk (Just "first-entry"),       rawFirstEntry ,
                Bulk (Just "last-entry"),        rawLastEntry ])) = do
                    xinfoStreamFirstEntry <- decode rawFirstEntry
                    xinfoStreamLastEntry  <- decode rawLastEntry
                    return XInfoStreamResponse{
                          xinfoMaxDeletedEntryId    = Nothing
                        , xinfoEntriesAdded         = Nothing
                        , xinfoRecordedFirstEntryId = Nothing
                        , ..}
            decodeRedis5 a = Left a

            decodeRedis6 (MultiBulk (Just [
                Bulk (Just "length"),            Integer xinfoStreamLength,
                Bulk (Just "radix-tree-keys"),   Integer xinfoStreamRadixTreeKeys,
                Bulk (Just "radix-tree-nodes"),  Integer xinfoStreamRadixTreeNodes,
                Bulk (Just "last-generated-id"), Bulk (Just xinfoStreamLastEntryId),
                Bulk (Just "groups"),            Integer xinfoStreamNumGroups,
                Bulk (Just "first-entry"),       Bulk Nothing ,
                Bulk (Just "last-entry"),        Bulk Nothing ])) = do
                    return XInfoStreamEmptyResponse{
                          xinfoMaxDeletedEntryId    = Nothing
                        , xinfoEntriesAdded         = Nothing
                        , xinfoRecordedFirstEntryId = Nothing
                        , ..}
            decodeRedis6 (MultiBulk (Just [
                Bulk (Just "length"),            Integer xinfoStreamLength,
                Bulk (Just "radix-tree-keys"),   Integer xinfoStreamRadixTreeKeys,
                Bulk (Just "radix-tree-nodes"),  Integer xinfoStreamRadixTreeNodes,
                Bulk (Just "last-generated-id"), Bulk (Just xinfoStreamLastEntryId),
                Bulk (Just "groups"),            Integer xinfoStreamNumGroups,
                Bulk (Just "first-entry"),       rawFirstEntry ,
                Bulk (Just "last-entry"),        rawLastEntry ])) = do
                    xinfoStreamFirstEntry <- decode rawFirstEntry
                    xinfoStreamLastEntry  <- decode rawLastEntry
                    return XInfoStreamResponse{
                          xinfoMaxDeletedEntryId    = Nothing
                        , xinfoEntriesAdded         = Nothing
                        , xinfoRecordedFirstEntryId = Nothing
                        , ..}
            decodeRedis6 a = Left a

            decodeRedis7 (MultiBulk (Just [
                Bulk (Just "length"),                  Integer xinfoStreamLength,
                Bulk (Just "radix-tree-keys"),         Integer xinfoStreamRadixTreeKeys,
                Bulk (Just "radix-tree-nodes"),        Integer xinfoStreamRadixTreeNodes,
                Bulk (Just "last-generated-id"),       Bulk (Just xinfoStreamLastEntryId),
                Bulk (Just "max-deleted-entry-id"),    Bulk (Just xinfoMaxDeletedEntryId),
                Bulk (Just "entries-added"),           Integer xinfoEntriesAdded,
                Bulk (Just "recorded-first-entry-id"), Bulk (Just xinfoRecordedFirstEntryId),
                Bulk (Just "groups"),                  Integer xinfoStreamNumGroups,
                Bulk (Just "first-entry"),             Bulk Nothing ,
                Bulk (Just "last-entry"),              Bulk Nothing ])) = do
                    return XInfoStreamEmptyResponse{
                          xinfoMaxDeletedEntryId    = Just xinfoMaxDeletedEntryId
                        , xinfoEntriesAdded         = Just xinfoEntriesAdded
                        , xinfoRecordedFirstEntryId = Just xinfoRecordedFirstEntryId
                        , ..}

            decodeRedis7 (MultiBulk (Just [
                Bulk (Just "length"),                  Integer xinfoStreamLength,
                Bulk (Just "radix-tree-keys"),         Integer xinfoStreamRadixTreeKeys,
                Bulk (Just "radix-tree-nodes"),        Integer xinfoStreamRadixTreeNodes,
                Bulk (Just "last-generated-id"),       Bulk (Just xinfoStreamLastEntryId),
                Bulk (Just "max-deleted-entry-id"),    Bulk (Just xinfoMaxDeletedEntryId),
                Bulk (Just "entries-added"),           Integer xinfoEntriesAdded,
                Bulk (Just "recorded-first-entry-id"), Bulk (Just xinfoRecordedFirstEntryId),
                Bulk (Just "groups"),                  Integer xinfoStreamNumGroups,
                Bulk (Just "first-entry"),          rawFirstEntry ,
                Bulk (Just "last-entry"),           rawLastEntry ])) = do
                    xinfoStreamFirstEntry <- decode rawFirstEntry
                    xinfoStreamLastEntry  <- decode rawLastEntry
                    return XInfoStreamResponse{
                          xinfoMaxDeletedEntryId    = Just xinfoMaxDeletedEntryId
                        , xinfoEntriesAdded         = Just xinfoEntriesAdded
                        , xinfoRecordedFirstEntryId = Just xinfoRecordedFirstEntryId
                        , ..}
            decodeRedis7 a = Left a

-- | Get info about a stream. The Redis command @XINFO@ is split into 'xinfoConsumers', 'xinfoGroups', and 'xinfoStream'.
-- Since Redis 5.0.0
xinfoStream
    :: (RedisCtx m f)
    => ByteString -- ^ stream
    -> m (f XInfoStreamResponse)
xinfoStream stream = sendRequest ["XINFO", "STREAM", stream]

-- | Delete messages from a stream.
-- Since Redis 5.0.0
xdel
    :: (RedisCtx m f)
    => ByteString -- ^ stream
    -> NonEmpty ByteString -- ^ message IDs
    -> m (f Integer)
xdel stream (messageId:|messageIds) = sendRequest ("XDEL":stream:messageId: messageIds)

-- |Conditionally deletes entries from a stream (<https://redis.io/commands/xdelex>).
--
-- $O(1)$ for each entry ID processed.
--
-- Since Redis 8.2.0
xdelex
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> NonEmpty ByteString -- ^ Entry IDs.
    -> m (f [XEntryDeletionResult])
xdelex stream messageIds =
    xdelexOpts stream messageIds defaultXEntryDeletionOpts

-- |Conditionally deletes entries from a stream (<https://redis.io/commands/xdelex>).
--
-- $O(1)$ for each entry ID processed.
--
-- Since Redis 8.2.0
xdelexOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Stream name.
    -> NonEmpty ByteString -- ^ Entry IDs.
    -> XEntryDeletionOpts -- ^ Additional options.
    -> m (f [XEntryDeletionResult])
xdelexOpts stream messageIds opts =
    sendRequest $ ["XDELEX", stream]
        ++ xEntryDeletionOptsToArgs opts
        ++ xEntryIdsBlockArgs messageIds

-- |Sets the IDMP configuration parameters for a stream (<https://redis.io/commands/xcfgset>).
--
-- $O(1)$
--
-- Since Redis 8.6.0
xcfgset
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the stream key. The stream must already exist.
    -> XCfgSetOpts
    {- ^ Configuration parameters.

       At least one of `xCfgSetIdmpDuration` or `xCfgSetIdmpMaxsize` must be specified.
       Calling `XCFGSET` clears all existing producer IDMP maps for the stream.
     -}
    -> m (f Status)
xcfgset key XCfgSetOpts{..} =
    sendRequest $
        ["XCFGSET", key]
            ++ maybe [] (\duration -> ["IDMP-DURATION", encode duration]) xCfgSetIdmpDuration
            ++ maybe [] (\maxsize -> ["IDMP-MAXSIZE", encode maxsize]) xCfgSetIdmpMaxsize

-- |Sets IDMP metadata on an existing stream message (<https://redis.io/commands/xidmprecord>).
--
-- This is an internal command used during AOF loading.
--
-- $O(1)$
--
-- Since Redis 8.6.2
xidmprecord
    :: (RedisCtx m f)
    => ByteString -- ^ Stream key.
    -> ByteString -- ^ Producer ID.
    -> ByteString -- ^ Idempotency ID.
    -> ByteString -- ^ Existing stream entry ID.
    -> m (f Status)
xidmprecord key producerId idempotencyId streamId =
    sendRequest ["XIDMPRECORD", key, producerId, idempotencyId, streamId]

-- |Releases claimed messages back to the group's PEL without acknowledging them (<https://redis.io/commands/xnack>).
--
-- $O(1)$ for each message ID processed.
--
-- Since Redis 8.8.0
xnack
    :: (RedisCtx m f)
    => ByteString -- ^ Stream key.
    -> ByteString -- ^ Consumer group name.
    -> XNackMode -- ^ Release strategy.
    -> NonEmpty ByteString -- ^ Stream entry IDs.
    -> m (f Integer)
xnack key groupName mode messageIds =
    xnackOpts key groupName mode messageIds defaultXNackOpts

-- |Releases claimed messages back to the group's PEL without acknowledging them (<https://redis.io/commands/xnack>).
--
-- $O(1)$ for each message ID processed.
--
-- Since Redis 8.8.0
xnackOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Stream key.
    -> ByteString -- ^ Consumer group name.
    -> XNackMode -- ^ Release strategy.
    -> NonEmpty ByteString -- ^ Stream entry IDs.
    -> XNackOpts -- ^ Additional options.
    -> m (f Integer)
xnackOpts key groupName mode messageIds XNackOpts{..} =
    sendRequest $
        ["XNACK", key, groupName, encode mode]
            ++ xEntryIdsBlockArgs messageIds
            ++ maybe [] (\retryCount -> ["RETRYCOUNT", encode retryCount]) xNackRetryCount
            ++ ["FORCE" | xNackForce]

-- |Set the upper bound for number of messages in a stream. Since Redis 5.0.0
xtrim
    :: (RedisCtx m f)
    => ByteString -- ^ stream
    -> TrimOpts
    -> m (f Integer)
xtrim stream opts = sendRequest ("XTRIM":stream:internalTrimArgToList opts)

-- |Constructor for `inf` Redis argument values
inf :: RealFloat a => a
inf = 1 / 0

-- | Additional parameters for the auth command.
data AuthOpts = AuthOpts
  { authOptsUsername
    :: Maybe ByteString
    {- ^ Username.

      Since Redis 6.0: fails on earlier
     -}
  }
  deriving Show

-- | Default options for AuthOpts
--
-- >>> defaultAuthOpts
-- AuthOpts {authOptsUsername = Nothing}
defaultAuthOpts :: AuthOpts
defaultAuthOpts = AuthOpts
  { authOptsUsername = Nothing
  }

-- | /O(N)/ where N is the number of passwords defined for the user.
--
-- Authenticates client to the server.
auth
    :: RedisCtx m f
    => ByteString -- ^ Password.
    -> m (f Status)
auth password = authOpts password defaultAuthOpts

-- | /O(N)/ where N is the number of passwords defined for the user.
--
-- Authenticates client to the server.
--
-- This method allows passing additional options.
authOpts
    :: RedisCtx m f
    => ByteString -- ^ Password.
    -> AuthOpts -- ^ Additional options.
    -> m (f Status)
authOpts password AuthOpts{..} = sendRequest $
  ["AUTH"] <> maybe [] (:[]) authOptsUsername <> [password]

-- |Change the selected database for the current connection (<http://redis.io/commands/select>). Since Redis 1.0.0
select
    :: RedisCtx m f
    => Integer -- ^ index
    -> m (f Status)
select ix = sendRequest ["SELECT", encode ix]

-- |Ping the server (<http://redis.io/commands/ping>). Since Redis 1.0.0
ping
    :: (RedisCtx m f)
    => m (f Status)
ping  = sendRequest (["PING"] )

-- https://redis.io/commands/cluster-info/
data ClusterInfoResponse = ClusterInfoResponse
  { clusterInfoResponseState :: ClusterInfoResponseState,
    clusterInfoResponseSlotsAssigned :: Integer,
    clusterInfoResponseSlotsOK :: Integer,
    clusterInfoResponseSlotsPfail :: Integer,
    clusterInfoResponseSlotsFail :: Integer,
    clusterInfoResponseKnownNodes :: Integer,
    clusterInfoResponseSize :: Integer,
    clusterInfoResponseCurrentEpoch :: Integer,
    clusterInfoResponseMyEpoch :: Integer,
    clusterInfoResponseStatsMessagesSent :: Integer,
    clusterInfoResponseStatsMessagesReceived :: Integer,
    clusterInfoResponseTotalLinksBufferLimitExceeded :: Integer,
    clusterInfoResponseStatsMessagesPingSent :: Maybe Integer,
    clusterInfoResponseStatsMessagesPingReceived :: Maybe Integer,
    clusterInfoResponseStatsMessagesPongSent :: Maybe Integer,
    clusterInfoResponseStatsMessagesPongReceived :: Maybe Integer,
    clusterInfoResponseStatsMessagesMeetSent :: Maybe Integer,
    clusterInfoResponseStatsMessagesMeetReceived :: Maybe Integer,
    clusterInfoResponseStatsMessagesFailSent :: Maybe Integer,
    clusterInfoResponseStatsMessagesFailReceived :: Maybe Integer,
    clusterInfoResponseStatsMessagesPublishSent :: Maybe Integer,
    clusterInfoResponseStatsMessagesPublishReceived :: Maybe Integer,
    clusterInfoResponseStatsMessagesAuthReqSent :: Maybe Integer,
    clusterInfoResponseStatsMessagesAuthReqReceived :: Maybe Integer,
    clusterInfoResponseStatsMessagesAuthAckSent :: Maybe Integer,
    clusterInfoResponseStatsMessagesAuthAckReceived :: Maybe Integer,
    clusterInfoResponseStatsMessagesUpdateSent :: Maybe Integer,
    clusterInfoResponseStatsMessagesUpdateReceived :: Maybe Integer,
    clusterInfoResponseStatsMessagesMfstartSent :: Maybe Integer,
    clusterInfoResponseStatsMessagesMfstartReceived :: Maybe Integer,
    clusterInfoResponseStatsMessagesModuleSent :: Maybe Integer,
    clusterInfoResponseStatsMessagesModuleReceived :: Maybe Integer,
    clusterInfoResponseStatsMessagesPublishshardSent :: Maybe Integer,
    clusterInfoResponseStatsMessagesPublishshardReceived :: Maybe Integer
  }
  deriving (Show, Eq)

data ClusterInfoResponseState
  = OK
  | Down
  deriving (Show, Eq)

defClusterInfoResponse :: ClusterInfoResponse
defClusterInfoResponse =
  ClusterInfoResponse
    { clusterInfoResponseState = Down,
      clusterInfoResponseSlotsAssigned = 0,
      clusterInfoResponseSlotsOK = 0,
      clusterInfoResponseSlotsPfail = 0,
      clusterInfoResponseSlotsFail = 0,
      clusterInfoResponseKnownNodes = 0,
      clusterInfoResponseSize = 0,
      clusterInfoResponseCurrentEpoch = 0,
      clusterInfoResponseMyEpoch = 0,
      clusterInfoResponseStatsMessagesSent = 0,
      clusterInfoResponseStatsMessagesReceived = 0,
      clusterInfoResponseTotalLinksBufferLimitExceeded = 0,
      clusterInfoResponseStatsMessagesPingSent = Nothing,
      clusterInfoResponseStatsMessagesPingReceived = Nothing,
      clusterInfoResponseStatsMessagesPongSent = Nothing,
      clusterInfoResponseStatsMessagesPongReceived = Nothing,
      clusterInfoResponseStatsMessagesMeetSent = Nothing,
      clusterInfoResponseStatsMessagesMeetReceived = Nothing,
      clusterInfoResponseStatsMessagesFailSent = Nothing,
      clusterInfoResponseStatsMessagesFailReceived = Nothing,
      clusterInfoResponseStatsMessagesPublishSent = Nothing,
      clusterInfoResponseStatsMessagesPublishReceived = Nothing,
      clusterInfoResponseStatsMessagesAuthReqSent = Nothing,
      clusterInfoResponseStatsMessagesAuthReqReceived = Nothing,
      clusterInfoResponseStatsMessagesAuthAckSent = Nothing,
      clusterInfoResponseStatsMessagesAuthAckReceived = Nothing,
      clusterInfoResponseStatsMessagesUpdateSent = Nothing,
      clusterInfoResponseStatsMessagesUpdateReceived = Nothing,
      clusterInfoResponseStatsMessagesMfstartSent = Nothing,
      clusterInfoResponseStatsMessagesMfstartReceived = Nothing,
      clusterInfoResponseStatsMessagesModuleSent = Nothing,
      clusterInfoResponseStatsMessagesModuleReceived = Nothing,
      clusterInfoResponseStatsMessagesPublishshardSent = Nothing,
      clusterInfoResponseStatsMessagesPublishshardReceived = Nothing
    }

parseClusterInfoResponse :: [[ByteString]] -> ClusterInfoResponse -> Maybe ClusterInfoResponse
parseClusterInfoResponse fields resp = case fields of
  [] -> pure resp
  (["cluster_state", state] : fs) -> parseState state >>= \s -> parseClusterInfoResponse fs $ resp {clusterInfoResponseState = s}
  (["cluster_slots_assigned", value] : fs) -> parseInteger value >>= \v -> parseClusterInfoResponse fs $ resp {clusterInfoResponseSlotsAssigned = v}
  (["cluster_slots_ok", value] : fs) -> parseInteger value >>= \v -> parseClusterInfoResponse fs $ resp {clusterInfoResponseSlotsOK = v}
  (["cluster_slots_pfail", value] : fs) -> parseInteger value >>= \v -> parseClusterInfoResponse fs $ resp {clusterInfoResponseSlotsPfail = v}
  (["cluster_slots_fail", value] : fs) -> parseInteger value >>= \v -> parseClusterInfoResponse fs $ resp {clusterInfoResponseSlotsFail = v}
  (["cluster_known_nodes", value] : fs) -> parseInteger value >>= \v -> parseClusterInfoResponse fs $ resp {clusterInfoResponseKnownNodes = v}
  (["cluster_size", value] : fs) -> parseInteger value >>= \v -> parseClusterInfoResponse fs $ resp {clusterInfoResponseSize = v}
  (["cluster_current_epoch", value] : fs) -> parseInteger value >>= \v -> parseClusterInfoResponse fs $ resp {clusterInfoResponseCurrentEpoch = v}
  (["cluster_my_epoch", value] : fs) -> parseInteger value >>= \v -> parseClusterInfoResponse fs $ resp {clusterInfoResponseMyEpoch = v}
  (["cluster_stats_messages_sent", value] : fs) -> parseInteger value >>= \v -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesSent = v}
  (["cluster_stats_messages_received", value] : fs) -> parseInteger value >>= \v -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesReceived = v}
  (["total_cluster_links_buffer_limit_exceeded", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseTotalLinksBufferLimitExceeded = fromMaybe 0 $ parseInteger value} -- this value should be mandatory according to the spec, but isn't necessarily set in Redis 6
  (["cluster_stats_messages_ping_sent", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesPingSent = parseInteger value}
  (["cluster_stats_messages_ping_received", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesPingReceived = parseInteger value}
  (["cluster_stats_messages_pong_sent", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesPongSent = parseInteger value}
  (["cluster_stats_messages_pong_received", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesPongReceived = parseInteger value}
  (["cluster_stats_messages_meet_sent", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesMeetSent = parseInteger value}
  (["cluster_stats_messages_meet_received", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesMeetReceived = parseInteger value}
  (["cluster_stats_messages_fail_sent", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesFailSent = parseInteger value}
  (["cluster_stats_messages_fail_received", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesFailReceived = parseInteger value}
  (["cluster_stats_messages_publish_sent", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesPublishSent = parseInteger value}
  (["cluster_stats_messages_publish_received", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesPublishReceived = parseInteger value}
  (["cluster_stats_messages_auth_req_sent", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesAuthReqSent = parseInteger value}
  (["cluster_stats_messages_auth_req_received", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesAuthReqReceived = parseInteger value}
  (["cluster_stats_messages_auth_ack_sent", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesAuthAckSent = parseInteger value}
  (["cluster_stats_messages_auth_ack_received", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesAuthAckReceived = parseInteger value}
  (["cluster_stats_messages_update_sent", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesUpdateSent = parseInteger value}
  (["cluster_stats_messages_update_received", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesUpdateReceived = parseInteger value}
  (["cluster_stats_messages_mfstart_sent", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesMfstartSent = parseInteger value}
  (["cluster_stats_messages_mfstart_received", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesMfstartReceived = parseInteger value}
  (["cluster_stats_messages_module_sent", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesModuleSent = parseInteger value}
  (["cluster_stats_messages_module_received", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesModuleReceived = parseInteger value}
  (["cluster_stats_messages_publishshard_sent", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesPublishshardSent = parseInteger value}
  (["cluster_stats_messages_publishshard_received", value] : fs) -> parseClusterInfoResponse fs $ resp {clusterInfoResponseStatsMessagesPublishshardReceived = parseInteger value}
  (_ : fs) -> parseClusterInfoResponse fs resp
  where
    parseState bs = case bs of
      "ok" -> Just OK
      "fail" -> Just Down
      _ -> Nothing
    parseInteger = fmap fst . Char8.readInteger

instance RedisResult ClusterInfoResponse where
  decode r@(Bulk (Just bulkData)) =
    maybe (Left r) Right
      . flip parseClusterInfoResponse defClusterInfoResponse
      . map (Char8.split ':' . Char8.takeWhile (/= '\r'))
      $ Char8.lines bulkData
  decode r = Left r

clusterInfo :: RedisCtx m f => m (f ClusterInfoResponse)
clusterInfo = sendRequest ["CLUSTER", "INFO"]

-- |Returns the shard ID of a node (<https://redis.io/commands/cluster-myshardid>).
--
-- $O(1)$
--
-- Since Redis 7.2.0
clusterMyshardid
    :: (RedisCtx m f)
    => m (f ByteString)
clusterMyshardid = sendRequest ["CLUSTER", "MYSHARDID"]

data ClusterNodesResponse = ClusterNodesResponse
    { clusterNodesResponseEntries :: [ClusterNodesResponseEntry]
    } deriving (Show, Eq)

data ClusterNodesResponseEntry = ClusterNodesResponseEntry { clusterNodesResponseNodeId :: ByteString
    , clusterNodesResponseNodeIp :: ByteString
    , clusterNodesResponseNodePort :: Integer
    , clusterNodesResponseNodeFlags :: [ByteString]
    , clusterNodesResponseMasterId :: Maybe ByteString
    , clusterNodesResponsePingSent :: Integer
    , clusterNodesResponsePongReceived :: Integer
    , clusterNodesResponseConfigEpoch :: Integer
    , clusterNodesResponseLinkState :: ByteString
    , clusterNodesResponseSlots :: [ClusterNodesResponseSlotSpec]
    } deriving (Show, Eq)

data ClusterNodesResponseSlotSpec
    = ClusterNodesResponseSingleSlot Integer
    | ClusterNodesResponseSlotRange Integer Integer
    | ClusterNodesResponseSlotImporting Integer ByteString
    | ClusterNodesResponseSlotMigrating Integer ByteString deriving (Show, Eq)


instance RedisResult ClusterNodesResponse where
    decode r@(Bulk (Just bulkData)) = maybe (Left r) Right $ do
        infos <- mapM parseNodeInfo $ Char8.lines bulkData
        return $ ClusterNodesResponse infos where
            parseNodeInfo :: ByteString -> Maybe ClusterNodesResponseEntry
            parseNodeInfo line = case Char8.words line of
              (nodeId : hostNamePort : flags : masterNodeId : pingSent : pongRecv : epoch : linkState : slots) ->
                case Char8.split ':' hostNamePort of
                  [hostName, port] -> ClusterNodesResponseEntry <$> pure nodeId
                                               <*> pure hostName
                                               <*> readInteger port
                                               <*> pure (Char8.split ',' flags)
                                               <*> pure (readMasterNodeId masterNodeId)
                                               <*> readInteger pingSent
                                               <*> readInteger pongRecv
                                               <*> readInteger epoch
                                               <*> pure linkState
                                               <*> (pure . catMaybes $ map readNodeSlot slots)
                  _ -> Nothing
              _ -> Nothing
            readInteger :: ByteString -> Maybe Integer
            readInteger = fmap fst . Char8.readInteger

            readMasterNodeId :: ByteString -> Maybe ByteString
            readMasterNodeId "-"    = Nothing
            readMasterNodeId nodeId = Just nodeId

            readNodeSlot :: ByteString -> Maybe ClusterNodesResponseSlotSpec
            readNodeSlot slotSpec = case '[' `Char8.elem` slotSpec of
                True -> readSlotImportMigrate slotSpec
                False -> case '-' `Char8.elem` slotSpec of
                    True -> readSlotRange slotSpec
                    False -> ClusterNodesResponseSingleSlot <$> readInteger slotSpec
            readSlotImportMigrate :: ByteString -> Maybe ClusterNodesResponseSlotSpec
            readSlotImportMigrate slotSpec = case BS.breakSubstring "->-" slotSpec of
                (_, "") -> case BS.breakSubstring "-<-" slotSpec of
                    (_, "") -> Nothing
                    (leftPart, rightPart) -> ClusterNodesResponseSlotImporting
                        <$> (readInteger $ Char8.drop 1 leftPart)
                        <*> (pure $ BS.take (BS.length rightPart - 1) rightPart)
                (leftPart, rightPart) -> ClusterNodesResponseSlotMigrating
                    <$> (readInteger $ Char8.drop 1 leftPart)
                    <*> (pure $ BS.take (BS.length rightPart - 1) rightPart)
            readSlotRange :: ByteString -> Maybe ClusterNodesResponseSlotSpec
            readSlotRange slotSpec = case BS.breakSubstring "-" slotSpec of
                (_, "") -> Nothing
                (leftPart, rightPart) -> ClusterNodesResponseSlotRange
                    <$> readInteger leftPart
                    <*> (readInteger $ BS.drop 1 rightPart)

    decode r = Left r

clusterNodes
    :: (RedisCtx m f)
    => m (f ClusterNodesResponse)
clusterNodes = sendRequest $ ["CLUSTER", "NODES"]

data ClusterSlotsResponse = ClusterSlotsResponse { clusterSlotsResponseEntries :: [ClusterSlotsResponseEntry] } deriving (Show)

data ClusterSlotsNode = ClusterSlotsNode
    { clusterSlotsNodeIP :: ByteString
    , clusterSlotsNodePort :: Int
    , clusterSlotsNodeID :: ByteString
    } deriving (Show)

data ClusterSlotsResponseEntry = ClusterSlotsResponseEntry
    { clusterSlotsResponseEntryStartSlot :: Int
    , clusterSlotsResponseEntryEndSlot :: Int
    , clusterSlotsResponseEntryMaster :: ClusterSlotsNode
    , clusterSlotsResponseEntryReplicas :: [ClusterSlotsNode]
    } deriving (Show)

instance RedisResult ClusterSlotsResponse where
    decode (MultiBulk (Just bulkData)) = do
        clusterSlotsResponseEntries <- mapM decode bulkData
        return ClusterSlotsResponse{..}
    decode a = Left a

instance RedisResult ClusterSlotsResponseEntry where
    decode (MultiBulk (Just
        ((Integer startSlot):(Integer endSlot):masterData:replicas))) = do
            clusterSlotsResponseEntryMaster <- decode masterData
            clusterSlotsResponseEntryReplicas <- mapM decode replicas
            let clusterSlotsResponseEntryStartSlot = fromInteger startSlot
            let clusterSlotsResponseEntryEndSlot = fromInteger endSlot
            return ClusterSlotsResponseEntry{..}
    decode a = Left a

instance RedisResult ClusterSlotsNode where
    decode (MultiBulk (Just ((Bulk (Just clusterSlotsNodeIP)):(Integer port):(Bulk (Just clusterSlotsNodeID)):_))) = Right ClusterSlotsNode{..}
        where clusterSlotsNodePort = fromInteger port
    decode a = Left a


clusterSlots
    :: (RedisCtx m f)
    => m (f ClusterSlotsResponse)
clusterSlots = sendRequest $ ["CLUSTER", "SLOTS"]

data ClusterSlotStatsMetric
    = ClusterSlotStatsKeyCount
    | ClusterSlotStatsCpuUsec
    | ClusterSlotStatsMemoryBytes
    | ClusterSlotStatsNetworkBytesIn
    | ClusterSlotStatsNetworkBytesOut
    deriving (Show, Eq)

instance RedisArg ClusterSlotStatsMetric where
    encode ClusterSlotStatsKeyCount = "KEY-COUNT"
    encode ClusterSlotStatsCpuUsec = "CPU-USEC"
    encode ClusterSlotStatsMemoryBytes = "MEMORY-BYTES"
    encode ClusterSlotStatsNetworkBytesIn = "NETWORK-BYTES-IN"
    encode ClusterSlotStatsNetworkBytesOut = "NETWORK-BYTES-OUT"

data ClusterSlotStatsOrderByOpts = ClusterSlotStatsOrderByOpts
    { clusterSlotStatsOrderByLimit :: Maybe Integer
    , clusterSlotStatsOrderByDirection :: SortOrder
    } deriving (Show, Eq)

defaultClusterSlotStatsOrderByOpts :: ClusterSlotStatsOrderByOpts
defaultClusterSlotStatsOrderByOpts = ClusterSlotStatsOrderByOpts
    { clusterSlotStatsOrderByLimit = Nothing
    , clusterSlotStatsOrderByDirection = Desc
    }

data ClusterSlotStatsQuery
    = ClusterSlotStatsSlotsRange Integer Integer
    | ClusterSlotStatsOrderBy ClusterSlotStatsMetric ClusterSlotStatsOrderByOpts
    deriving (Show, Eq)

data ClusterSlotStatsResponse = ClusterSlotStatsResponse
    { clusterSlotStatsResponseEntries :: [ClusterSlotStatsResponseEntry]
    } deriving (Show, Eq)

data ClusterSlotStatsResponseEntry = ClusterSlotStatsResponseEntry
    { clusterSlotStatsResponseEntrySlot :: Integer
    , clusterSlotStatsResponseEntryKeyCount :: Maybe Integer
    , clusterSlotStatsResponseEntryCpuUsec :: Maybe Integer
    , clusterSlotStatsResponseEntryMemoryBytes :: Maybe Integer
    , clusterSlotStatsResponseEntryNetworkBytesIn :: Maybe Integer
    , clusterSlotStatsResponseEntryNetworkBytesOut :: Maybe Integer
    } deriving (Show, Eq)

instance RedisResult ClusterSlotStatsResponse where
    decode (MultiBulk (Just entries)) =
        ClusterSlotStatsResponse <$> mapM decode entries
    decode r = Left r

instance RedisResult ClusterSlotStatsResponseEntry where
    decode r@(MultiBulk (Just entries)) =
        parseClusterSlotStatsEntry entries
      where
        parseClusterSlotStatsEntry :: [Reply] -> Either Reply ClusterSlotStatsResponseEntry
        parseClusterSlotStatsEntry ((Integer slot):statsReply:[]) =
            parseClusterSlotStatsFields slot =<< parseClusterSlotStatsMetricPairs statsReply
        parseClusterSlotStatsEntry fields =
            case parseClusterSlotStatsFieldPairs fields of
                Right kvs -> do
                    slot <- maybe (Left r) Right (lookup "slot" kvs)
                    parseClusterSlotStatsFields slot (filter ((/= "slot") . fst) kvs)
                Left _ -> Left r

        parseClusterSlotStatsMetricPairs :: Reply -> Either Reply [(ByteString, Integer)]
        parseClusterSlotStatsMetricPairs (MultiBulk (Just replies)) =
            case parseClusterSlotStatsFieldPairs replies of
                Right kvs -> Right kvs
                Left _ -> mapM parseNestedPair replies
          where
            parseNestedPair (MultiBulk (Just [keyReply, valueReply])) =
                (,) <$> decode keyReply <*> decode valueReply
            parseNestedPair nestedReply = Left nestedReply
        parseClusterSlotStatsMetricPairs reply' = Left reply'

        parseClusterSlotStatsFieldPairs :: [Reply] -> Either Reply [(ByteString, Integer)]
        parseClusterSlotStatsFieldPairs [] = Right []
        parseClusterSlotStatsFieldPairs (keyReply:valueReply:rest) =
            (:) <$> ((,) <$> decode keyReply <*> decode valueReply)
                <*> parseClusterSlotStatsFieldPairs rest
        parseClusterSlotStatsFieldPairs [badReply] = Left badReply

        parseClusterSlotStatsFields :: Integer -> [(ByteString, Integer)] -> Either Reply ClusterSlotStatsResponseEntry
        parseClusterSlotStatsFields slot fields =
            Right ClusterSlotStatsResponseEntry
                { clusterSlotStatsResponseEntrySlot = slot
                , clusterSlotStatsResponseEntryKeyCount = lookup "key-count" fields
                , clusterSlotStatsResponseEntryCpuUsec = lookup "cpu-usec" fields
                , clusterSlotStatsResponseEntryMemoryBytes = lookup "memory-bytes" fields
                , clusterSlotStatsResponseEntryNetworkBytesIn = lookup "network-bytes-in" fields
                , clusterSlotStatsResponseEntryNetworkBytesOut = lookup "network-bytes-out" fields
                }
    decode r = Left r

clusterSlotStats
    :: (RedisCtx m f)
    => ClusterSlotStatsQuery
    -> m (f ClusterSlotStatsResponse)
clusterSlotStats query = sendRequest $ ["CLUSTER", "SLOT-STATS"] ++ clusterSlotStatsQueryArgs query

clusterSlotStatsSlotsRange
    :: (RedisCtx m f)
    => Integer
    -> Integer
    -> m (f ClusterSlotStatsResponse)
clusterSlotStatsSlotsRange startSlot endSlot =
    clusterSlotStats (ClusterSlotStatsSlotsRange startSlot endSlot)

clusterSlotStatsOrderBy
    :: (RedisCtx m f)
    => ClusterSlotStatsMetric
    -> m (f ClusterSlotStatsResponse)
clusterSlotStatsOrderBy metric =
    clusterSlotStatsOrderByOpts metric defaultClusterSlotStatsOrderByOpts

clusterSlotStatsOrderByOpts
    :: (RedisCtx m f)
    => ClusterSlotStatsMetric
    -> ClusterSlotStatsOrderByOpts
    -> m (f ClusterSlotStatsResponse)
clusterSlotStatsOrderByOpts metric opts =
    clusterSlotStats (ClusterSlotStatsOrderBy metric opts)

clusterSlotStatsQueryArgs :: ClusterSlotStatsQuery -> [ByteString]
clusterSlotStatsQueryArgs query =
    case query of
        ClusterSlotStatsSlotsRange startSlot endSlot ->
            ["SLOTSRANGE", encode startSlot, encode endSlot]
        ClusterSlotStatsOrderBy metric ClusterSlotStatsOrderByOpts{..} ->
            ["ORDERBY", encode metric]
                ++ maybe [] (\limit -> ["LIMIT", encode limit]) clusterSlotStatsOrderByLimit
                ++ [case clusterSlotStatsOrderByDirection of
                        Asc -> "ASC"
                        Desc -> "DESC"
                   ]

clusterSetSlotImporting
    :: (RedisCtx m f)
    => Integer
    -> ByteString
    -> m (f Status)
clusterSetSlotImporting slot sourceNodeId = sendRequest $ ["CLUSTER", "SETSLOT", (encode slot), "IMPORTING", sourceNodeId]

clusterSetSlotMigrating
    :: (RedisCtx m f)
    => Integer
    -> ByteString
    -> m (f Status)
clusterSetSlotMigrating slot destinationNodeId = sendRequest $ ["CLUSTER", "SETSLOT", (encode slot), "MIGRATING", destinationNodeId]

clusterSetSlotStable
    :: (RedisCtx m f)
    => Integer
    -> m (f Status)
clusterSetSlotStable slot = sendRequest $ ["CLUSTER", "SETSLOT", "STABLE", (encode slot)]

clusterSetSlotNode
    :: (RedisCtx m f)
    => Integer
    -> ByteString
    -> m (f Status)
clusterSetSlotNode slot node = sendRequest ["CLUSTER", "SETSLOT", (encode slot), "NODE", node]

clusterGetKeysInSlot
    :: (RedisCtx m f)
    => Integer
    -> Integer
    -> m (f [ByteString])
clusterGetKeysInSlot slot count = sendRequest ["CLUSTER", "GETKEYSINSLOT", (encode slot), (encode count)]

data ClusterMigrationSlotRange = ClusterMigrationSlotRange
    { clusterMigrationSlotRangeStart :: Integer
    , clusterMigrationSlotRangeEnd :: Integer
    } deriving (Show, Eq)

data ClusterMigrationTask = ClusterMigrationTask
    { clusterMigrationTaskId :: ByteString
    , clusterMigrationTaskSlots :: [ClusterMigrationSlotRange]
    , clusterMigrationTaskSource :: Maybe ByteString
    , clusterMigrationTaskDest :: Maybe ByteString
    , clusterMigrationTaskOperation :: Maybe ByteString
    , clusterMigrationTaskState :: Maybe ByteString
    , clusterMigrationTaskLastError :: Maybe ByteString
    , clusterMigrationTaskRetries :: Maybe Integer
    , clusterMigrationTaskCreateTime :: Maybe Integer
    , clusterMigrationTaskStartTime :: Maybe Integer
    , clusterMigrationTaskEndTime :: Maybe Integer
    , clusterMigrationTaskWritePauseMs :: Maybe Integer
    } deriving (Show, Eq)

newtype ClusterMigrationStatusResponse = ClusterMigrationStatusResponse
    { clusterMigrationStatusTasks :: [ClusterMigrationTask]
    } deriving (Show, Eq)

instance RedisResult ClusterMigrationStatusResponse where
    decode (MultiBulk (Just tasks)) =
        ClusterMigrationStatusResponse <$> mapM decode tasks
    decode r = Left r

instance RedisResult ClusterMigrationTask where
    decode r@(MultiBulk (Just replies)) = do
        pairs <- parsePairs replies
        clusterMigrationTaskId <- lookupRequired "id" pairs
        clusterMigrationTaskSlots <- maybe (Right []) parseSlotsReply (lookup "slots" pairs)
        let clusterMigrationTaskSource = lookupMaybeByteString "source" pairs
        let clusterMigrationTaskDest = lookupMaybeByteString "dest" pairs
        let clusterMigrationTaskOperation = lookupMaybeByteString "operation" pairs
        let clusterMigrationTaskState = lookupMaybeByteString "state" pairs
        let clusterMigrationTaskLastError = lookupMaybeByteString "last_error" pairs
        let clusterMigrationTaskRetries = lookupInteger "retries" pairs
        let clusterMigrationTaskCreateTime = lookupInteger "create_time" pairs
        let clusterMigrationTaskStartTime = lookupInteger "start_time" pairs
        let clusterMigrationTaskEndTime = lookupInteger "end_time" pairs
        let clusterMigrationTaskWritePauseMs = lookupInteger "write_pause_ms" pairs
        Right ClusterMigrationTask{..}
      where
        parsePairs :: [Reply] -> Either Reply [(ByteString, Reply)]
        parsePairs [] = Right []
        parsePairs (keyReply:valueReply:rest) =
            (:) <$> ((,) <$> decode keyReply <*> pure valueReply) <*> parsePairs rest
        parsePairs [nestedReply] =
            case nestedReply of
                MultiBulk (Just nestedReplies) -> parseNestedPairs nestedReplies
                _ -> Left nestedReply

        parseNestedPairs :: [Reply] -> Either Reply [(ByteString, Reply)]
        parseNestedPairs nestedReplies = mapM parseNestedPair nestedReplies

        parseNestedPair :: Reply -> Either Reply (ByteString, Reply)
        parseNestedPair (MultiBulk (Just [keyReply, valueReply])) =
            (,) <$> decode keyReply <*> pure valueReply
        parseNestedPair nestedReply = Left nestedReply

        lookupRequired :: RedisResult a => ByteString -> [(ByteString, Reply)] -> Either Reply a
        lookupRequired key pairs =
            maybe (Left r) decode (lookup key pairs)

        lookupMaybeByteString :: ByteString -> [(ByteString, Reply)] -> Maybe ByteString
        lookupMaybeByteString key pairs =
            case lookup key pairs of
                Just (Bulk (Just "")) -> Nothing
                Just valueReply -> either (const Nothing) id (decode valueReply)
                Nothing -> Nothing

        lookupInteger :: ByteString -> [(ByteString, Reply)] -> Maybe Integer
        lookupInteger key pairs =
            case lookup key pairs of
                Just valueReply -> either (const Nothing) Just (decode valueReply)
                Nothing -> Nothing

        parseSlotsReply :: Reply -> Either Reply [ClusterMigrationSlotRange]
        parseSlotsReply (Bulk (Just slotRanges)) =
            mapM parseSlotToken (Char8.words $ Char8.map normalizeDelimiter slotRanges)
          where
            normalizeDelimiter ',' = ' '
            normalizeDelimiter c = c
        parseSlotsReply (MultiBulk (Just slotReplies))
            | all isIntegerReply slotReplies = parseIntegerPairs slotReplies
            | otherwise = mapM parseNestedRange slotReplies
          where
            isIntegerReply (Integer _) = True
            isIntegerReply _ = False

            parseIntegerPairs :: [Reply] -> Either Reply [ClusterMigrationSlotRange]
            parseIntegerPairs [] = Right []
            parseIntegerPairs (Integer startSlot:Integer endSlot:rest) =
                (ClusterMigrationSlotRange startSlot endSlot :) <$> parseIntegerPairs rest
            parseIntegerPairs badReplies = Left $ MultiBulk (Just badReplies)

            parseNestedRange :: Reply -> Either Reply ClusterMigrationSlotRange
            parseNestedRange (MultiBulk (Just [Integer startSlot, Integer endSlot])) =
                Right $ ClusterMigrationSlotRange startSlot endSlot
            parseNestedRange nestedReply = Left nestedReply
        parseSlotsReply badReply = Left badReply

        parseSlotToken :: ByteString -> Either Reply ClusterMigrationSlotRange
        parseSlotToken token =
            case Char8.break (== '-') token of
                (startPart, endPart)
                    | BS.null endPart -> do
                        startSlot <- parseIntegerToken token
                        Right $ ClusterMigrationSlotRange startSlot startSlot
                    | otherwise -> do
                        startSlot <- parseIntegerToken startPart
                        endSlot <- parseIntegerToken (Char8.drop 1 endPart)
                        Right $ ClusterMigrationSlotRange startSlot endSlot

        parseIntegerToken :: ByteString -> Either Reply Integer
        parseIntegerToken token =
            maybe (Left r) Right (fst <$> Char8.readInteger token)
    decode r = Left r

-- |Starts an atomic slot migration import task on the current node (<https://redis.io/commands/cluster-migration>).
--
-- $O(N)$ where $N$ is the total number of slots between the specified start and end slot arguments.
--
-- Since Redis 8.4.0
clusterMigrationImport
    :: (RedisCtx m f)
    => NonEmpty (Integer, Integer)
    {- ^ Slot ranges to import.

       Execute this subcommand on the destination master. It accepts multiple slot ranges and returns a task ID that can later be used to monitor the migration.
     -}
    -> m (f ByteString)
clusterMigrationImport slotRanges =
    sendRequest $ ["CLUSTER", "MIGRATION", "IMPORT"]
        ++ concatMap (\(startSlot, endSlot) -> [encode startSlot, encode endSlot]) (NE.toList slotRanges)

-- |Cancels an ongoing migration task by task ID (<https://redis.io/commands/cluster-migration>).
--
-- $O(N)$ where $N$ is the total number of slots between the specified start and end slot arguments.
--
-- Since Redis 8.4.0
clusterMigrationCancelId
    :: (RedisCtx m f)
    => ByteString -- ^ Task identifier.
    -> m (f Integer)
clusterMigrationCancelId taskId =
    sendRequest ["CLUSTER", "MIGRATION", "CANCEL", "ID", taskId]

-- |Cancels all ongoing migration tasks (<https://redis.io/commands/cluster-migration>).
--
-- $O(N)$ where $N$ is the total number of slots between the specified start and end slot arguments.
--
-- Since Redis 8.4.0
clusterMigrationCancelAll
    :: (RedisCtx m f)
    => m (f Integer)
clusterMigrationCancelAll =
    sendRequest ["CLUSTER", "MIGRATION", "CANCEL", "ALL"]

-- |Returns the status of current and completed atomic slot migration tasks (<https://redis.io/commands/cluster-migration>).
--
-- $O(N)$ where $N$ is the total number of slots between the specified start and end slot arguments.
--
-- Since Redis 8.4.0
clusterMigrationStatus
    :: (RedisCtx m f)
    => m (f ClusterMigrationStatusResponse)
clusterMigrationStatus =
    sendRequest ["CLUSTER", "MIGRATION", "STATUS"]

-- |Returns the status of all current and completed atomic slot migration tasks (<https://redis.io/commands/cluster-migration>).
--
-- $O(N)$ where $N$ is the total number of slots between the specified start and end slot arguments.
--
-- Since Redis 8.4.0
clusterMigrationStatusAll
    :: (RedisCtx m f)
    => m (f ClusterMigrationStatusResponse)
clusterMigrationStatusAll =
    sendRequest ["CLUSTER", "MIGRATION", "STATUS", "ALL"]

-- |Returns the status of a specific atomic slot migration task (<https://redis.io/commands/cluster-migration>).
--
-- $O(N)$ where $N$ is the total number of slots between the specified start and end slot arguments.
--
-- Since Redis 8.4.0
clusterMigrationStatusId
    :: (RedisCtx m f)
    => ByteString -- ^ Task identifier.
    -> m (f ClusterMigrationStatusResponse)
clusterMigrationStatusId taskId =
    sendRequest ["CLUSTER", "MIGRATION", "STATUS", "ID", taskId]

command :: (RedisCtx m f) => m (f [CMD.CommandInfo])
command = sendRequest ["COMMAND"]

-- |Returns a list of command names (<https://redis.io/commands/command-list>).
--
-- $O(N)$ where $N$ is the total number of Redis commands.
--
-- Since Redis 7.0.0
commandList
    :: (RedisCtx m f)
    => m (f [ByteString])
commandList = commandListOpts Nothing

data CommandListFilter
    = CommandListFilterByModule ByteString
    | CommandListFilterByAclCat ByteString
    | CommandListFilterByPattern ByteString
    deriving (Show, Eq)

-- |Returns a list of command names (<https://redis.io/commands/command-list>).
--
-- $O(N)$ where $N$ is the total number of Redis commands.
--
-- Since Redis 7.0.0
commandListOpts
    :: (RedisCtx m f)
    => Maybe CommandListFilter
    {- ^ Optional filtering mode.

       `CommandListFilterByModule` keeps only commands that belong to the given module.
       `CommandListFilterByAclCat` keeps only commands from the given ACL category.
       `CommandListFilterByPattern` keeps only commands whose names match the specified glob-style pattern.
     -}
    -> m (f [ByteString])
commandListOpts commandFilter =
    sendRequest $ ["COMMAND", "LIST"] ++ filterArgs
  where
    filterArgs =
        case commandFilter of
            Nothing -> []
            Just (CommandListFilterByModule moduleName) ->
                ["FILTERBY", "MODULE", moduleName]
            Just (CommandListFilterByAclCat category) ->
                ["FILTERBY", "ACLCAT", category]
            Just (CommandListFilterByPattern pattern_) ->
                ["FILTERBY", "PATTERN", pattern_]

data IncrexExpiration
    = IncrexSeconds Integer
    | IncrexMilliseconds Integer
    | IncrexUnixSeconds Integer
    | IncrexUnixMilliseconds Integer
    | IncrexPersist
    deriving (Show, Eq)

data IncrexOpts a = IncrexOpts
    { increxLowerBound :: Maybe a
    , increxUpperBound :: Maybe a
    , increxSaturate :: Bool
    , increxExpiration :: Maybe IncrexExpiration
    , increxExpirationIfNotExists :: Bool
    } deriving (Show, Eq)

-- |Redis default 'IncrexOpts'. Equivalent to omitting all optional parameters.
defaultIncrexOpts :: IncrexOpts a
defaultIncrexOpts = IncrexOpts
    { increxLowerBound = Nothing
    , increxUpperBound = Nothing
    , increxSaturate = False
    , increxExpiration = Nothing
    , increxExpirationIfNotExists = False
    }

-- |Increments the numeric value of a key by one and optionally updates its expiration (<https://redis.io/commands/increx>).
--
-- $O(1)$
--
-- Since Redis 8.8.0
increx
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key to increment.
    -> m (f (Integer, Integer))
increx key = increxOpts key defaultIncrexOpts

-- |Increments the numeric value of a key by one and optionally updates its expiration (<https://redis.io/commands/increx>).
--
-- $O(1)$
--
-- Since Redis 8.8.0
increxOpts
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key to increment.
    -> IncrexOpts Integer
    {- ^ Bound and expiration options.

       `LBOUND` and `UBOUND` constrain the result.
       `SATURATE` clips out-of-bounds values instead of rejecting the increment.
       `EX`/`PX`/`EXAT`/`PXAT`/`PERSIST` control the key expiration.
       `ENX` only sets the expiration when the key currently has no TTL.
     -}
    -> m (f (Integer, Integer))
increxOpts key opts =
    sendRequest $ ["INCREX", key] ++ increxCommonArgs opts

-- |Increments the integer value of a key by a specific amount and optionally updates its expiration (<https://redis.io/commands/increx>).
--
-- $O(1)$
--
-- Since Redis 8.8.0
increxBy
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key to increment.
    -> Integer -- ^ The integer increment to apply.
    -> IncrexOpts Integer -- ^ Bound and expiration options.
    -> m (f (Integer, Integer))
increxBy key increment opts =
    sendRequest $ ["INCREX", key, "BYINT", encode increment] ++ increxCommonArgs opts

-- |Increments the floating-point value of a key by a specific amount and optionally updates its expiration (<https://redis.io/commands/increx>).
--
-- $O(1)$
--
-- Since Redis 8.8.0
increxByFloat
    :: (RedisCtx m f)
    => ByteString -- ^ The name of the key to increment.
    -> Double -- ^ The floating-point increment to apply.
    -> IncrexOpts Double -- ^ Bound and expiration options.
    -> m (f (Double, Double))
increxByFloat key increment opts =
    sendRequest $ ["INCREX", key, "BYFLOAT", encode increment] ++ increxCommonArgs opts

increxCommonArgs :: RedisArg a => IncrexOpts a -> [ByteString]
increxCommonArgs IncrexOpts{..} =
    lowerBoundArg ++ upperBoundArg ++ saturateArg ++ expirationArg ++ enxArg
  where
    lowerBoundArg = maybe [] (\bound -> ["LBOUND", encode bound]) increxLowerBound
    upperBoundArg = maybe [] (\bound -> ["UBOUND", encode bound]) increxUpperBound
    saturateArg = ["SATURATE" | increxSaturate]
    expirationArg =
        case increxExpiration of
            Nothing -> []
            Just (IncrexSeconds seconds) -> ["EX", encode seconds]
            Just (IncrexMilliseconds milliseconds) -> ["PX", encode milliseconds]
            Just (IncrexUnixSeconds seconds) -> ["EXAT", encode seconds]
            Just (IncrexUnixMilliseconds milliseconds) -> ["PXAT", encode milliseconds]
            Just IncrexPersist -> ["PERSIST"]
    enxArg = ["ENX" | increxExpirationIfNotExists]

data ARGrepPredicate
    = ARGrepExact ByteString
    | ARGrepMatch ByteString
    | ARGrepGlob ByteString
    | ARGrepRegex ByteString
    deriving (Show, Eq)

data ARGrepCombine
    = ARGrepAnd
    | ARGrepOr
    deriving (Show, Eq)

data ARGrepOpts = ARGrepOpts
    { arGrepCombine :: Maybe ARGrepCombine
    , arGrepLimit :: Maybe Integer
    , arGrepNoCase :: Bool
    } deriving (Show, Eq)

-- |Redis default 'ARGrepOpts'. Equivalent to omitting all optional parameters.
defaultARGrepOpts :: ARGrepOpts
defaultARGrepOpts = ARGrepOpts
    { arGrepCombine = Nothing
    , arGrepLimit = Nothing
    , arGrepNoCase = False
    }

data ARLastItemsOpts = ARLastItemsOpts
    { arLastItemsReverse :: Bool
    } deriving (Show, Eq)

-- |Redis default 'ARLastItemsOpts'. Equivalent to omitting all optional parameters.
defaultARLastItemsOpts :: ARLastItemsOpts
defaultARLastItemsOpts = ARLastItemsOpts
    { arLastItemsReverse = False
    }

data ARScanOpts = ARScanOpts
    { arScanLimit :: Maybe Integer
    } deriving (Show, Eq)

-- |Redis default 'ARScanOpts'. Equivalent to omitting all optional parameters.
defaultARScanOpts :: ARScanOpts
defaultARScanOpts = ARScanOpts
    { arScanLimit = Nothing
    }

newtype ARIndexValuePairsResponse = ARIndexValuePairsResponse
    { arIndexValuePairs :: [(Integer, ByteString)]
    } deriving (Show, Eq)

instance RedisResult ARIndexValuePairsResponse where
    decode r@(MultiBulk (Just replies)) =
        ARIndexValuePairsResponse <$> decodePairs replies
      where
        decodePairs [] = Right []
        decodePairs (MultiBulk (Just [indexReply, valueReply]):rest) =
            (:) <$> ((,) <$> decode indexReply <*> decode valueReply) <*> decodePairs rest
        decodePairs (indexReply:valueReply:rest) =
            (:) <$> ((,) <$> decode indexReply <*> decode valueReply) <*> decodePairs rest
        decodePairs _ = Left r
    decode r = Left r

data ARInfoResponse = ARInfoResponse
    { arInfoCount :: Integer
    , arInfoLength :: Integer
    , arInfoNextInsertIndex :: Integer
    , arInfoSlices :: Integer
    , arInfoDirectorySize :: Integer
    , arInfoSuperDirEntries :: Integer
    , arInfoSliceSize :: Integer
    , arInfoDenseSlices :: Maybe Integer
    , arInfoSparseSlices :: Maybe Integer
    , arInfoAvgDenseSize :: Maybe Double
    , arInfoAvgDenseFill :: Maybe Double
    , arInfoAvgSparseSize :: Maybe Double
    } deriving (Show, Eq)

instance RedisResult ARInfoResponse where
    decode r@(MultiBulk (Just replies)) = do
        pairs <- parsePairs replies
        ARInfoResponse
            <$> required "count" pairs
            <*> required "len" pairs
            <*> required "next-insert-index" pairs
            <*> required "slices" pairs
            <*> required "directory-size" pairs
            <*> required "super-dir-entries" pairs
            <*> required "slice-size" pairs
            <*> pure (optional "dense-slices" pairs)
            <*> pure (optional "sparse-slices" pairs)
            <*> pure (optional "avg-dense-size" pairs)
            <*> pure (optional "avg-dense-fill" pairs)
            <*> pure (optional "avg-sparse-size" pairs)
      where
        parsePairs [] = Right []
        parsePairs (keyReply:valueReply:rest) =
            (:) <$> ((,) <$> decode keyReply <*> pure valueReply) <*> parsePairs rest
        parsePairs _ = Left r

        required :: RedisResult a => ByteString -> [(ByteString, Reply)] -> Either Reply a
        required key pairs = maybe (Left r) decode (lookup key pairs)

        optional :: RedisResult a => ByteString -> [(ByteString, Reply)] -> Maybe a
        optional key pairs = lookup key pairs >>= either (const Nothing) Just . decode
    decode r = Left r

data AROpValue
    = AROpSum
    | AROpMin
    | AROpMax
    deriving (Show, Eq)

data AROpCount
    = AROpAnd
    | AROpOr
    | AROpXor
    | AROpMatch ByteString
    | AROpUsed
    deriving (Show, Eq)

argrepPredicateArgs :: ARGrepPredicate -> [ByteString]
argrepPredicateArgs predicate =
    case predicate of
        ARGrepExact value -> ["EXACT", value]
        ARGrepMatch value -> ["MATCH", value]
        ARGrepGlob pattern_ -> ["GLOB", pattern_]
        ARGrepRegex pattern_ -> ["RE", pattern_]

argrepOptsArgs :: ARGrepOpts -> [ByteString]
argrepOptsArgs ARGrepOpts{..} =
    combineArg ++ limitArg ++ nocaseArg
  where
    combineArg =
        case arGrepCombine of
            Nothing -> []
            Just ARGrepAnd -> ["AND"]
            Just ARGrepOr -> ["OR"]
    limitArg = maybe [] (\limit -> ["LIMIT", encode limit]) arGrepLimit
    nocaseArg = ["NOCASE" | arGrepNoCase]

aropValueArg :: AROpValue -> ByteString
aropValueArg operation =
    case operation of
        AROpSum -> "SUM"
        AROpMin -> "MIN"
        AROpMax -> "MAX"

aropCountArgs :: AROpCount -> [ByteString]
aropCountArgs operation =
    case operation of
        AROpAnd -> ["AND"]
        AROpOr -> ["OR"]
        AROpXor -> ["XOR"]
        AROpMatch value -> ["MATCH", value]
        AROpUsed -> ["USED"]

-- |Returns the number of non-empty elements in an array (<https://redis.io/commands/arcount>).
--
-- $O(1)$
--
-- Since Redis 8.8.0
arcount
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> m (f Integer)
arcount key = sendRequest ["ARCOUNT", key]

-- |Deletes elements at the specified indices in an array (<https://redis.io/commands/ardel>).
--
-- $O(N)$ where $N$ is the number of indices to delete.
--
-- Since Redis 8.8.0
ardel
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> NonEmpty Integer -- ^ One or more zero-based indices to delete.
    -> m (f Integer)
ardel key indices =
    sendRequest $ ["ARDEL", key] ++ map encode (NE.toList indices)

-- |Gets values in a range of indices (<https://redis.io/commands/argetrange>).
--
-- $O(N)$ where $N$ is the range length.
--
-- Since Redis 8.8.0
argetrange
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> Integer -- ^ Start index.
    -> Integer -- ^ End index, inclusive.
    -> m (f [Maybe ByteString])
argetrange key start end =
    sendRequest ["ARGETRANGE", key, encode start, encode end]

-- |Searches array elements in a range using textual predicates (<https://redis.io/commands/argrep>).
--
-- $O(P * C)$ where $P$ is the number of visited positions and $C$ is the cost of evaluating predicates.
--
-- Since Redis 8.8.0
argrep
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> ByteString -- ^ Start index or `-` for the first array index.
    -> ByteString -- ^ End index or `+` for the last array index.
    -> NonEmpty ARGrepPredicate -- ^ One or more predicates to apply.
    -> m (f [Integer])
argrep key start end predicates =
    argrepOpts key start end predicates defaultARGrepOpts

-- |Searches array elements in a range using textual predicates (<https://redis.io/commands/argrep>).
--
-- $O(P * C)$ where $P$ is the number of visited positions and $C$ is the cost of evaluating predicates.
--
-- Since Redis 8.8.0
argrepOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> ByteString -- ^ Start index or `-` for the first array index.
    -> ByteString -- ^ End index or `+` for the last array index.
    -> NonEmpty ARGrepPredicate -- ^ One or more predicates to apply.
    -> ARGrepOpts -- ^ Additional predicate options.
    -> m (f [Integer])
argrepOpts key start end predicates opts =
    sendRequest $
        ["ARGREP", key, start, end]
            ++ concatMap argrepPredicateArgs (NE.toList predicates)
            ++ argrepOptsArgs opts

-- |Searches array elements in a range and returns matching index-value pairs (<https://redis.io/commands/argrep>).
--
-- $O(P * C)$ where $P$ is the number of visited positions and $C$ is the cost of evaluating predicates.
--
-- Since Redis 8.8.0
argrepWithValues
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> ByteString -- ^ Start index or `-` for the first array index.
    -> ByteString -- ^ End index or `+` for the last array index.
    -> NonEmpty ARGrepPredicate -- ^ One or more predicates to apply.
    -> m (f ARIndexValuePairsResponse)
argrepWithValues key start end predicates =
    argrepWithValuesOpts key start end predicates defaultARGrepOpts

-- |Searches array elements in a range and returns matching index-value pairs (<https://redis.io/commands/argrep>).
--
-- $O(P * C)$ where $P$ is the number of visited positions and $C$ is the cost of evaluating predicates.
--
-- Since Redis 8.8.0
argrepWithValuesOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> ByteString -- ^ Start index or `-` for the first array index.
    -> ByteString -- ^ End index or `+` for the last array index.
    -> NonEmpty ARGrepPredicate -- ^ One or more predicates to apply.
    -> ARGrepOpts -- ^ Additional predicate options.
    -> m (f ARIndexValuePairsResponse)
argrepWithValuesOpts key start end predicates opts =
    sendRequest $
        ["ARGREP", key, start, end]
            ++ concatMap argrepPredicateArgs (NE.toList predicates)
            ++ ["WITHVALUES"]
            ++ argrepOptsArgs opts

-- |Returns metadata about an array (<https://redis.io/commands/arinfo>).
--
-- $O(1)$, or $O(N)$ with `FULL` where $N$ is the number of slices.
--
-- Since Redis 8.8.0
arinfo
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> m (f ARInfoResponse)
arinfo key = sendRequest ["ARINFO", key]

-- |Returns extended metadata about an array (<https://redis.io/commands/arinfo>).
--
-- $O(N)$ where $N$ is the number of slices.
--
-- Since Redis 8.8.0
arinfoFull
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> m (f ARInfoResponse)
arinfoFull key = sendRequest ["ARINFO", key, "FULL"]

-- |Inserts one or more values at consecutive indices (<https://redis.io/commands/arinsert>).
--
-- $O(N)$ where $N$ is the number of values.
--
-- Since Redis 8.8.0
arinsert
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> NonEmpty ByteString -- ^ Values to insert at the current insert cursor.
    -> m (f Integer)
arinsert key values =
    sendRequest $ ["ARINSERT", key] ++ NE.toList values

-- |Returns the most recently inserted elements (<https://redis.io/commands/arlastitems>).
--
-- $O(N)$ where $N$ is the count.
--
-- Since Redis 8.8.0
arlastitems
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> Integer -- ^ Maximum number of most recently inserted elements to return.
    -> m (f [Maybe ByteString])
arlastitems key count =
    arlastitemsOpts key count defaultARLastItemsOpts

-- |Returns the most recently inserted elements (<https://redis.io/commands/arlastitems>).
--
-- $O(N)$ where $N$ is the count.
--
-- Since Redis 8.8.0
arlastitemsOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> Integer -- ^ Maximum number of most recently inserted elements to return.
    -> ARLastItemsOpts -- ^ Additional options.
    -> m (f [Maybe ByteString])
arlastitemsOpts key count ARLastItemsOpts{..} =
    sendRequest $ ["ARLASTITEMS", key, encode count] ++ ["REV" | arLastItemsReverse]

-- |Returns the length of an array (max index + 1) (<https://redis.io/commands/arlen>).
--
-- $O(1)$
--
-- Since Redis 8.8.0
arlen
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> m (f Integer)
arlen key = sendRequest ["ARLEN", key]

-- |Gets values at multiple indices in an array (<https://redis.io/commands/armget>).
--
-- $O(N)$ where $N$ is the number of indices.
--
-- Since Redis 8.8.0
armget
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> NonEmpty Integer -- ^ One or more zero-based indices.
    -> m (f [Maybe ByteString])
armget key indices =
    sendRequest $ ["ARMGET", key] ++ map encode (NE.toList indices)

-- |Returns the next index that `ARINSERT` would use (<https://redis.io/commands/arnext>).
--
-- $O(1)$
--
-- Since Redis 8.8.0
arnext
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> m (f (Maybe Integer))
arnext key = sendRequest ["ARNEXT", key]

-- |Performs aggregate operations on array elements in a range and returns a string result (<https://redis.io/commands/arop>).
--
-- $O(P)$ where $P$ is the number of visited positions in touched slices.
--
-- Since Redis 8.8.0
aropValue
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> Integer -- ^ Start index.
    -> Integer -- ^ End index.
    -> AROpValue -- ^ Aggregate operation.
    -> m (f (Maybe ByteString))
aropValue key start end operation =
    sendRequest ["AROP", key, encode start, encode end, aropValueArg operation]

-- |Performs aggregate operations on array elements in a range and returns an integer result (<https://redis.io/commands/arop>).
--
-- $O(P)$ where $P$ is the number of visited positions in touched slices.
--
-- Since Redis 8.8.0
aropCount
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> Integer -- ^ Start index.
    -> Integer -- ^ End index.
    -> AROpCount -- ^ Aggregate operation.
    -> m (f (Maybe Integer))
aropCount key start end operation =
    sendRequest $ ["AROP", key, encode start, encode end] ++ aropCountArgs operation

-- |Inserts values into a ring buffer of specified size, wrapping and truncating as needed (<https://redis.io/commands/arring>).
--
-- $O(M)$ normally, or $O(N+M)$ on ring resize.
--
-- Since Redis 8.8.0
arring
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> Integer -- ^ Ring buffer size.
    -> NonEmpty ByteString -- ^ Values to insert.
    -> m (f Integer)
arring key size values =
    sendRequest $ ["ARRING", key, encode size] ++ NE.toList values

-- |Iterates existing elements in a range, returning index-value pairs (<https://redis.io/commands/arscan>).
--
-- $O(P)$ where $P$ is the number of visited positions in touched slices.
--
-- Since Redis 8.8.0
arscan
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> Integer -- ^ Start index.
    -> Integer -- ^ End index.
    -> m (f ARIndexValuePairsResponse)
arscan key start end =
    arscanOpts key start end defaultARScanOpts

-- |Iterates existing elements in a range, returning index-value pairs (<https://redis.io/commands/arscan>).
--
-- $O(P)$ where $P$ is the number of visited positions in touched slices.
--
-- Since Redis 8.8.0
arscanOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> Integer -- ^ Start index.
    -> Integer -- ^ End index.
    -> ARScanOpts -- ^ Additional options.
    -> m (f ARIndexValuePairsResponse)
arscanOpts key start end ARScanOpts{..} =
    sendRequest $
        ["ARSCAN", key, encode start, encode end]
            ++ maybe [] (\limit -> ["LIMIT", encode limit]) arScanLimit

-- |Sets the `ARINSERT` / `ARRING` cursor to a specific index (<https://redis.io/commands/arseek>).
--
-- $O(1)$
--
-- Since Redis 8.8.0
arseek
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> Integer -- ^ The new insert cursor position.
    -> m (f Bool)
arseek key index = sendRequest ["ARSEEK", key, encode index]

-- |Sets one or more contiguous values starting at an index in an array (<https://redis.io/commands/arset>).
--
-- $O(N)$ where $N$ is the number of values.
--
-- Since Redis 8.8.0
arset
    :: (RedisCtx m f)
    => ByteString -- ^ Array key.
    -> Integer -- ^ Start index.
    -> NonEmpty ByteString -- ^ One or more values to store at consecutive indices.
    -> m (f Integer)
arset key index values =
    sendRequest $ ["ARSET", key, encode index] ++ NE.toList values

data HotkeysMetric
    = HotkeysMetricCPU
    | HotkeysMetricNET
    deriving (Show, Eq)

instance RedisArg HotkeysMetric where
    encode HotkeysMetricCPU = "CPU"
    encode HotkeysMetricNET = "NET"

data HotkeysStartOpts = HotkeysStartOpts
    { hotkeysStartTopKCount :: Maybe Integer
      -- ^ The value of K for the top-K hotkeys tracking.
    , hotkeysStartDurationSeconds :: Maybe Integer
      -- ^ The number of seconds to keep tracking before it stops automatically.
    , hotkeysStartSampleRatio :: Maybe Integer
      -- ^ The probabilistic sampling ratio. Each key is sampled with probability @1/ratio@.
    , hotkeysStartSlots :: Maybe (NonEmpty Integer)
      -- ^ The hash slots to track in cluster mode.
    } deriving (Show, Eq)

-- |Redis default 'HotkeysStartOpts'. Equivalent to omitting all optional parameters.
defaultHotkeysStartOpts :: HotkeysStartOpts
defaultHotkeysStartOpts = HotkeysStartOpts
    { hotkeysStartTopKCount = Nothing
    , hotkeysStartDurationSeconds = Nothing
    , hotkeysStartSampleRatio = Nothing
    , hotkeysStartSlots = Nothing
    }

data HotkeysSlotRange = HotkeysSlotRange
    { hotkeysSlotRangeStart :: Integer
    , hotkeysSlotRangeEnd :: Integer
    } deriving (Show, Eq)

instance RedisResult HotkeysSlotRange where
    decode (MultiBulk (Just [Integer slot])) =
        Right HotkeysSlotRange
            { hotkeysSlotRangeStart = slot
            , hotkeysSlotRangeEnd = slot
            }
    decode (MultiBulk (Just [Integer start, Integer end])) =
        Right HotkeysSlotRange
            { hotkeysSlotRangeStart = start
            , hotkeysSlotRangeEnd = end
            }
    decode r = Left r

data HotkeysGetResponse = HotkeysGetResponse
    { hotkeysGetTrackingActive :: Bool
    , hotkeysGetSampleRatio :: Integer
    , hotkeysGetSelectedSlots :: [HotkeysSlotRange]
    , hotkeysGetAllCommandsAllSlotsUs :: Integer
    , hotkeysGetNetBytesAllCommandsAllSlots :: Integer
    , hotkeysGetCollectionStartTimeUnixMs :: Integer
    , hotkeysGetCollectionDurationMs :: Integer
    , hotkeysGetTotalCpuTimeUserMs :: Maybe Integer
    , hotkeysGetTotalCpuTimeSysMs :: Maybe Integer
    , hotkeysGetTotalNetBytes :: Maybe Integer
    , hotkeysGetByCpuTimeUs :: Maybe [(ByteString, Integer)]
    , hotkeysGetByNetBytes :: Maybe [(ByteString, Integer)]
    , hotkeysGetSampledCommandsSelectedSlotsUs :: Maybe Integer
    , hotkeysGetAllCommandsSelectedSlotsUs :: Maybe Integer
    , hotkeysGetNetBytesSampledCommandsSelectedSlots :: Maybe Integer
    , hotkeysGetNetBytesAllCommandsSelectedSlots :: Maybe Integer
    } deriving (Show, Eq)

instance RedisResult HotkeysGetResponse where
    decode (MultiBulk (Just [payload])) = decode payload
    decode r@(MultiBulk (Just replies)) = do
        pairs <- parsePairs replies
        hotkeysGetTrackingActive <- require "tracking-active" pairs
        hotkeysGetSampleRatio <- require "sample-ratio" pairs
        hotkeysGetSelectedSlots <- require "selected-slots" pairs
        hotkeysGetAllCommandsAllSlotsUs <- require "all-commands-all-slots-us" pairs
        hotkeysGetNetBytesAllCommandsAllSlots <- require "net-bytes-all-commands-all-slots" pairs
        hotkeysGetCollectionStartTimeUnixMs <- require "collection-start-time-unix-ms" pairs
        hotkeysGetCollectionDurationMs <- require "collection-duration-ms" pairs
        let hotkeysGetTotalCpuTimeUserMs = optional "total-cpu-time-user-ms" pairs
            hotkeysGetTotalCpuTimeSysMs = optional "total-cpu-time-sys-ms" pairs
            hotkeysGetTotalNetBytes = optional "total-net-bytes" pairs
            hotkeysGetByCpuTimeUs = optional "by-cpu-time-us" pairs
            hotkeysGetByNetBytes = optional "by-net-bytes" pairs
            hotkeysGetSampledCommandsSelectedSlotsUs = optional "sampled-commands-selected-slots-us" pairs
            hotkeysGetAllCommandsSelectedSlotsUs = optional "all-commands-selected-slots-us" pairs
            hotkeysGetNetBytesSampledCommandsSelectedSlots = optional "net-bytes-sampled-commands-selected-slots" pairs
            hotkeysGetNetBytesAllCommandsSelectedSlots = optional "net-bytes-all-commands-selected-slots" pairs
        pure HotkeysGetResponse{..}
      where
        parsePairs [] = Right []
        parsePairs (keyReply:valueReply:rest) =
            (:) <$> ((,) <$> decode keyReply <*> pure valueReply) <*> parsePairs rest
        parsePairs _ = Left r

        require :: RedisResult a => ByteString -> [(ByteString, Reply)] -> Either Reply a
        require key pairs =
            maybe (Left r) decode (lookup key pairs)

        optional :: RedisResult a => ByteString -> [(ByteString, Reply)] -> Maybe a
        optional key pairs = lookup key pairs >>= either (const Nothing) Just . decode
    decode r = Left r

-- |Starts hotkeys tracking (<https://redis.io/commands/hotkeys-start>).
--
-- $O(1)$
--
-- Since Redis 8.6.0
hotkeysStart
    :: (RedisCtx m f)
    => NonEmpty HotkeysMetric
    {- ^ The metrics to track.

       The command automatically derives the `METRICS count` argument from the number of provided metrics.
       At least one metric must be specified.
     -}
    -> m (f Status)
hotkeysStart metrics = hotkeysStartOpts metrics defaultHotkeysStartOpts

-- |Starts hotkeys tracking (<https://redis.io/commands/hotkeys-start>).
--
-- $O(1)$
--
-- Since Redis 8.6.0
hotkeysStartOpts
    :: (RedisCtx m f)
    => NonEmpty HotkeysMetric -- ^ The metrics to track.
    -> HotkeysStartOpts -- ^ Additional tracking options.
    -> m (f Status)
hotkeysStartOpts metrics HotkeysStartOpts{..} =
    sendRequest $
        ["HOTKEYS", "START", "METRICS", encode (toInteger $ NE.length metrics)]
            ++ map encode (NE.toList metrics)
            ++ maybe [] (\count -> ["COUNT", encode count]) hotkeysStartTopKCount
            ++ maybe [] (\duration -> ["DURATION", encode duration]) hotkeysStartDurationSeconds
            ++ maybe [] (\ratio -> ["SAMPLE", encode ratio]) hotkeysStartSampleRatio
            ++ maybe [] slotsArgs hotkeysStartSlots
  where
    slotsArgs slots = ["SLOTS", encode (toInteger $ NE.length slots)] ++ map encode (NE.toList slots)

-- |Returns tracking results and metadata from the current or most recent hotkeys tracking session (<https://redis.io/commands/hotkeys-get>).
--
-- $O(K)$ where $K$ is the number of hotkeys returned.
--
-- Since Redis 8.6.0
hotkeysGet
    :: (RedisCtx m f)
    => m (f HotkeysGetResponse)
hotkeysGet = sendRequest ["HOTKEYS", "GET"]

-- |Stops hotkeys tracking (<https://redis.io/commands/hotkeys-stop>).
--
-- $O(1)$
--
-- Since Redis 8.6.0
hotkeysStop
    :: (RedisCtx m f)
    => m (f Status)
hotkeysStop = sendRequest ["HOTKEYS", "STOP"]

-- |Release the resources used for hotkey tracking (<https://redis.io/commands/hotkeys-reset>).
--
-- $O(1)$
--
-- Since Redis 8.6.0
hotkeysReset
    :: (RedisCtx m f)
    => m (f Status)
hotkeysReset = sendRequest ["HOTKEYS", "RESET"]


data ExpireOpts
  = ExpireOptsTime Condition
  | ExpireOptsValue SizeCondition

instance RedisArg ExpireOpts where
  encode (ExpireOptsTime c)  = encode c
  encode (ExpireOptsValue c) = encode c

-- |Set the expiration for a key as a UNIX timestamp specified in milliseconds (<http://redis.io/commands/pexpireat>).
-- Since Redis 7.0
pexpireatOpts
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ millisecondsTimestamp
    -> ExpireOpts
    -> m (f Bool)
pexpireatOpts key millisecondsTimestamp opts =
  sendRequest ["PEXPIREAT", key, encode millisecondsTimestamp, encode opts]

expireOpts
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ seconds
    -> ExpireOpts
    -> m (f Bool)
expireOpts key seconds opts = sendRequest ["EXPIRE", key, encode seconds, encode opts]

-- | Set the expiration for a key as a UNIX timestamp (<http://redis.io/commands/expireat>).
-- Since Redis 1.2.0
expireatOpts
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ timestamp
    -> ExpireOpts
    -> m (f Bool)
expireatOpts key timestamp opts = sendRequest ["EXPIREAT", key, encode timestamp, encode opts]

data FlushOpts
  = FlushOptsSync
  | FlushOptsAsync

instance RedisArg FlushOpts where
  encode FlushOptsSync = "SYNC"
  encode FlushOptsAsync = "ASYNC"

-- |Remove all keys from the current database (<http://redis.io/commands/flushdb>).
-- Since Redis 6.2
flushdbOpts
    :: (RedisCtx m f)
    => FlushOpts
    -> m (f Status)
flushdbOpts opts = sendRequest ["FLUSHDB", encode opts]

-- |Remove all keys from the current database (<http://redis.io/commands/flushdb>).
-- Since Redis 6.2
flushallOpts
    :: (RedisCtx m f)
    => FlushOpts
    -> m (f Status)
flushallOpts opts = sendRequest ["FLUSHALL", encode opts]

data BitposType = Byte | Bit

instance RedisArg BitposType where
  encode Byte = "BYTE"
  encode Bit = "BIT"

data BitposOpts
  = BitposOptsStart Integer
  | BitposOptsStartEnd Integer Integer (Maybe BitposType)

bitposOpts
    :: (RedisCtx m f)
    => ByteString
    -> Integer
    -> BitposOpts
    -> m (f Integer)
bitposOpts key_ bit opts = sendRequest ("BITPOS": key_:encode bit: rest) where
  rest  = case opts of
    BitposOptsStart s -> [encode s]
    BitposOptsStartEnd start end bits ->
      [encode start, encode end] ++ [ encode bits_ | Just bits_ <- pure bits]

-- |Get a substring of the string stored at a key (<http://redis.io/commands/substr>).
--
-- Deprecated in Redis. Use 'getrange' instead.
--
-- Since Redis 1.0.0
substr
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ end
    -> m (f ByteString)
substr key start end = sendRequest ["SUBSTR", key, encode start, encode end]
