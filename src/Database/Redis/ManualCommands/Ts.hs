{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Database.Redis.ManualCommands.Ts where

import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as Char8
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE

import Database.Redis.Core
import Database.Redis.Protocol
import Database.Redis.Types

data TsSample = TsSample
    { tsSampleTimestamp :: Integer
    , tsSampleValue :: Double
    } deriving (Show, Eq)

instance RedisResult TsSample where
    decode (MultiBulk (Just [timestampReply, valueReply])) =
        TsSample <$> decode timestampReply <*> decode valueReply
    decode response = Left response

data TsEncoding
    = TsUncompressed
    | TsCompressed
    deriving (Show, Eq)

instance RedisArg TsEncoding where
    encode TsUncompressed = "UNCOMPRESSED"
    encode TsCompressed = "COMPRESSED"

data TsDuplicatePolicy
    = TsDuplicateBlock
    | TsDuplicateFirst
    | TsDuplicateLast
    | TsDuplicateMin
    | TsDuplicateMax
    | TsDuplicateSum
    deriving (Show, Eq)

instance RedisArg TsDuplicatePolicy where
    encode TsDuplicateBlock = "BLOCK"
    encode TsDuplicateFirst = "FIRST"
    encode TsDuplicateLast = "LAST"
    encode TsDuplicateMin = "MIN"
    encode TsDuplicateMax = "MAX"
    encode TsDuplicateSum = "SUM"

data TsIgnore = TsIgnore
    { tsIgnoreMaxTimeDiff :: Integer
    , tsIgnoreMaxValDiff :: Double
    } deriving (Show, Eq)

data TsCreateOpts = TsCreateOpts
    { tsCreateRetention :: Maybe Integer
    , tsCreateEncoding :: Maybe TsEncoding
    , tsCreateChunkSize :: Maybe Integer
    , tsCreateDuplicatePolicy :: Maybe TsDuplicatePolicy
    , tsCreateIgnore :: Maybe TsIgnore
    , tsCreateLabels :: [(ByteString, ByteString)]
    } deriving (Show, Eq)

defaultTsCreateOpts :: TsCreateOpts
defaultTsCreateOpts = TsCreateOpts
    { tsCreateRetention = Nothing
    , tsCreateEncoding = Nothing
    , tsCreateChunkSize = Nothing
    , tsCreateDuplicatePolicy = Nothing
    , tsCreateIgnore = Nothing
    , tsCreateLabels = []
    }

data TsAlterOpts = TsAlterOpts
    { tsAlterRetention :: Maybe Integer
    , tsAlterChunkSize :: Maybe Integer
    , tsAlterDuplicatePolicy :: Maybe TsDuplicatePolicy
    , tsAlterLabels :: [(ByteString, ByteString)]
    } deriving (Show, Eq)

defaultTsAlterOpts :: TsAlterOpts
defaultTsAlterOpts = TsAlterOpts
    { tsAlterRetention = Nothing
    , tsAlterChunkSize = Nothing
    , tsAlterDuplicatePolicy = Nothing
    , tsAlterLabels = []
    }

data TsAddOpts = TsAddOpts
    { tsAddRetention :: Maybe Integer
    , tsAddEncoding :: Maybe TsEncoding
    , tsAddChunkSize :: Maybe Integer
    , tsAddOnDuplicate :: Maybe TsDuplicatePolicy
    , tsAddIgnore :: Maybe TsIgnore
    , tsAddLabels :: [(ByteString, ByteString)]
    } deriving (Show, Eq)

defaultTsAddOpts :: TsAddOpts
defaultTsAddOpts = TsAddOpts
    { tsAddRetention = Nothing
    , tsAddEncoding = Nothing
    , tsAddChunkSize = Nothing
    , tsAddOnDuplicate = Nothing
    , tsAddIgnore = Nothing
    , tsAddLabels = []
    }

data TsIncrByOpts = TsIncrByOpts
    { tsIncrByTimestamp :: Maybe ByteString
    , tsIncrByRetention :: Maybe Integer
    , tsIncrByUncompressed :: Bool
    , tsIncrByChunkSize :: Maybe Integer
    , tsIncrByDuplicatePolicy :: Maybe TsDuplicatePolicy
    , tsIncrByIgnore :: Maybe TsIgnore
    , tsIncrByLabels :: [(ByteString, ByteString)]
    } deriving (Show, Eq)

defaultTsIncrByOpts :: TsIncrByOpts
defaultTsIncrByOpts = TsIncrByOpts
    { tsIncrByTimestamp = Nothing
    , tsIncrByRetention = Nothing
    , tsIncrByUncompressed = False
    , tsIncrByChunkSize = Nothing
    , tsIncrByDuplicatePolicy = Nothing
    , tsIncrByIgnore = Nothing
    , tsIncrByLabels = []
    }

data TsGetOpts = TsGetOpts
    { tsGetLatest :: Bool
    } deriving (Show, Eq)

defaultTsGetOpts :: TsGetOpts
defaultTsGetOpts = TsGetOpts
    { tsGetLatest = False
    }

data TsAggregator
    = TsAggAvg
    | TsAggFirst
    | TsAggLast
    | TsAggMin
    | TsAggMax
    | TsAggSum
    | TsAggRange
    | TsAggCount
    | TsAggStdP
    | TsAggStdS
    | TsAggVarP
    | TsAggVarS
    | TsAggTwa
    | TsAggCountNaN
    | TsAggCountAll
    deriving (Show, Eq)

instance RedisArg TsAggregator where
    encode TsAggAvg = "avg"
    encode TsAggFirst = "first"
    encode TsAggLast = "last"
    encode TsAggMin = "min"
    encode TsAggMax = "max"
    encode TsAggSum = "sum"
    encode TsAggRange = "range"
    encode TsAggCount = "count"
    encode TsAggStdP = "std.p"
    encode TsAggStdS = "std.s"
    encode TsAggVarP = "var.p"
    encode TsAggVarS = "var.s"
    encode TsAggTwa = "twa"
    encode TsAggCountNaN = "countnan"
    encode TsAggCountAll = "countall"

newtype TsAggregators = TsAggregators
    { unTsAggregators :: NonEmpty TsAggregator
    } deriving (Show, Eq)

instance RedisArg TsAggregators where
    encode = Char8.intercalate "," . map encode . NE.toList . unTsAggregators

data TsBucketTimestamp
    = TsBucketStart
    | TsBucketEnd
    | TsBucketMid
    deriving (Show, Eq)

instance RedisArg TsBucketTimestamp where
    encode TsBucketStart = "-"
    encode TsBucketEnd = "+"
    encode TsBucketMid = "~"

data TsAggregationOpts = TsAggregationOpts
    { tsAggregationAlign :: Maybe ByteString
    , tsAggregationType :: TsAggregators
    , tsAggregationBucketDuration :: Integer
    , tsAggregationBucketTimestamp :: Maybe TsBucketTimestamp
    , tsAggregationEmpty :: Bool
    } deriving (Show, Eq)

data TsRangeOpts = TsRangeOpts
    { tsRangeLatest :: Bool
    , tsRangeFilterByTs :: [Integer]
    , tsRangeFilterByValue :: Maybe (Double, Double)
    , tsRangeCount :: Maybe Integer
    , tsRangeAggregation :: Maybe TsAggregationOpts
    } deriving (Show, Eq)

defaultTsRangeOpts :: TsRangeOpts
defaultTsRangeOpts = TsRangeOpts
    { tsRangeLatest = False
    , tsRangeFilterByTs = []
    , tsRangeFilterByValue = Nothing
    , tsRangeCount = Nothing
    , tsRangeAggregation = Nothing
    }

data TsLabelSelection
    = TsWithLabels
    | TsSelectedLabels (NonEmpty ByteString)
    deriving (Show, Eq)

data TsGroupByReduce = TsGroupByReduce
    { tsGroupByLabel :: ByteString
    , tsGroupByReducer :: TsAggregator
    } deriving (Show, Eq)

data TsMGetOpts = TsMGetOpts
    { tsMGetLatest :: Bool
    , tsMGetLabels :: Maybe TsLabelSelection
    } deriving (Show, Eq)

defaultTsMGetOpts :: TsMGetOpts
defaultTsMGetOpts = TsMGetOpts
    { tsMGetLatest = False
    , tsMGetLabels = Nothing
    }

data TsMRangeOpts = TsMRangeOpts
    { tsMRangeLatest :: Bool
    , tsMRangeFilterByTs :: [Integer]
    , tsMRangeFilterByValue :: Maybe (Double, Double)
    , tsMRangeLabels :: Maybe TsLabelSelection
    , tsMRangeCount :: Maybe Integer
    , tsMRangeAggregation :: Maybe TsAggregationOpts
    , tsMRangeGroupByReduce :: Maybe TsGroupByReduce
    } deriving (Show, Eq)

defaultTsMRangeOpts :: TsMRangeOpts
defaultTsMRangeOpts = TsMRangeOpts
    { tsMRangeLatest = False
    , tsMRangeFilterByTs = []
    , tsMRangeFilterByValue = Nothing
    , tsMRangeLabels = Nothing
    , tsMRangeCount = Nothing
    , tsMRangeAggregation = Nothing
    , tsMRangeGroupByReduce = Nothing
    }

data TsInfoOpts
    = TsInfoDefault
    | TsInfoDebug
    deriving (Show, Eq)

tsLabelsToArgs :: [(ByteString, ByteString)] -> [ByteString]
tsLabelsToArgs [] = []
tsLabelsToArgs labels = "LABELS" : concatMap (\(k, v) -> [k, v]) labels

tsIgnoreToArgs :: TsIgnore -> [ByteString]
tsIgnoreToArgs TsIgnore{..} =
    ["IGNORE", encode tsIgnoreMaxTimeDiff, encode tsIgnoreMaxValDiff]

tsCreateOptsToArgs :: TsCreateOpts -> [ByteString]
tsCreateOptsToArgs TsCreateOpts{..} =
    retentionArg ++ encodingArg ++ chunkSizeArg ++ duplicatePolicyArg ++ ignoreArg ++ tsLabelsToArgs tsCreateLabels
  where
    retentionArg = maybe [] (\retention -> ["RETENTION", encode retention]) tsCreateRetention
    encodingArg = maybe [] (\encoding -> ["ENCODING", encode encoding]) tsCreateEncoding
    chunkSizeArg = maybe [] (\size -> ["CHUNK_SIZE", encode size]) tsCreateChunkSize
    duplicatePolicyArg = maybe [] (\policy -> ["DUPLICATE_POLICY", encode policy]) tsCreateDuplicatePolicy
    ignoreArg = maybe [] tsIgnoreToArgs tsCreateIgnore

tsAlterOptsToArgs :: TsAlterOpts -> [ByteString]
tsAlterOptsToArgs TsAlterOpts{..} =
    retentionArg ++ chunkSizeArg ++ duplicatePolicyArg ++ tsLabelsToArgs tsAlterLabels
  where
    retentionArg = maybe [] (\retention -> ["RETENTION", encode retention]) tsAlterRetention
    chunkSizeArg = maybe [] (\size -> ["CHUNK_SIZE", encode size]) tsAlterChunkSize
    duplicatePolicyArg = maybe [] (\policy -> ["DUPLICATE_POLICY", encode policy]) tsAlterDuplicatePolicy

tsAddOptsToArgs :: TsAddOpts -> [ByteString]
tsAddOptsToArgs TsAddOpts{..} =
    retentionArg ++ encodingArg ++ chunkSizeArg ++ onDuplicateArg ++ ignoreArg ++ tsLabelsToArgs tsAddLabels
  where
    retentionArg = maybe [] (\retention -> ["RETENTION", encode retention]) tsAddRetention
    encodingArg = maybe [] (\encoding -> ["ENCODING", encode encoding]) tsAddEncoding
    chunkSizeArg = maybe [] (\size -> ["CHUNK_SIZE", encode size]) tsAddChunkSize
    onDuplicateArg = maybe [] (\policy -> ["ON_DUPLICATE", encode policy]) tsAddOnDuplicate
    ignoreArg = maybe [] tsIgnoreToArgs tsAddIgnore

tsIncrByOptsToArgs :: TsIncrByOpts -> [ByteString]
tsIncrByOptsToArgs TsIncrByOpts{..} =
    timestampArg ++ retentionArg ++ uncompressedArg ++ chunkSizeArg ++ duplicatePolicyArg ++ ignoreArg ++ tsLabelsToArgs tsIncrByLabels
  where
    timestampArg = maybe [] (\timestamp -> ["TIMESTAMP", timestamp]) tsIncrByTimestamp
    retentionArg = maybe [] (\retention -> ["RETENTION", encode retention]) tsIncrByRetention
    uncompressedArg = ["UNCOMPRESSED" | tsIncrByUncompressed]
    chunkSizeArg = maybe [] (\size -> ["CHUNK_SIZE", encode size]) tsIncrByChunkSize
    duplicatePolicyArg = maybe [] (\policy -> ["DUPLICATE_POLICY", encode policy]) tsIncrByDuplicatePolicy
    ignoreArg = maybe [] tsIgnoreToArgs tsIncrByIgnore

tsAggregationToArgs :: TsAggregationOpts -> [ByteString]
tsAggregationToArgs TsAggregationOpts{..} =
    alignArg ++ ["AGGREGATION", encode tsAggregationType, encode tsAggregationBucketDuration] ++ bucketTimestampArg ++ emptyArg
  where
    alignArg = maybe [] (\align -> ["ALIGN", align]) tsAggregationAlign
    bucketTimestampArg = maybe [] (\bt -> ["BUCKETTIMESTAMP", encode bt]) tsAggregationBucketTimestamp
    emptyArg = ["EMPTY" | tsAggregationEmpty]

tsRangeOptsToArgs :: TsRangeOpts -> [ByteString]
tsRangeOptsToArgs TsRangeOpts{..} =
    latestArg ++ filterByTsArg ++ filterByValueArg ++ countArg ++ aggregationArg
  where
    latestArg = ["LATEST" | tsRangeLatest]
    filterByTsArg = ["FILTER_BY_TS" | not (null tsRangeFilterByTs)] ++ map encode tsRangeFilterByTs
    filterByValueArg = maybe [] (\(minValue, maxValue) -> ["FILTER_BY_VALUE", encode minValue, encode maxValue]) tsRangeFilterByValue
    countArg = maybe [] (\count -> ["COUNT", encode count]) tsRangeCount
    aggregationArg = maybe [] tsAggregationToArgs tsRangeAggregation

tsLabelSelectionToArgs :: TsLabelSelection -> [ByteString]
tsLabelSelectionToArgs TsWithLabels = ["WITHLABELS"]
tsLabelSelectionToArgs (TsSelectedLabels labels) = ["SELECTED_LABELS"] ++ NE.toList labels

tsMGetOptsToArgs :: TsMGetOpts -> [ByteString]
tsMGetOptsToArgs TsMGetOpts{..} =
    latestArg ++ labelsArg
  where
    latestArg = ["LATEST" | tsMGetLatest]
    labelsArg = maybe [] tsLabelSelectionToArgs tsMGetLabels

tsGroupByReduceToArgs :: TsGroupByReduce -> [ByteString]
tsGroupByReduceToArgs TsGroupByReduce{..} =
    ["GROUPBY", tsGroupByLabel, "REDUCE", encode tsGroupByReducer]

tsMRangeOptsToArgs :: TsMRangeOpts -> [ByteString]
tsMRangeOptsToArgs TsMRangeOpts{..} =
    latestArg ++ filterByTsArg ++ filterByValueArg ++ labelsArg ++ countArg ++ aggregationArg ++ groupByReduceArg
  where
    latestArg = ["LATEST" | tsMRangeLatest]
    filterByTsArg = ["FILTER_BY_TS" | not (null tsMRangeFilterByTs)] ++ map encode tsMRangeFilterByTs
    filterByValueArg = maybe [] (\(minValue, maxValue) -> ["FILTER_BY_VALUE", encode minValue, encode maxValue]) tsMRangeFilterByValue
    labelsArg = maybe [] tsLabelSelectionToArgs tsMRangeLabels
    countArg = maybe [] (\count -> ["COUNT", encode count]) tsMRangeCount
    aggregationArg = maybe [] tsAggregationToArgs tsMRangeAggregation
    groupByReduceArg = maybe [] tsGroupByReduceToArgs tsMRangeGroupByReduce

-- |Appends a sample to a time series (<https://redis.io/commands/ts.add>).
--
-- /O(M)/ when /M/ is the number of compaction rules, or /O(1)/ with no compaction
--
-- Since RedisTimeSeries 1.0.0
tsAdd
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> ByteString -- ^ Timestamp, or @*@ for the current server time.
    -> Double -- ^ Sample value.
    -> m (f Integer)
tsAdd key timestamp value = tsAddOpts key timestamp value defaultTsAddOpts

-- |Appends a sample to a time series (<https://redis.io/commands/ts.add>).
--
-- /O(M)/ when /M/ is the number of compaction rules, or /O(1)/ with no compaction
--
-- Since RedisTimeSeries 1.0.0
tsAddOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> ByteString -- ^ Timestamp, or @*@ for the current server time.
    -> Double -- ^ Sample value.
    -> TsAddOpts -- ^ Insertion options.
    -> m (f Integer)
tsAddOpts key timestamp value opts =
    sendRequest $ ["TS.ADD", key, timestamp, encode value] ++ tsAddOptsToArgs opts

-- |Update the retention, chunk size, duplicate policy, and labels of an existing time series (<https://redis.io/commands/ts.alter>).
--
-- /O(N)/ where /N/ is the number of labels requested to update
--
-- Since RedisTimeSeries 1.0.0
tsAlter
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> TsAlterOpts -- ^ Alteration options.
    -> m (f Status)
tsAlter key opts = sendRequest $ ["TS.ALTER", key] ++ tsAlterOptsToArgs opts

-- |Create a new time series (<https://redis.io/commands/ts.create>).
--
-- /O(1)/
--
-- Since RedisTimeSeries 1.0.0
tsCreate
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> m (f Status)
tsCreate key = tsCreateOpts key defaultTsCreateOpts

-- |Create a new time series (<https://redis.io/commands/ts.create>).
--
-- /O(1)/
--
-- Since RedisTimeSeries 1.0.0
tsCreateOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> TsCreateOpts -- ^ Creation options.
    -> m (f Status)
tsCreateOpts key opts = sendRequest $ ["TS.CREATE", key] ++ tsCreateOptsToArgs opts

-- |Create a compaction rule (<https://redis.io/commands/ts.createrule>).
--
-- /O(1)/
--
-- Since RedisTimeSeries 1.0.0
tsCreaterule
    :: (RedisCtx m f)
    => ByteString -- ^ Source time series key.
    -> ByteString -- ^ Destination time series key.
    -> TsAggregator -- ^ Aggregation function.
    -> Integer -- ^ Bucket duration in milliseconds.
    -> m (f Status)
tsCreaterule source destination aggregator bucketDuration =
    sendRequest ["TS.CREATERULE", source, destination, "AGGREGATION", encode aggregator, encode bucketDuration]

-- |Create a compaction rule with an aligned bucket timestamp (<https://redis.io/commands/ts.createrule>).
--
-- /O(1)/
--
-- Since RedisTimeSeries 1.8.0
tsCreateruleAlign
    :: (RedisCtx m f)
    => ByteString -- ^ Source time series key.
    -> ByteString -- ^ Destination time series key.
    -> TsAggregator -- ^ Aggregation function.
    -> Integer -- ^ Bucket duration in milliseconds.
    -> Integer -- ^ Alignment timestamp in milliseconds.
    -> m (f Status)
tsCreateruleAlign source destination aggregator bucketDuration alignTimestamp =
    sendRequest ["TS.CREATERULE", source, destination, "AGGREGATION", encode aggregator, encode bucketDuration, encode alignTimestamp]

-- |Decrease the value of the sample with the maximum timestamp, or create a new sample with a decremented value (<https://redis.io/commands/ts.decrby>).
--
-- /O(M)/ when /M/ is the number of compaction rules, or /O(1)/ with no compaction
--
-- Since RedisTimeSeries 1.0.0
tsDecrby
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> Double -- ^ Decrement amount.
    -> m (f Integer)
tsDecrby key value = tsDecrbyOpts key value defaultTsIncrByOpts

-- |Decrease the value of the sample with the maximum timestamp, or create a new sample with a decremented value (<https://redis.io/commands/ts.decrby>).
--
-- /O(M)/ when /M/ is the number of compaction rules, or /O(1)/ with no compaction
--
-- Since RedisTimeSeries 1.0.0
tsDecrbyOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> Double -- ^ Decrement amount.
    -> TsIncrByOpts -- ^ Update options.
    -> m (f Integer)
tsDecrbyOpts key value opts =
    sendRequest $ ["TS.DECRBY", key, encode value] ++ tsIncrByOptsToArgs opts

-- |Delete all samples between two timestamps for a given time series (<https://redis.io/commands/ts.del>).
--
-- /O(N)/ where /N/ is the number of data points that will be removed
--
-- Since RedisTimeSeries 1.6.0
tsDel
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> Integer -- ^ Lower timestamp bound.
    -> Integer -- ^ Upper timestamp bound.
    -> m (f Integer)
tsDel key fromTimestamp toTimestamp =
    sendRequest ["TS.DEL", key, encode fromTimestamp, encode toTimestamp]

-- |Delete a compaction rule (<https://redis.io/commands/ts.delrule>).
--
-- /O(1)/
--
-- Since RedisTimeSeries 1.0.0
tsDelrule
    :: (RedisCtx m f)
    => ByteString -- ^ Source time series key.
    -> ByteString -- ^ Destination time series key.
    -> m (f Status)
tsDelrule source destination = sendRequest ["TS.DELRULE", source, destination]

-- |Get the sample with the highest timestamp from a given time series (<https://redis.io/commands/ts.get>).
--
-- /O(1)/
--
-- Since RedisTimeSeries 1.0.0
tsGet
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> m (f (Maybe TsSample))
tsGet key = tsGetOpts key defaultTsGetOpts

-- |Get the sample with the highest timestamp from a given time series (<https://redis.io/commands/ts.get>).
--
-- /O(1)/
--
-- Since RedisTimeSeries 1.0.0
tsGetOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> TsGetOpts -- ^ Read options.
    -> m (f (Maybe TsSample))
tsGetOpts key TsGetOpts{..} =
    sendRequest $ ["TS.GET", key] ++ ["LATEST" | tsGetLatest]

-- |Increase the value of the sample with the maximum timestamp, or create a new sample with an incremented value (<https://redis.io/commands/ts.incrby>).
--
-- /O(M)/ when /M/ is the number of compaction rules, or /O(1)/ with no compaction
--
-- Since RedisTimeSeries 1.0.0
tsIncrby
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> Double -- ^ Increment amount.
    -> m (f Integer)
tsIncrby key value = tsIncrbyOpts key value defaultTsIncrByOpts

-- |Increase the value of the sample with the maximum timestamp, or create a new sample with an incremented value (<https://redis.io/commands/ts.incrby>).
--
-- /O(M)/ when /M/ is the number of compaction rules, or /O(1)/ with no compaction
--
-- Since RedisTimeSeries 1.0.0
tsIncrbyOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> Double -- ^ Increment amount.
    -> TsIncrByOpts -- ^ Update options.
    -> m (f Integer)
tsIncrbyOpts key value opts =
    sendRequest $ ["TS.INCRBY", key, encode value] ++ tsIncrByOptsToArgs opts

-- |Returns information and statistics for a time series (<https://redis.io/commands/ts.info>).
--
-- The reply is a heterogeneous attribute map, so this wrapper returns the raw 'Reply'.
--
-- /O(1)/
--
-- Since RedisTimeSeries 1.0.0
tsInfo
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> m (f Reply)
tsInfo key = tsInfoOpts key TsInfoDefault

-- |Returns information and statistics for a time series (<https://redis.io/commands/ts.info>).
--
-- The reply is a heterogeneous attribute map, so this wrapper returns the raw 'Reply'.
--
-- /O(1)/
--
-- Since RedisTimeSeries 1.0.0
tsInfoOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> TsInfoOpts -- ^ Information query options.
    -> m (f Reply)
tsInfoOpts key infoOpts =
    sendRequest $ ["TS.INFO", key] ++ case infoOpts of
        TsInfoDefault -> []
        TsInfoDebug -> ["DEBUG"]

-- |Append new samples to one or more time series (<https://redis.io/commands/ts.madd>).
--
-- /O(N \cdot M)/ when /N/ is the number of series updated and /M/ is the number of compaction rules, or /O(N)/ with no compaction
--
-- Since RedisTimeSeries 1.0.0
tsMadd
    :: (RedisCtx m f)
    => NonEmpty (ByteString, ByteString, Double) -- ^ Time series key, timestamp, and sample value triplets.
    -> m (f [Integer])
tsMadd triples = sendRequest $ "TS.MADD" : concatMap encodeTriple (NE.toList triples)
  where
    encodeTriple (key, timestamp, value) = [key, timestamp, encode value]

-- |Get the sample with the highest timestamp from each time series matching a specific filter (<https://redis.io/commands/ts.mget>).
--
-- The reply is heterogeneous and depends on label options, so this wrapper returns the raw 'Reply'.
--
-- /O(n)/ where /n/ is the number of time-series that match the filters
--
-- Since RedisTimeSeries 1.0.0
tsMget
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ Filter expressions.
    -> m (f Reply)
tsMget filters = tsMgetOpts filters defaultTsMGetOpts

-- |Get the sample with the highest timestamp from each time series matching a specific filter (<https://redis.io/commands/ts.mget>).
--
-- The reply is heterogeneous and depends on label options, so this wrapper returns the raw 'Reply'.
--
-- /O(n)/ where /n/ is the number of time-series that match the filters
--
-- Since RedisTimeSeries 1.0.0
tsMgetOpts
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ Filter expressions.
    -> TsMGetOpts -- ^ Read options.
    -> m (f Reply)
tsMgetOpts filters opts =
    sendRequest $ ["TS.MGET"] ++ tsMGetOptsToArgs opts ++ ["FILTER"] ++ NE.toList filters

-- |Query a range across multiple time series by filters in forward direction (<https://redis.io/commands/ts.mrange>).
--
-- The reply is heterogeneous and may include labels or grouped output, so this wrapper returns the raw 'Reply'.
--
-- /O(n\/m+k)/ where /n/ is the number of data points, /m/ is the chunk size, and /k/ is the number of returned samples
--
-- Since RedisTimeSeries 1.0.0
tsMrange
    :: (RedisCtx m f)
    => ByteString -- ^ Lower timestamp bound, or @-@.
    -> ByteString -- ^ Upper timestamp bound, or @+@.
    -> NonEmpty ByteString -- ^ Filter expressions.
    -> m (f Reply)
tsMrange fromTimestamp toTimestamp filters =
    tsMrangeOpts fromTimestamp toTimestamp filters defaultTsMRangeOpts

-- |Query a range across multiple time series by filters in forward direction (<https://redis.io/commands/ts.mrange>).
--
-- The reply is heterogeneous and may include labels or grouped output, so this wrapper returns the raw 'Reply'.
--
-- /O(n\/m+k)/ where /n/ is the number of data points, /m/ is the chunk size, and /k/ is the number of returned samples
--
-- Since RedisTimeSeries 1.0.0
tsMrangeOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Lower timestamp bound, or @-@.
    -> ByteString -- ^ Upper timestamp bound, or @+@.
    -> NonEmpty ByteString -- ^ Filter expressions.
    -> TsMRangeOpts -- ^ Query options.
    -> m (f Reply)
tsMrangeOpts fromTimestamp toTimestamp filters opts =
    sendRequest $ ["TS.MRANGE", fromTimestamp, toTimestamp] ++ tsMRangeOptsToArgs opts ++ ["FILTER"] ++ NE.toList filters

-- |Query a range across multiple time series by filters in reverse direction (<https://redis.io/commands/ts.mrevrange>).
--
-- The reply is heterogeneous and may include labels or grouped output, so this wrapper returns the raw 'Reply'.
--
-- /O(n\/m+k)/ where /n/ is the number of data points, /m/ is the chunk size, and /k/ is the number of returned samples
--
-- Since RedisTimeSeries 1.4.0
tsMrevrange
    :: (RedisCtx m f)
    => ByteString -- ^ Lower timestamp bound, or @-@.
    -> ByteString -- ^ Upper timestamp bound, or @+@.
    -> NonEmpty ByteString -- ^ Filter expressions.
    -> m (f Reply)
tsMrevrange fromTimestamp toTimestamp filters =
    tsMrevrangeOpts fromTimestamp toTimestamp filters defaultTsMRangeOpts

-- |Query a range across multiple time series by filters in reverse direction (<https://redis.io/commands/ts.mrevrange>).
--
-- The reply is heterogeneous and may include labels or grouped output, so this wrapper returns the raw 'Reply'.
--
-- /O(n\/m+k)/ where /n/ is the number of data points, /m/ is the chunk size, and /k/ is the number of returned samples
--
-- Since RedisTimeSeries 1.4.0
tsMrevrangeOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Lower timestamp bound, or @-@.
    -> ByteString -- ^ Upper timestamp bound, or @+@.
    -> NonEmpty ByteString -- ^ Filter expressions.
    -> TsMRangeOpts -- ^ Query options.
    -> m (f Reply)
tsMrevrangeOpts fromTimestamp toTimestamp filters opts =
    sendRequest $ ["TS.MREVRANGE", fromTimestamp, toTimestamp] ++ tsMRangeOptsToArgs opts ++ ["FILTER"] ++ NE.toList filters

-- |Get all time series keys matching a filter list (<https://redis.io/commands/ts.queryindex>).
--
-- /O(n)/ where /n/ is the number of time-series that match the filters
--
-- Since RedisTimeSeries 1.0.0
tsQueryindex
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ Filter expressions.
    -> m (f [ByteString])
tsQueryindex filters = sendRequest $ "TS.QUERYINDEX" : NE.toList filters

-- |Query a range in forward direction (<https://redis.io/commands/ts.range>).
--
-- /O(n\/m+k)/ where /n/ is the number of data points, /m/ is the chunk size, and /k/ is the number of returned samples
--
-- Since RedisTimeSeries 1.0.0
tsRange
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> ByteString -- ^ Lower timestamp bound, or @-@.
    -> ByteString -- ^ Upper timestamp bound, or @+@.
    -> m (f [TsSample])
tsRange key fromTimestamp toTimestamp =
    tsRangeOpts key fromTimestamp toTimestamp defaultTsRangeOpts

-- |Query a range in forward direction (<https://redis.io/commands/ts.range>).
--
-- /O(n\/m+k)/ where /n/ is the number of data points, /m/ is the chunk size, and /k/ is the number of returned samples
--
-- Since RedisTimeSeries 1.0.0
tsRangeOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> ByteString -- ^ Lower timestamp bound, or @-@.
    -> ByteString -- ^ Upper timestamp bound, or @+@.
    -> TsRangeOpts -- ^ Query options.
    -> m (f [TsSample])
tsRangeOpts key fromTimestamp toTimestamp opts =
    sendRequest $ ["TS.RANGE", key, fromTimestamp, toTimestamp] ++ tsRangeOptsToArgs opts

-- |Query a range in reverse direction (<https://redis.io/commands/ts.revrange>).
--
-- /O(n\/m+k)/ where /n/ is the number of data points, /m/ is the chunk size, and /k/ is the number of returned samples
--
-- Since RedisTimeSeries 1.4.0
tsRevrange
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> ByteString -- ^ Lower timestamp bound, or @-@.
    -> ByteString -- ^ Upper timestamp bound, or @+@.
    -> m (f [TsSample])
tsRevrange key fromTimestamp toTimestamp =
    tsRevrangeOpts key fromTimestamp toTimestamp defaultTsRangeOpts

-- |Query a range in reverse direction (<https://redis.io/commands/ts.revrange>).
--
-- /O(n\/m+k)/ where /n/ is the number of data points, /m/ is the chunk size, and /k/ is the number of returned samples
--
-- Since RedisTimeSeries 1.4.0
tsRevrangeOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Time series key.
    -> ByteString -- ^ Lower timestamp bound, or @-@.
    -> ByteString -- ^ Upper timestamp bound, or @+@.
    -> TsRangeOpts -- ^ Query options.
    -> m (f [TsSample])
tsRevrangeOpts key fromTimestamp toTimestamp opts =
    sendRequest $ ["TS.REVRANGE", key, fromTimestamp, toTimestamp] ++ tsRangeOptsToArgs opts
