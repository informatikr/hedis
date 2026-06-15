{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Database.Redis.ManualCommands.Cms where

import Data.ByteString (ByteString)
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE
import Data.Maybe (listToMaybe)

import Database.Redis.Core
import Database.Redis.Protocol
import Database.Redis.Types

data CMSInfo = CMSInfo
    { cmsInfoWidth :: Integer
      -- ^ Number of counters in each array row.
    , cmsInfoDepth :: Integer
      -- ^ Number of counter array rows.
    , cmsInfoCount :: Integer
      -- ^ Total count added to the sketch.
    } deriving (Show, Eq)

instance RedisResult CMSInfo where
    decode r = do
        fields <- decode r :: Either Reply [(ByteString, Integer)]
        cmsInfoWidth <- decodeField ["width", "Width"] fields
        cmsInfoDepth <- decodeField ["depth", "Depth"] fields
        cmsInfoCount <- decodeField ["count", "Count"] fields
        pure CMSInfo{..}
      where
        decodeField keys fields =
            maybe (Left r) Right . listToMaybe $
                [value | key <- keys, value <- maybeToList (lookup key fields)]

        maybeToList = maybe [] pure

data CMSMergeOpts
    = CMSMergeUnweighted (NonEmpty ByteString)
      -- ^ Merge the given source sketches using the default weight of @1@.
    | CMSMergeWeighted (NonEmpty (ByteString, Double))
      -- ^ Merge the given source sketches using an explicit weight for each source.
    deriving (Show, Eq)

cmsMergeOptsToArgs :: CMSMergeOpts -> [ByteString]
cmsMergeOptsToArgs (CMSMergeUnweighted sourceKeys) =
    encode (fromIntegral (NE.length sourceKeys) :: Integer) : NE.toList sourceKeys
cmsMergeOptsToArgs (CMSMergeWeighted weightedSourceKeys) =
    encode (fromIntegral (NE.length weightedSourceKeys) :: Integer)
        : map fst sourceKeyWeights
        ++ ["WEIGHTS"]
        ++ map (encode . snd) sourceKeyWeights
  where
    sourceKeyWeights = NE.toList weightedSourceKeys

-- |Increases the count of one or more items by increment (<https://redis.io/commands/cms.incrby>).
--
-- $O(n)$ where $n$ is the number of items
--
-- Since RedisBloom 2.0.0
cmsincrby
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Count-Min Sketch.
    -> NonEmpty (ByteString, Integer) -- ^ Item and increment pairs.
    -> m (f [Integer])
cmsincrby key itemIncrements =
    sendRequest $ ["CMS.INCRBY", key] ++ concatMap encodeItemIncrement (NE.toList itemIncrements)
  where
    encodeItemIncrement (item, increment) = [item, encode increment]

-- |Returns information about a sketch (<https://redis.io/commands/cms.info>).
--
-- $O(1)$
--
-- Since RedisBloom 2.0.0
cmsinfo
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Count-Min Sketch.
    -> m (f CMSInfo)
cmsinfo key = sendRequest ["CMS.INFO", key]

-- |Initializes a Count-Min Sketch to dimensions specified by user (<https://redis.io/commands/cms.initbydim>).
--
-- $O(1)$
--
-- Since RedisBloom 2.0.0
cmsinitbydim
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Count-Min Sketch to create.
    -> Integer -- ^ Number of counters in each row.
    -> Integer -- ^ Number of counter rows.
    -> m (f Status)
cmsinitbydim key width depth =
    sendRequest ["CMS.INITBYDIM", key, encode width, encode depth]

-- |Initializes a Count-Min Sketch to accommodate requested tolerances (<https://redis.io/commands/cms.initbyprob>).
--
-- $O(1)$
--
-- Since RedisBloom 2.0.0
cmsinitbyprob
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Count-Min Sketch to create.
    -> Double -- ^ Error factor.
    -> Double -- ^ Probability of the error factor.
    -> m (f Status)
cmsinitbyprob key err probability =
    sendRequest ["CMS.INITBYPROB", key, encode err, encode probability]

-- |Merges several sketches into one sketch (<https://redis.io/commands/cms.merge>).
--
-- Source sketches are merged with the default weight of @1@.
--
-- $O(n)$ where $n$ is the number of sketches
--
-- Since RedisBloom 2.0.0
cmsmerge
    :: (RedisCtx m f)
    => ByteString -- ^ Destination sketch key.
    -> NonEmpty ByteString -- ^ Source sketch keys.
    -> m (f Status)
cmsmerge destination sourceKeys =
    cmsmergeOpts destination (CMSMergeUnweighted sourceKeys)

-- |Merges several sketches into one sketch (<https://redis.io/commands/cms.merge>).
--
-- $O(n)$ where $n$ is the number of sketches
--
-- Since RedisBloom 2.0.0
cmsmergeOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Destination sketch key.
    -> CMSMergeOpts -- ^ Source sketches with optional weights.
    -> m (f Status)
cmsmergeOpts destination opts =
    sendRequest $ ["CMS.MERGE", destination] ++ cmsMergeOptsToArgs opts

-- |Merges several sketches into one sketch (<https://redis.io/commands/cms.merge>).
--
-- $O(n)$ where $n$ is the number of sketches
--
-- Since RedisBloom 2.0.0
cmsmergeWeighted
    :: (RedisCtx m f)
    => ByteString -- ^ Destination sketch key.
    -> NonEmpty (ByteString, Double) -- ^ Source sketch keys paired with weights.
    -> m (f Status)
cmsmergeWeighted destination weightedSourceKeys =
    cmsmergeOpts destination (CMSMergeWeighted weightedSourceKeys)

-- |Returns the count for one or more items in a sketch (<https://redis.io/commands/cms.query>).
--
-- $O(n)$ where $n$ is the number of items
--
-- Since RedisBloom 2.0.0
cmsquery
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Count-Min Sketch.
    -> NonEmpty ByteString -- ^ Items to query.
    -> m (f [Integer])
cmsquery key items = sendRequest $ ["CMS.QUERY", key] ++ NE.toList items
