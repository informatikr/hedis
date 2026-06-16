{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Database.Redis.ManualCommands.Tdigest where

import Data.ByteString (ByteString)
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE
import Data.Maybe (listToMaybe)

import Database.Redis.Core
import Database.Redis.Protocol
import Database.Redis.Types

data TDigestCreateOpts = TDigestCreateOpts
    { tdigestCreateCompression :: Maybe Integer
      -- ^ Compression parameter controlling accuracy and size.
    } deriving (Show, Eq)

defaultTDigestCreateOpts :: TDigestCreateOpts
defaultTDigestCreateOpts = TDigestCreateOpts
    { tdigestCreateCompression = Nothing
    }

data TDigestMergeOpts = TDigestMergeOpts
    { tdigestMergeCompression :: Maybe Integer
      -- ^ Compression parameter for the destination digest.
    , tdigestMergeOverride :: Bool
      -- ^ Overwrite the destination key if it already exists.
    } deriving (Show, Eq)

defaultTDigestMergeOpts :: TDigestMergeOpts
defaultTDigestMergeOpts = TDigestMergeOpts
    { tdigestMergeCompression = Nothing
    , tdigestMergeOverride = False
    }

data TDigestInfo = TDigestInfo
    { tdigestInfoCompression :: Integer
      -- ^ Compression parameter of the digest.
    , tdigestInfoCapacity :: Integer
      -- ^ Allocated centroid capacity.
    , tdigestInfoMergedNodes :: Integer
      -- ^ Number of merged centroids.
    , tdigestInfoUnmergedNodes :: Integer
      -- ^ Number of pending unmerged centroids.
    , tdigestInfoMergedWeight :: Integer
      -- ^ Weight held by merged centroids.
    , tdigestInfoUnmergedWeight :: Integer
      -- ^ Weight held by pending unmerged centroids.
    , tdigestInfoObservations :: Integer
      -- ^ Total number of added observations.
    , tdigestInfoTotalCompressions :: Integer
      -- ^ Number of performed compression passes.
    , tdigestInfoMemoryUsage :: Integer
      -- ^ Memory usage in bytes.
    } deriving (Show, Eq)

instance RedisResult TDigestInfo where
    decode r = do
        fields <- decode r :: Either Reply [(ByteString, Integer)]
        tdigestInfoCompression <- decodeField ["Compression", "compression"] fields
        tdigestInfoCapacity <- decodeField ["Capacity", "capacity"] fields
        tdigestInfoMergedNodes <- decodeField ["Merged nodes", "merged nodes"] fields
        tdigestInfoUnmergedNodes <- decodeField ["Unmerged nodes", "unmerged nodes"] fields
        tdigestInfoMergedWeight <- decodeField ["Merged weight", "merged weight"] fields
        tdigestInfoUnmergedWeight <- decodeField ["Unmerged weight", "unmerged weight"] fields
        tdigestInfoObservations <- decodeField ["Observations", "observations"] fields
        tdigestInfoTotalCompressions <- decodeField ["Total compressions", "total compressions"] fields
        tdigestInfoMemoryUsage <- decodeField ["Memory usage", "memory usage"] fields
        pure TDigestInfo{..}
      where
        decodeField keys fields =
            maybe (Left r) Right . listToMaybe $
                [value | key <- keys, value <- maybeToList (lookup key fields)]

        maybeToList = maybe [] pure

tdigestCreateOptsToArgs :: TDigestCreateOpts -> [ByteString]
tdigestCreateOptsToArgs TDigestCreateOpts{..} =
    maybe [] (\compression -> ["COMPRESSION", encode compression]) tdigestCreateCompression

tdigestMergeOptsToArgs :: TDigestMergeOpts -> [ByteString]
tdigestMergeOptsToArgs TDigestMergeOpts{..} =
    compressionArg ++ overrideArg
  where
    compressionArg = maybe [] (\compression -> ["COMPRESSION", encode compression]) tdigestMergeCompression
    overrideArg = ["OVERRIDE" | tdigestMergeOverride]

-- |Adds one or more observations to a t-digest sketch (<https://redis.io/commands/tdigest.add>).
--
-- $O(n \log k)$, where $n$ is the number of observations and $k$ is the compression parameter.
--
-- Since RedisBloom 2.4.0
tdigestAdd
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the t-digest sketch.
    -> NonEmpty Double -- ^ Observations to add.
    -> m (f Status)
tdigestAdd key values = sendRequest $ ["TDIGEST.ADD", key] ++ map encode (NE.toList values)

-- |Returns observations by their ascending ranks from a t-digest sketch (<https://redis.io/commands/tdigest.byrank>).
--
-- $O(n \log k)$, where $n$ is the number of requested ranks and $k$ is the compression parameter.
--
-- Since RedisBloom 2.4.0
tdigestByrank
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the t-digest sketch.
    -> NonEmpty Integer -- ^ Requested ranks.
    -> m (f [Double])
tdigestByrank key ranks = sendRequest $ ["TDIGEST.BYRANK", key] ++ map encode (NE.toList ranks)

-- |Returns observations by their descending ranks from a t-digest sketch (<https://redis.io/commands/tdigest.byrevrank>).
--
-- $O(n \log k)$, where $n$ is the number of requested reverse ranks and $k$ is the compression parameter.
--
-- Since RedisBloom 2.4.0
tdigestByrevrank
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the t-digest sketch.
    -> NonEmpty Integer -- ^ Requested reverse ranks.
    -> m (f [Double])
tdigestByrevrank key ranks = sendRequest $ ["TDIGEST.BYREVRANK", key] ++ map encode (NE.toList ranks)

-- |Returns cumulative distribution estimates for one or more observations (<https://redis.io/commands/tdigest.cdf>).
--
-- $O(n \log k)$, where $n$ is the number of queried values and $k$ is the compression parameter.
--
-- Since RedisBloom 2.4.0
tdigestCdf
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the t-digest sketch.
    -> NonEmpty Double -- ^ Observations to query.
    -> m (f [Double])
tdigestCdf key values = sendRequest $ ["TDIGEST.CDF", key] ++ map encode (NE.toList values)

-- |Creates an empty t-digest sketch (<https://redis.io/commands/tdigest.create>).
--
-- $O(1)$
--
-- Since RedisBloom 2.4.0
tdigestCreate
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the t-digest sketch to create.
    -> m (f Status)
tdigestCreate key = tdigestCreateOpts key defaultTDigestCreateOpts

-- |Creates an empty t-digest sketch (<https://redis.io/commands/tdigest.create>).
--
-- $O(1)$
--
-- Since RedisBloom 2.4.0
tdigestCreateOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the t-digest sketch to create.
    -> TDigestCreateOpts -- ^ Creation options.
    -> m (f Status)
tdigestCreateOpts key opts =
    sendRequest $ ["TDIGEST.CREATE", key] ++ tdigestCreateOptsToArgs opts

-- |Returns information about a t-digest sketch (<https://redis.io/commands/tdigest.info>).
--
-- $O(1)$
--
-- Since RedisBloom 2.4.0
tdigestInfo
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the t-digest sketch.
    -> m (f TDigestInfo)
tdigestInfo key = sendRequest ["TDIGEST.INFO", key]

-- |Returns the maximum observation in a t-digest sketch (<https://redis.io/commands/tdigest.max>).
--
-- $O(1)$
--
-- Since RedisBloom 2.4.0
tdigestMax
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the t-digest sketch.
    -> m (f Double)
tdigestMax key = sendRequest ["TDIGEST.MAX", key]

-- |Merges multiple t-digest sketches into a destination sketch (<https://redis.io/commands/tdigest.merge>).
--
-- $O(n \cdot k)$, where $n$ is the number of source sketches and $k$ is the compression parameter.
--
-- Since RedisBloom 2.4.0
tdigestMerge
    :: (RedisCtx m f)
    => ByteString -- ^ Destination key.
    -> NonEmpty ByteString -- ^ Source sketch keys.
    -> m (f Status)
tdigestMerge destination sources =
    tdigestMergeOpts destination sources defaultTDigestMergeOpts

-- |Merges multiple t-digest sketches into a destination sketch (<https://redis.io/commands/tdigest.merge>).
--
-- $O(n \cdot k)$, where $n$ is the number of source sketches and $k$ is the compression parameter.
--
-- Since RedisBloom 2.4.0
tdigestMergeOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Destination key.
    -> NonEmpty ByteString -- ^ Source sketch keys.
    -> TDigestMergeOpts -- ^ Merge options.
    -> m (f Status)
tdigestMergeOpts destination sources opts =
    sendRequest $
        ["TDIGEST.MERGE", destination, encode (fromIntegral (NE.length sources) :: Integer)]
            ++ NE.toList sources
            ++ tdigestMergeOptsToArgs opts

-- |Returns the minimum observation in a t-digest sketch (<https://redis.io/commands/tdigest.min>).
--
-- $O(1)$
--
-- Since RedisBloom 2.4.0
tdigestMin
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the t-digest sketch.
    -> m (f Double)
tdigestMin key = sendRequest ["TDIGEST.MIN", key]

-- |Returns quantile estimates for one or more quantiles (<https://redis.io/commands/tdigest.quantile>).
--
-- $O(n \log k)$, where $n$ is the number of quantiles and $k$ is the compression parameter.
--
-- Since RedisBloom 2.4.0
tdigestQuantile
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the t-digest sketch.
    -> NonEmpty Double -- ^ Quantiles to estimate.
    -> m (f [Double])
tdigestQuantile key quantiles =
    sendRequest $ ["TDIGEST.QUANTILE", key] ++ map encode (NE.toList quantiles)

-- |Returns ascending rank estimates for one or more observations (<https://redis.io/commands/tdigest.rank>).
--
-- $O(n \log k)$, where $n$ is the number of observations and $k$ is the compression parameter.
--
-- Since RedisBloom 2.4.0
tdigestRank
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the t-digest sketch.
    -> NonEmpty Double -- ^ Observations to rank.
    -> m (f [Integer])
tdigestRank key values = sendRequest $ ["TDIGEST.RANK", key] ++ map encode (NE.toList values)

-- |Resets a t-digest sketch to its empty state (<https://redis.io/commands/tdigest.reset>).
--
-- $O(1)$
--
-- Since RedisBloom 2.4.0
tdigestReset
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the t-digest sketch.
    -> m (f Status)
tdigestReset key = sendRequest ["TDIGEST.RESET", key]

-- |Returns descending rank estimates for one or more observations (<https://redis.io/commands/tdigest.revrank>).
--
-- $O(n \log k)$, where $n$ is the number of observations and $k$ is the compression parameter.
--
-- Since RedisBloom 2.4.0
tdigestRevrank
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the t-digest sketch.
    -> NonEmpty Double -- ^ Observations to rank.
    -> m (f [Integer])
tdigestRevrank key values = sendRequest $ ["TDIGEST.REVRANK", key] ++ map encode (NE.toList values)

-- |Returns the trimmed mean for observations within the provided quantile range (<https://redis.io/commands/tdigest.trimmed_mean>).
--
-- $O(\log k)$, where $k$ is the compression parameter.
--
-- Since RedisBloom 2.4.0
tdigestTrimmedMean
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the t-digest sketch.
    -> Double -- ^ Lower quantile bound.
    -> Double -- ^ Upper quantile bound.
    -> m (f Double)
tdigestTrimmedMean key lowCut highCut =
    sendRequest ["TDIGEST.TRIMMED_MEAN", key, encode lowCut, encode highCut]
