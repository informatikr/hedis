{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Database.Redis.ManualCommands.Topk where

import Data.ByteString (ByteString)
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE

import Database.Redis.Core
import Database.Redis.Protocol
import Database.Redis.Types

data TopkInfo = TopkInfo
    { topkInfoK :: Integer
      -- ^ Number of items kept in the Top-K list.
    , topkInfoWidth :: Integer
      -- ^ Number of counters in each array.
    , topkInfoDepth :: Integer
      -- ^ Number of counter arrays.
    , topkInfoDecay :: Double
      -- ^ Decay factor of the sketch.
    } deriving (Show, Eq)

instance RedisResult TopkInfo where
    decode r = do
        fields <- decode r :: Either Reply [(ByteString, Reply)]
        topkInfoK <- decodeField "k" fields
        topkInfoWidth <- decodeField "width" fields
        topkInfoDepth <- decodeField "depth" fields
        topkInfoDecay <- decodeField "decay" fields
        pure TopkInfo{..}
      where
        decodeField key fields = maybe (Left r) decode (lookup key fields)

-- |Adds one or more items to a Top-K sketch (<https://redis.io/commands/topk.add>).
--
-- Returns the items dropped from the sketch after each insertion, or 'Nothing' when no item was expelled.
--
-- $O(n \cdot d)$, where $n$ is the number of items and $d$ is the depth of the sketch.
--
-- Since RedisBloom 2.0.0
topkAdd
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Top-K sketch.
    -> NonEmpty ByteString -- ^ Items to add.
    -> m (f [Maybe ByteString])
topkAdd key items = sendRequest $ ["TOPK.ADD", key] ++ NE.toList items

-- |Returns the count for one or more items in a Top-K sketch (<https://redis.io/commands/topk.count>).
--
-- Returns @0@ for items that are not tracked by the sketch.
--
-- $O(n \cdot d)$, where $n$ is the number of items and $d$ is the depth of the sketch.
--
-- Since RedisBloom 2.0.0
topkCount
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Top-K sketch.
    -> NonEmpty ByteString -- ^ Items to count.
    -> m (f [Integer])
topkCount key items = sendRequest $ ["TOPK.COUNT", key] ++ NE.toList items

-- |Increments the count of one or more items by a configured amount (<https://redis.io/commands/topk.incrby>).
--
-- Returns the items dropped from the sketch after each increment, or 'Nothing' when no item was expelled.
--
-- $O(n \cdot d)$, where $n$ is the number of item-increment pairs and $d$ is the depth of the sketch.
--
-- Since RedisBloom 2.0.0
topkIncrby
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Top-K sketch.
    -> NonEmpty (ByteString, Integer) -- ^ Item and increment pairs.
    -> m (f [Maybe ByteString])
topkIncrby key itemIncrements =
    sendRequest $ ["TOPK.INCRBY", key] ++ concatMap encodePair (NE.toList itemIncrements)
  where
    encodePair (item, increment) = [item, encode increment]

-- |Returns information about a Top-K sketch (<https://redis.io/commands/topk.info>).
--
-- $O(1)$
--
-- Since RedisBloom 2.0.0
topkInfo
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Top-K sketch.
    -> m (f TopkInfo)
topkInfo key = sendRequest ["TOPK.INFO", key]

-- |Returns the items in a Top-K sketch (<https://redis.io/commands/topk.list>).
--
-- $O(k)$, where $k$ is the configured top-k size.
--
-- Since RedisBloom 2.0.0
topkList
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Top-K sketch.
    -> m (f [ByteString])
topkList key = sendRequest ["TOPK.LIST", key]

-- |Returns the items in a Top-K sketch along with their approximated counts (<https://redis.io/commands/topk.list>).
--
-- $O(k)$, where $k$ is the configured top-k size.
--
-- Since RedisBloom 2.0.0
topkListWithCount
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Top-K sketch.
    -> m (f [(ByteString, Integer)])
topkListWithCount key = sendRequest ["TOPK.LIST", key, "WITHCOUNT"]

-- |Creates an empty Top-K sketch (<https://redis.io/commands/topk.reserve>).
--
-- The sketch will fail to be created if the key already exists.
--
-- $O(1)$
--
-- Since RedisBloom 2.0.0
topkReserve
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Top-K sketch to create.
    -> Integer -- ^ Number of items to keep in the sketch.
    -> Integer -- ^ Number of counters in each array.
    -> Integer -- ^ Number of counter arrays.
    -> Double -- ^ Decay factor.
    -> m (f Status)
topkReserve key topk width depth decay =
    sendRequest ["TOPK.RESERVE", key, encode topk, encode width, encode depth, encode decay]

-- |Checks whether one or more items are present in a Top-K sketch (<https://redis.io/commands/topk.query>).
--
-- A 'False' value means the item is not currently one of the tracked heavy hitters.
--
-- $O(n \cdot d)$, where $n$ is the number of items and $d$ is the depth of the sketch.
--
-- Since RedisBloom 2.0.0
topkQuery
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Top-K sketch.
    -> NonEmpty ByteString -- ^ Items to check.
    -> m (f [Bool])
topkQuery key items = sendRequest $ ["TOPK.QUERY", key] ++ NE.toList items
