{-# LANGUAGE OverloadedStrings, RecordWildCards, FlexibleContexts
  #-}

module Database.Redis.ManualCommands where

import Data.ByteString (ByteString, empty, append)
import Data.Maybe (maybeToList)
import Database.Redis.Core
import Database.Redis.Protocol
import Database.Redis.Types
import Prelude hiding (min, max)

objectRefcount
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> m (f Integer)
objectRefcount key = sendRequest ["OBJECT", "refcount", encode key]

objectIdletime
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> m (f Integer)
objectIdletime key = sendRequest ["OBJECT", "idletime", encode key]

objectEncoding
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> m (f ByteString)
objectEncoding key = sendRequest ["OBJECT", "encoding", encode key]

linsertBefore
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> ByteString -- ^ pivot
  -> ByteString -- ^ value
  -> m (f Integer)
linsertBefore key pivot value =
  sendRequest ["LINSERT", encode key, "BEFORE", encode pivot, encode value]

linsertAfter
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> ByteString -- ^ pivot
  -> ByteString -- ^ value
  -> m (f Integer)
linsertAfter key pivot value =
  sendRequest ["LINSERT", encode key, "AFTER", encode pivot, encode value]

getType
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> m (f RedisType)
getType key = sendRequest ["TYPE", encode key]

-- |A single entry from the slowlog.
data Slowlog = Slowlog
  { slowlogId :: Integer
      -- ^ A unique progressive identifier for every slow log entry.
  , slowlogTimestamp :: Integer
      -- ^ The unix timestamp at which the logged command was processed.
  , slowlogMicros :: Integer
      -- ^ The amount of time needed for its execution, in microseconds.
  , slowlogCmd :: [ByteString]
      -- ^ The command and it's arguments.
  } deriving (Show, Eq)

instance RedisResult Slowlog where
  decode (MultiBulk (Just [logId, timestamp, micros, cmd])) = do
    slowlogId <- decode logId
    slowlogTimestamp <- decode timestamp
    slowlogMicros <- decode micros
    slowlogCmd <- decode cmd
    return Slowlog {..}
  decode r = Left r

slowlogGet
  :: (RedisCtx m f)
  => Integer -- ^ cnt
  -> m (f [Slowlog])
slowlogGet n = sendRequest ["SLOWLOG", "GET", encode n]

slowlogLen
  :: (RedisCtx m f)
  => m (f Integer)
slowlogLen = sendRequest ["SLOWLOG", "LEN"]

slowlogReset
  :: (RedisCtx m f)
  => m (f Status)
slowlogReset = sendRequest ["SLOWLOG", "RESET"]

zrange
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> Integer -- ^ start
  -> Integer -- ^ stop
  -> m (f [ByteString])
zrange key start stop =
  sendRequest ["ZRANGE", encode key, encode start, encode stop]

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
  sendRequest ["ZREVRANGE", encode key, encode start, encode stop, "WITHSCORES"]

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
  sendRequest
    ["ZRANGEBYSCORE", encode key, encode min, encode max, "WITHSCORES"]

zrangebyscoreLimit
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> Double -- ^ min
  -> Double -- ^ max
  -> Integer -- ^ offset
  -> Integer -- ^ count
  -> m (f [ByteString])
zrangebyscoreLimit key min max offset count =
  sendRequest
    [ "ZRANGEBYSCORE"
    , encode key
    , encode min
    , encode max
    , "LIMIT"
    , encode offset
    , encode count
    ]

zrangebyscoreWithscoresLimit
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> Double -- ^ min
  -> Double -- ^ max
  -> Integer -- ^ offset
  -> Integer -- ^ count
  -> m (f [(ByteString, Double)])
zrangebyscoreWithscoresLimit key min max offset count =
  sendRequest
    [ "ZRANGEBYSCORE"
    , encode key
    , encode min
    , encode max
    , "WITHSCORES"
    , "LIMIT"
    , encode offset
    , encode count
    ]

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
  sendRequest
    ["ZREVRANGEBYSCORE", encode key, encode min, encode max, "WITHSCORES"]

zrevrangebyscoreLimit
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> Double -- ^ max
  -> Double -- ^ min
  -> Integer -- ^ offset
  -> Integer -- ^ count
  -> m (f [ByteString])
zrevrangebyscoreLimit key min max offset count =
  sendRequest
    [ "ZREVRANGEBYSCORE"
    , encode key
    , encode min
    , encode max
    , "LIMIT"
    , encode offset
    , encode count
    ]

zrevrangebyscoreWithscoresLimit
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> Double -- ^ max
  -> Double -- ^ min
  -> Integer -- ^ offset
  -> Integer -- ^ count
  -> m (f [(ByteString, Double)])
zrevrangebyscoreWithscoresLimit key min max offset count =
  sendRequest
    [ "ZREVRANGEBYSCORE"
    , encode key
    , encode min
    , encode max
    , "WITHSCORES"
    , "LIMIT"
    , encode offset
    , encode count
    ]

-- |Options for the 'sort' command.
data SortOpts = SortOpts
  { sortBy :: Maybe ByteString
  , sortLimit :: (Integer, Integer)
  , sortGet :: [ByteString]
  , sortOrder :: SortOrder
  , sortAlpha :: Bool
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
defaultSortOpts =
  SortOpts
  { sortBy = Nothing
  , sortLimit = (0, -1)
  , sortGet = []
  , sortOrder = Asc
  , sortAlpha = False
  }

data SortOrder
  = Asc
  | Desc
  deriving (Show, Eq)

data GeoRadiusOpts = GeoRadiusOpts
  { withCoordinates :: Bool
  , withDistance :: Bool
  , withGeoHash :: Bool
  , count :: Maybe Int
  , distanceSortOrder :: SortOrder
  , store :: Maybe ByteString
  , storeDist :: Maybe ByteString
  }  deriving (Show, Eq)

defaultGeoRadiusOpts :: GeoRadiusOpts
defaultGeoRadiusOpts =
  GeoRadiusOpts
  { withCoordinates = False
  , withDistance = False
  , withGeoHash = False
  , count = Nothing
  , distanceSortOrder = Asc
  , store = Nothing
  , storeDist = Nothing
  }

sortStore
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> ByteString -- ^ destination
  -> SortOpts
  -> m (f Integer)
sortStore key dest = sortInternal key (Just dest)

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
sortInternal key destination SortOpts {..} =
  sendRequest $
  concat [["SORT", encode key], by, limit, get, order, alpha, store]
  where
    by = maybe [] (\pattern -> ["BY", pattern]) sortBy
    limit =
      let (off, cnt) = sortLimit
      in ["LIMIT", encode off, encode cnt]
    get = concatMap (\pattern -> ["GET", pattern]) sortGet
    order =
      case sortOrder of
        Desc -> ["DESC"]
        Asc -> ["ASC"]
    alpha = ["ALPHA" | sortAlpha]
    store = maybe [] (\dest -> ["STORE", dest]) destination

data Aggregate
  = Sum
  | Min
  | Max
  deriving (Show, Eq)

zunionstore
  :: (RedisCtx m f)
  => ByteString -- ^ destination
  -> [ByteString] -- ^ keys
  -> Aggregate
  -> m (f Integer)
zunionstore dest keys = zstoreInternal "ZUNIONSTORE" dest keys []

zunionstoreWeights
  :: (RedisCtx m f)
  => ByteString -- ^ destination
  -> [(ByteString, Double)] -- ^ weighted keys
  -> Aggregate
  -> m (f Integer)
zunionstoreWeights dest kws =
  let (keys, weights) = unzip kws
  in zstoreInternal "ZUNIONSTORE" dest keys weights

zinterstore
  :: (RedisCtx m f)
  => ByteString -- ^ destination
  -> [ByteString] -- ^ keys
  -> Aggregate
  -> m (f Integer)
zinterstore dest keys = zstoreInternal "ZINTERSTORE" dest keys []

zinterstoreWeights
  :: (RedisCtx m f)
  => ByteString -- ^ destination
  -> [(ByteString, Double)] -- ^ weighted keys
  -> Aggregate
  -> m (f Integer)
zinterstoreWeights dest kws =
  let (keys, weights) = unzip kws
  in zstoreInternal "ZINTERSTORE" dest keys weights

zstoreInternal
  :: (RedisCtx m f)
  => ByteString -- ^ cmd
  -> ByteString -- ^ destination
  -> [ByteString] -- ^ keys
  -> [Double] -- ^ weights
  -> Aggregate
  -> m (f Integer)
zstoreInternal cmd dest keys weights aggregate =
  sendRequest $
  concat
    [ [cmd, dest, encode . toInteger $ length keys]
    , keys
    , if null weights
        then []
        else "WEIGHTS" : map encode weights
    , ["AGGREGATE", aggregate']
    ]
  where
    aggregate' =
      case aggregate of
        Sum -> "SUM"
        Min -> "MIN"
        Max -> "MAX"

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

evalsha
  :: (RedisCtx m f, RedisResult a)
  => ByteString -- ^ script
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
bitopAnd dst srcs = bitop "AND" (dst : srcs)

bitopOr
  :: (RedisCtx m f)
  => ByteString -- ^ destkey
  -> [ByteString] -- ^ srckeys
  -> m (f Integer)
bitopOr dst srcs = bitop "OR" (dst : srcs)

bitopXor
  :: (RedisCtx m f)
  => ByteString -- ^ destkey
  -> [ByteString] -- ^ srckeys
  -> m (f Integer)
bitopXor dst srcs = bitop "XOR" (dst : srcs)

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

-- setRange
--   ::
-- setRange = sendRequest (["SET"] ++ [encode key] ++ [encode value] ++ )
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

-- |Options for the 'migrate' command.
data MigrateOpts = MigrateOpts
  { migrateCopy :: Bool
  , migrateReplace :: Bool
  } deriving (Show, Eq)

-- |Redis default 'MigrateOpts'. Equivalent to omitting all optional parameters.
--
-- @
-- MigrateOpts
--     { migrateCopy    = False -- remove the key from the local instance
--     , migrateReplace = False -- don't replace existing key on the remote instance
--     }
-- @
--
defaultMigrateOpts :: MigrateOpts
defaultMigrateOpts = MigrateOpts {migrateCopy = False, migrateReplace = False}

migrateMultiple
  :: (RedisCtx m f)
  => ByteString -- ^ host
  -> ByteString -- ^ port
  -> Integer -- ^ destinationDb
  -> Integer -- ^ timeout
  -> MigrateOpts
  -> [ByteString] -- ^ keys
  -> m (f Status)
migrateMultiple host port destinationDb timeout MigrateOpts {..} keys =
  sendRequest $
  concat
    [ ["MIGRATE", host, port, empty, encode destinationDb, encode timeout]
    , copy
    , replace
    , keys
    ]
  where
    copy = ["COPY" | migrateCopy]
    replace = ["REPLACE" | migrateReplace]

restore
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> Integer -- ^ timeToLive
  -> ByteString -- ^ serializedValue
  -> m (f Status)
restore key timeToLive serializedValue =
  sendRequest ["RESTORE", key, encode timeToLive, serializedValue]

restoreReplace
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> Integer -- ^ timeToLive
  -> ByteString -- ^ serializedValue
  -> m (f Status)
restoreReplace key timeToLive serializedValue =
  sendRequest ["RESTORE", key, encode timeToLive, serializedValue, "REPLACE"]

set
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> ByteString -- ^ value
  -> m (f Status)
set key value = sendRequest ["SET", key, value]

data Condition
  = Nx
  | Xx
  deriving (Show, Eq)

instance RedisArg Condition where
  encode Nx = "NX"
  encode Xx = "XX"

data SetOpts = SetOpts
  { setSeconds :: Maybe Integer
  , setMilliseconds :: Maybe Integer
  , setCondition :: Maybe Condition
  } deriving (Show, Eq)

setOpts
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> ByteString -- ^ value
  -> SetOpts
  -> m (f Status)
setOpts key value SetOpts {..} =
  sendRequest $ concat [["SET", key, value], ex, px, condition]
  where
    ex = maybe [] (\s -> ["EX", encode s]) setSeconds
    px = maybe [] (\s -> ["PX", encode s]) setMilliseconds
    condition = map encode $ maybeToList setCondition

data DebugMode
  = Yes
  | Sync
  | No
  deriving (Show, Eq)

instance RedisArg DebugMode where
  encode Yes = "YES"
  encode Sync = "SYNC"
  encode No = "NO"

scriptDebug
  :: (RedisCtx m f)
  => DebugMode -> m (f Bool)
scriptDebug mode = sendRequest ["SCRIPT DEBUG", encode mode]

zadd
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> [(Double, ByteString)] -- ^ scoreMember
  -> m (f Integer)
zadd key scoreMembers = zaddOpts key scoreMembers defaultZaddOpts

data ZaddOpts = ZaddOpts
  { zaddCondition :: Maybe Condition
  , zaddChange :: Bool
  , zaddIncrement :: Bool
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
defaultZaddOpts =
  ZaddOpts {zaddCondition = Nothing, zaddChange = False, zaddIncrement = False}

zaddOpts
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> [(Double, ByteString)] -- ^ scoreMember
  -> ZaddOpts -- ^ options
  -> m (f Integer)
zaddOpts key scoreMembers ZaddOpts {..} =
  sendRequest $ concat [["ZADD", key], condition, change, increment, scores]
  where
    scores = concatMap (\(x, y) -> [encode x, encode y]) scoreMembers
    condition = map encode $ maybeToList zaddCondition
    change = ["CH" | zaddChange]
    increment = ["INCR" | zaddIncrement]

data ReplyMode
  = On
  | Off
  | Skip
  deriving (Show, Eq)

instance RedisArg ReplyMode where
  encode On = "ON"
  encode Off = "OFF"
  encode Skip = "SKIP"

clientReply
  :: (RedisCtx m f)
  => ReplyMode -> m (f Bool)
clientReply mode = sendRequest ["CLIENT REPLY", encode mode]

srandmember
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> m (f (Maybe ByteString))
srandmember key = sendRequest ["SRANDMEMBER", key]

srandmemberN
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> Integer -- ^ count
  -> m (f [ByteString])
srandmemberN key count = sendRequest ["SRANDMEMBER", key, encode count]

spop
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> m (f (Maybe ByteString))
spop key = sendRequest ["SPOP", key]

spopN
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> Integer -- ^ count
  -> m (f [ByteString])
spopN key count = sendRequest ["SPOP", key, encode count]

info
  :: (RedisCtx m f)
  => m (f ByteString)
info = sendRequest ["INFO"]

infoSection
  :: (RedisCtx m f)
  => ByteString -- ^ section
  -> m (f ByteString)
infoSection section = sendRequest ["INFO", section]

exists
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> m (f Bool)
exists key = sendRequest ["EXISTS", key]

newtype Cursor =
  Cursor ByteString
  deriving (Show, Eq)

instance RedisArg Cursor where
  encode (Cursor c) = encode c

instance RedisResult Cursor where
  decode (Bulk (Just s)) = Right $ Cursor s
  decode r = Left r

cursor0 :: Cursor
cursor0 = Cursor "0"

scan
  :: (RedisCtx m f)
  => Cursor -> m (f (Cursor, [ByteString])) -- ^ next cursor and values
scan cursor = scanOpts cursor defaultScanOpts

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
defaultScanOpts = ScanOpts {scanMatch = Nothing, scanCount = Nothing}

scanOpts
  :: (RedisCtx m f)
  => Cursor
  -> ScanOpts
  -> m (f (Cursor, [ByteString])) -- ^ next cursor and values
scanOpts cursor opts = sendRequest $ addScanOpts ["SCAN", encode cursor] opts

addScanOpts
  :: [ByteString] -- ^ main part of scan command
  -> ScanOpts
  -> [ByteString]
addScanOpts cmd ScanOpts {..} = concat [cmd, match, count]
  where
    prepend x y = [x, y]
    match = maybe [] (prepend "MATCH") scanMatch
    count = maybe [] ((prepend "COUNT") . encode) scanCount

sscan
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> Cursor
  -> m (f (Cursor, [ByteString])) -- ^ next cursor and values
sscan key cursor = sscanOpts key cursor defaultScanOpts

sscanOpts
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> Cursor
  -> ScanOpts
  -> m (f (Cursor, [ByteString])) -- ^ next cursor and values
sscanOpts key cursor opts =
  sendRequest $ addScanOpts ["SSCAN", key, encode cursor] opts

hscan
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> Cursor
  -> m (f (Cursor, [(ByteString, ByteString)])) -- ^ next cursor and values
hscan key cursor = hscanOpts key cursor defaultScanOpts

hscanOpts
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> Cursor
  -> ScanOpts
  -> m (f (Cursor, [(ByteString, ByteString)])) -- ^ next cursor and values
hscanOpts key cursor opts =
  sendRequest $ addScanOpts ["HSCAN", key, encode cursor] opts

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
zscanOpts key cursor opts =
  sendRequest $ addScanOpts ["ZSCAN", key, encode cursor] opts

data RangeLex a
  = Incl a
  | Excl a
  | Minr
  | Maxr

instance RedisArg a =>
         RedisArg (RangeLex a) where
  encode (Incl bs) = "[" `append` encode bs
  encode (Excl bs) = "(" `append` encode bs
  encode Minr = "-"
  encode Maxr = "+"

zrangebylex
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> RangeLex ByteString -- ^ min
  -> RangeLex ByteString -- ^ max
  -> m (f [ByteString])
zrangebylex key min max =
  sendRequest ["ZRANGEBYLEX", encode key, encode min, encode max]

zrangebylexLimit
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> RangeLex ByteString -- ^ min
  -> RangeLex ByteString -- ^ max
  -> Integer -- ^ offset
  -> Integer -- ^ count
  -> m (f [ByteString])
zrangebylexLimit key min max offset count =
  sendRequest
    [ "ZRANGEBYLEX"
    , encode key
    , encode min
    , encode max
    , "LIMIT"
    , encode offset
    , encode count
    ]

data TrimOpts
  = NoArgs
  | Maxlen Integer
  | ApproxMaxlen Integer

xaddOpts
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> ByteString -- ^ id
  -> [(ByteString, ByteString)] -- ^ (field, value)
  -> TrimOpts
  -> m (f ByteString)
xaddOpts key entryId fieldValues opts =
  sendRequest $ ["XADD", key, entryId] ++ optArgs ++ fieldArgs
  where
    fieldArgs = concatMap (\(x, y) -> [x, y]) fieldValues
    optArgs =
      case opts of
        NoArgs -> []
        Maxlen max -> ["MAXLEN", encode max]
        ApproxMaxlen max -> ["MAXLEN", "~", encode max]

xadd
  :: (RedisCtx m f)
  => ByteString -- ^ stream
  -> ByteString -- ^ id
  -> [(ByteString, ByteString)] -- ^ (field, value)
  -> m (f ByteString)
xadd key entryId fieldValues = xaddOpts key entryId fieldValues NoArgs

data StreamsRecord = StreamsRecord
  { recordId :: ByteString
  , keyValues :: [(ByteString, ByteString)]
  } deriving (Show, Eq)

instance RedisResult StreamsRecord where
  decode (MultiBulk (Just [SingleLine recordId, MultiBulk (Just rawKeyValues)])) = do
    keyValuesList <- mapM decode rawKeyValues
    let keyValues = decodeKeyValues keyValuesList
    return StreamsRecord {..}
    where
      decodeKeyValues :: [ByteString] -> [(ByteString, ByteString)]
      decodeKeyValues bs = map (\[x, y] -> (x, y)) $ chunksOfTwo bs
      chunksOfTwo (x:y:rest) = [x, y] : chunksOfTwo rest
      chunksOfTwo _ = []
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
defaultXreadOpts = XReadOpts {block = Nothing, recordCount = Nothing}

data XReadResponse = XReadResponse
  { stream :: ByteString
  , records :: [StreamsRecord]
  } deriving (Show, Eq)

instance RedisResult XReadResponse where
  decode (MultiBulk (Just [Bulk (Just stream), MultiBulk (Just rawRecords)])) = do
    records <- mapM decode rawRecords
    return XReadResponse {..}
  decode a = Left a

xreadOpts
  :: (RedisCtx m f)
  => [(ByteString, ByteString)] -- ^ (stream, id) pairs
  -> XReadOpts -- ^ Options
  -> m (f (Maybe [XReadResponse]))
xreadOpts streamsAndIds opts =
  sendRequest $ ["XREAD"] ++ (internalXreadArgs streamsAndIds opts)

internalXreadArgs :: [(ByteString, ByteString)] -> XReadOpts -> [ByteString]
internalXreadArgs streamsAndIds XReadOpts {..} =
  concat [blockArgs, countArgs, ["STREAMS"], streams, recordIds]
  where
    blockArgs = maybe [] (\blockMillis -> ["BLOCK", encode blockMillis]) block
    countArgs =
      maybe [] (\countRecords -> ["COUNT", encode countRecords]) recordCount
    streams = map (\(stream, _) -> stream) streamsAndIds
    recordIds = map (\(_, recordId) -> recordId) streamsAndIds

xread
  :: (RedisCtx m f)
  => [(ByteString, ByteString)] -- ^ (stream, id) pairs
  -> m (f (Maybe [XReadResponse]))
xread streamsAndIds = xreadOpts streamsAndIds defaultXreadOpts

xreadGroupOpts
  :: (RedisCtx m f)
  => ByteString -- ^ group name
  -> ByteString -- ^ consumer name
  -> [(ByteString, ByteString)] -- ^ (stream, id) pairs
  -> XReadOpts -- ^ Options
  -> m (f (Maybe [XReadResponse]))
xreadGroupOpts groupName consumerName streamsAndIds opts =
  sendRequest $
  ["XREADGROUP", "GROUP", groupName, consumerName] ++
  (internalXreadArgs streamsAndIds opts)

xreadGroup
  :: (RedisCtx m f)
  => ByteString -- ^ group name
  -> ByteString -- ^ consumer name
  -> [(ByteString, ByteString)] -- ^ (stream, id) pairs
  -> m (f (Maybe [XReadResponse]))
xreadGroup groupName consumerName streamsAndIds =
  xreadGroupOpts groupName consumerName streamsAndIds defaultXreadOpts

xgroupCreate
  :: (RedisCtx m f)
  => ByteString -- ^ stream
  -> ByteString -- ^ group name
  -> ByteString -- ^ start ID
  -> m (f Bool)
xgroupCreate stream groupName startId =
  sendRequest $ ["XGROUP", "CREATE", stream, groupName, startId]

xgroupSetId
  :: (RedisCtx m f)
  => ByteString -- ^ stream
  -> ByteString -- ^ group
  -> ByteString -- ^ id
  -> m (f Status)
xgroupSetId stream group messageId =
  sendRequest ["XGROUP", "SETID", stream, group, messageId]

xgroupDelConsumer
  :: (RedisCtx m f)
  => ByteString -- ^ stream
  -> ByteString -- ^ group
  -> ByteString -- ^ consumer
  -> m (f Integer)
xgroupDelConsumer stream group consumer =
  sendRequest ["XGROUP", "DELCONSUMER", stream, group, consumer]

xgroupDestroy
  :: (RedisCtx m f)
  => ByteString -- ^ stream
  -> ByteString -- ^ group
  -> m (f Bool)
xgroupDestroy stream group = sendRequest ["XGROUP", "DESTROY", stream, group]

xack
  :: (RedisCtx m f)
  => ByteString -- ^ stream
  -> ByteString -- ^ group name
  -> ByteString -- ^ message ID
  -> m (f Integer)
xack stream groupName messageId =
  sendRequest ["XACK", stream, groupName, messageId]

xrange
  :: (RedisCtx m f)
  => ByteString -- ^ stream
  -> ByteString -- ^ start
  -> ByteString -- ^ end
  -> Maybe Integer -- ^ COUNT
  -> m (f [StreamsRecord])
xrange stream start end count =
  sendRequest $ ["XRANGE", stream, start, end] ++ countArgs
  where
    countArgs = maybe [] (\c -> ["COUNT", encode c]) count

xrevRange
  :: (RedisCtx m f)
  => ByteString -- ^ stream
  -> ByteString -- ^ end
  -> ByteString -- ^ start
  -> Maybe Integer -- ^ COUNT
  -> m (f [StreamsRecord])
xrevRange stream end start count =
  sendRequest $ ["XREVRANGE", stream, end, start] ++ countArgs
  where
    countArgs = maybe [] (\c -> ["COUNT", encode c]) count

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
  decode (MultiBulk (Just [Integer numPendingMessages, SingleLine smallestPendingMessageId, SingleLine largestPendingMessageId, MultiBulk (Just [MultiBulk (Just rawGroupsAndCounts)])])) = do
    let groupsAndCounts = chunksOfTwo rawGroupsAndCounts
    numPendingMessagesByconsumer <- decodeGroupsAndCounts groupsAndCounts
    return XPendingSummaryResponse {..}
    where
      decodeGroupsAndCounts :: [(Reply, Reply)]
                            -> Either Reply [(ByteString, Integer)]
      decodeGroupsAndCounts bs = sequence $ map decodeGroupCount bs
      decodeGroupCount :: (Reply, Reply) -> Either Reply (ByteString, Integer)
      decodeGroupCount (x, y) = do
        decodedX <- decode x
        decodedY <- decode y
        return (decodedX, decodedY)
      chunksOfTwo (x:y:rest) = (x, y) : chunksOfTwo rest
      chunksOfTwo _ = []
  decode a = Left a

xpendingSummary
  :: (RedisCtx m f)
  => ByteString -- ^ stream
  -> ByteString -- ^ group
  -> Maybe ByteString -- ^ consumer
  -> m (f XPendingSummaryResponse)
xpendingSummary stream group consumer =
  sendRequest $ ["XPENDING", stream, group] ++ consumerArg
  where
    consumerArg = maybe [] (\c -> [c]) consumer

data XPendingDetailRecord = XPendingDetailRecord
  { messageId :: ByteString
  , consumer :: ByteString
  , millisSinceLastDelivered :: Integer
  , numTimesDelivered :: Integer
  } deriving (Show, Eq)

instance RedisResult XPendingDetailRecord where
  decode (MultiBulk (Just [SingleLine messageId, Bulk (Just consumer), Integer millisSinceLastDelivered, Integer numTimesDelivered])) =
    Right XPendingDetailRecord {..}
  decode a = Left a

xpendingDetail
  :: (RedisCtx m f)
  => ByteString -- ^ stream
  -> ByteString -- ^ group
  -> ByteString -- ^ startId
  -> ByteString -- ^ endId
  -> Integer -- ^ count
  -> Maybe ByteString -- ^ consumer
  -> m (f [XPendingDetailRecord])
xpendingDetail stream group startId endId count consumer =
  sendRequest $
  ["XPENDING", stream, group, startId, endId, encode count] ++ consumerArg
  where
    consumerArg = maybe [] (\c -> [c]) consumer

data XClaimOpts = XClaimOpts
  { xclaimIdle :: Maybe Integer
  , xclaimTime :: Maybe Integer
  , xclaimRetryCount :: Maybe Integer
  , xclaimForce :: Bool
  } deriving (Show, Eq)

defaultXClaimOpts :: XClaimOpts
defaultXClaimOpts =
  XClaimOpts
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
xclaimRequest stream group consumer minIdleTime XClaimOpts {..} messageIds =
  ["XCLAIM", stream, group, consumer, encode minIdleTime] ++
  (map encode messageIds) ++ optArgs
  where
    optArgs = idleArg ++ timeArg ++ retryCountArg ++ forceArg
    idleArg = optArg "IDLE" xclaimIdle
    timeArg = optArg "TIME" xclaimTime
    retryCountArg = optArg "RETRYCOUNT" xclaimRetryCount
    forceArg =
      if xclaimForce
        then ["FORCE"]
        else []
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
xclaim stream group consumer minIdleTime opts messageIds =
  sendRequest $ xclaimRequest stream group consumer minIdleTime opts messageIds

xclaimJustIds
  :: (RedisCtx m f)
  => ByteString -- ^ stream
  -> ByteString -- ^ group
  -> ByteString -- ^ consumer
  -> Integer -- ^ min idle time
  -> XClaimOpts -- ^ optional arguments
  -> [ByteString] -- ^ message IDs
  -> m (f [ByteString])
xclaimJustIds stream group consumer minIdleTime opts messageIds =
  sendRequest $
  (xclaimRequest stream group consumer minIdleTime opts messageIds) ++
  ["JUSTID"]

data XInfoConsumersResponse = XInfoConsumersResponse
  { xinfoConsumerName :: ByteString
  , xinfoConsumerNumPendingMessages :: Integer
  , xinfoConsumerIdleTime :: Integer
  } deriving (Show, Eq)

instance RedisResult XInfoConsumersResponse where
  decode (MultiBulk (Just [SingleLine "name", Bulk (Just xinfoConsumerName), SingleLine "pending", Integer xinfoConsumerNumPendingMessages, SingleLine "idle", Integer xinfoConsumerIdleTime])) =
    Right XInfoConsumersResponse {..}
  decode a = Left a

xinfoConsumers
  :: (RedisCtx m f)
  => ByteString -- ^ stream
  -> ByteString -- ^ group
  -> m (f [XInfoConsumersResponse])
xinfoConsumers stream group =
  sendRequest $ ["XINFO", "CONSUMERS", stream, group]

data XInfoGroupsResponse = XInfoGroupsResponse
  { xinfoGroupsGroupName :: ByteString
  , xinfoGroupsNumConsumers :: Integer
  , xinfoGroupsNumPendingMessages :: Integer
  , xinfoGroupsLastDeliveredMessageId :: ByteString
  } deriving (Show, Eq)

instance RedisResult XInfoGroupsResponse where
  decode (MultiBulk (Just [SingleLine "name", Bulk (Just xinfoGroupsGroupName), SingleLine "consumers", Integer xinfoGroupsNumConsumers, SingleLine "pending", Integer xinfoGroupsNumPendingMessages, SingleLine "last-delivered-id", SingleLine xinfoGroupsLastDeliveredMessageId])) =
    Right XInfoGroupsResponse {..}
  decode a = Left a

xinfoGroups
  :: (RedisCtx m f)
  => ByteString -- ^ stream
  -> m (f [XInfoGroupsResponse])
xinfoGroups stream = sendRequest ["XINFO", "GROUPS", stream]

data XInfoStreamResponse = XInfoStreamResponse
  { xinfoStreamLength :: Integer
  , xinfoStreamRadixTreeKeys :: Integer
  , xinfoStreamRadixTreeNodes :: Integer
  , xinfoStreamNumGroups :: Integer
  , xinfoStreamLastEntryId :: ByteString
  , xinfoStreamFirstEntry :: StreamsRecord
  , xinfoStreamLastEntry :: StreamsRecord
  } deriving (Show, Eq)

instance RedisResult XInfoStreamResponse where
  decode (MultiBulk (Just [SingleLine "length", Integer xinfoStreamLength, SingleLine "radix-tree-keys", Integer xinfoStreamRadixTreeKeys, SingleLine "radix-tree-nodes", Integer xinfoStreamRadixTreeNodes, SingleLine "groups", Integer xinfoStreamNumGroups, SingleLine "last-generated-id", SingleLine xinfoStreamLastEntryId, SingleLine "first-entry", rawFirstEntry, SingleLine "last-entry", rawLastEntry])) = do
    xinfoStreamFirstEntry <- decode rawFirstEntry
    xinfoStreamLastEntry <- decode rawLastEntry
    return XInfoStreamResponse {..}
  decode a = Left a

xinfoStream
  :: (RedisCtx m f)
  => ByteString -- ^ stream
  -> m (f XInfoStreamResponse)
xinfoStream stream = sendRequest ["XINFO", "STREAM", stream]

xdel
  :: (RedisCtx m f)
  => ByteString -- ^ stream
  -> [ByteString] -- ^ message IDs
  -> m (f Integer)
xdel stream messageIds = sendRequest $ ["XDEL", stream] ++ messageIds

xtrim
  :: (RedisCtx m f)
  => ByteString -- ^ stream
  -> TrimOpts
  -> m (f Integer)
xtrim stream opts = sendRequest $ ["XTRIM", stream] ++ optArgs
  where
    optArgs =
      case opts of
        NoArgs -> []
        Maxlen max -> ["MAXLEN", encode max]
        ApproxMaxlen max -> ["MAXLEN", "~", encode max]

geoadd
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> [(Double, Double, ByteString)] -- ^ (latitude, longitude, member)
  -> m (f Integer)
geoadd key locationValues = sendRequest $ ["GEOADD", key] ++ fieldArgs
  where
    fieldArgs = concatMap (\(x, y, m) -> [encode x, encode y, m]) locationValues

geohash
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> [ByteString] -- ^ member
  -> m (f [ByteString])
geohash key members = sendRequest $ ["GEOHASH", key] ++ (map encode members)

geodist
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> ByteString -- ^ member1
  -> ByteString -- ^ member2
  -> ByteString -- ^ unit
  -> m (f ByteString)
geodist key member1 member2 unit =
  sendRequest $ ["GEODIST", key, member1, member2, unit]

geopos
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> [ByteString] -- ^ members
  -> m (f [(ByteString, ByteString)])
geopos key members = sendRequest $ ["GEOPOS", key] ++ (map encode members)

georadius
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> Double -- ^ longitude
  -> Double -- ^ latitude
  -> Double -- ^ radius
  -> ByteString -- ^ unit
  -> GeoRadiusOpts
  -> m (f [(ByteString, ByteString)])
georadius key lon lat radius unit opts = sendRequest $ ["GEORADIUS", key, encode lon, encode lat, encode radius, unit]

georadiusbymember
  :: (RedisCtx m f)
  => ByteString -- ^ key
  -> ByteString -- ^ member
  -> Double -- ^ radius
  -> ByteString -- ^ unit
  -> GeoRadiusOpts
  -> m (f [(ByteString, ByteString)])
georadiusbymember key member radius unit opts = sendRequest $ ["GEORADIUSBYMEMBER", key, member, encode radius, unit]