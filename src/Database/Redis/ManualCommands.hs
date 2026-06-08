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

xack
    :: (RedisCtx m f)
    => ByteString -- ^ stream
    -> ByteString -- ^ group name
    -> [ByteString] -- ^ message IDs
    -> m (f Integer)
xack stream groupName messageIds = sendRequest $ ["XACK", stream, groupName] ++ messageIds

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

command :: (RedisCtx m f) => m (f [CMD.CommandInfo])
command = sendRequest ["COMMAND"]


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
