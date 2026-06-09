{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Database.Redis.ManualCommands.BF where

import Data.ByteString (ByteString)
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE

import Database.Redis.Core
import Database.Redis.Types
import Database.Redis.Protocol

data BFInfo = BFInfo
    { bfInfoCapacity :: Integer
      -- ^ Number of unique items that can be stored before scaling is required.
    , bfInfoSize :: Integer
      -- ^ Number of bytes allocated for the Bloom filter.
    , bfInfoFilters :: Integer
      -- ^ Number of sub-filters.
    , bfInfoItems :: Integer
      -- ^ Number of unique inserted items detected by the filter.
    , bfInfoExpansion :: Integer
      -- ^ Expansion rate used when a new sub-filter is created.
    } deriving (Show, Eq)

instance RedisResult BFInfo where
    decode r = do
        fields <- decode r :: Either Reply [(ByteString, Integer)]
        bfInfoCapacity <- decodeField "Capacity" fields
        bfInfoSize <- decodeField "Size" fields
        bfInfoFilters <- decodeField "Number of filters" fields
        bfInfoItems <- decodeField "Number of items inserted" fields
        bfInfoExpansion <- decodeField "Expansion rate" fields
        pure BFInfo{..}
      where
        decodeField key fields = maybe (Left r) Right (lookup key fields)

data BFReserveOpts = BFReserveOpts
    { bfReserveExpansion :: Maybe Integer
      -- ^ Expansion rate for newly created sub-filters once capacity is reached.
    , bfReserveNonScaling :: Bool
      -- ^ Prevent creation of additional sub-filters when initial capacity is reached.
    } deriving (Show, Eq)

defaultBFReserveOpts :: BFReserveOpts
defaultBFReserveOpts = BFReserveOpts
    { bfReserveExpansion = Nothing
    , bfReserveNonScaling = False
    }

data BFInsertOpts = BFInsertOpts
    { bfInsertCapacity :: Maybe Integer
      -- ^ Initial capacity to use if a new filter is created.
    , bfInsertError :: Maybe Double
      -- ^ Desired false positive probability to use if a new filter is created.
    , bfInsertExpansion :: Maybe Integer
      -- ^ Expansion rate for additional sub-filters.
    , bfInsertNoCreate :: Bool
      -- ^ Return an error instead of creating the filter when the key does not exist.
    , bfInsertNonScaling :: Bool
      -- ^ Prevent creation of additional sub-filters when capacity is reached.
    } deriving (Show, Eq)

defaultBFInsertOpts :: BFInsertOpts
defaultBFInsertOpts = BFInsertOpts
    { bfInsertCapacity = Nothing
    , bfInsertError = Nothing
    , bfInsertExpansion = Nothing
    , bfInsertNoCreate = False
    , bfInsertNonScaling = False
    }

bfReserveOptsToArgs :: BFReserveOpts -> [ByteString]
bfReserveOptsToArgs BFReserveOpts{..} =
    expansionArg ++ nonScalingArg
  where
    expansionArg = maybe [] (\expansion -> ["EXPANSION", encode expansion]) bfReserveExpansion
    nonScalingArg = ["NONSCALING" | bfReserveNonScaling]

bfInsertOptsToArgs :: BFInsertOpts -> [ByteString]
bfInsertOptsToArgs BFInsertOpts{..} =
    capacityArg ++ errorArg ++ expansionArg ++ noCreateArg ++ nonScalingArg
  where
    capacityArg = maybe [] (\capacity -> ["CAPACITY", encode capacity]) bfInsertCapacity
    errorArg = maybe [] (\err -> ["ERROR", encode err]) bfInsertError
    expansionArg = maybe [] (\expansion -> ["EXPANSION", encode expansion]) bfInsertExpansion
    noCreateArg = ["NOCREATE" | bfInsertNoCreate]
    nonScalingArg = ["NONSCALING" | bfInsertNonScaling]

-- |Adds an item to a Bloom filter (<https://redis.io/commands/bf.add>).
--
-- A filter is created automatically if the key does not exist.
--
-- $O(k)$, where $k$ is the number of hash functions used by the last sub-filter.
--
-- Since RedisBloom 1.0.0
bfadd
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Bloom filter.
    -> ByteString -- ^ Item to add to the Bloom filter.
    -> m (f Bool)
bfadd key item = sendRequest ["BF.ADD", key, item]

-- |Returns the cardinality of a Bloom filter (<https://redis.io/commands/bf.card>).
--
-- Returns @0@ when the key does not exist.
--
-- $O(1)$
--
-- Since RedisBloom 2.4.4
bfcard
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Bloom filter.
    -> m (f Integer)
bfcard key = sendRequest ["BF.CARD", key]

-- |Determines whether an item was added to a Bloom filter (<https://redis.io/commands/bf.exists>).
--
-- Returns 'False' when the key does not exist or the item was definitely not added.
--
-- $O(k)$, where $k$ is the number of hash functions used by the last sub-filter.
--
-- Since RedisBloom 1.0.0
bfexists
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Bloom filter.
    -> ByteString -- ^ Item to check.
    -> m (f Bool)
bfexists key item = sendRequest ["BF.EXISTS", key, item]

-- |Returns information about a Bloom filter (<https://redis.io/commands/bf.info>).
--
-- $O(1)$
--
-- Since RedisBloom 1.0.0
bfinfo
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Bloom filter.
    -> m (f BFInfo)
bfinfo key = sendRequest ["BF.INFO", key]

-- |Returns the configured capacity of a Bloom filter (<https://redis.io/commands/bf.info>).
--
-- $O(1)$
--
-- Since RedisBloom 1.0.0
bfinfoCapacity
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Bloom filter.
    -> m (f [Integer])
bfinfoCapacity key = sendRequest ["BF.INFO", key, "CAPACITY"]

-- |Returns the size in bytes of a Bloom filter (<https://redis.io/commands/bf.info>).
--
-- $O(1)$
--
-- Since RedisBloom 1.0.0
bfinfoSize
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Bloom filter.
    -> m (f [Integer])
bfinfoSize key = sendRequest ["BF.INFO", key, "SIZE"]

-- |Returns the number of sub-filters in a Bloom filter (<https://redis.io/commands/bf.info>).
--
-- $O(1)$
--
-- Since RedisBloom 1.0.0
bfinfoFilters
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Bloom filter.
    -> m (f [Integer])
bfinfoFilters key = sendRequest ["BF.INFO", key, "FILTERS"]

-- |Returns the number of unique inserted items detected by a Bloom filter (<https://redis.io/commands/bf.info>).
--
-- $O(1)$
--
-- Since RedisBloom 1.0.0
bfinfoItems
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Bloom filter.
    -> m (f [Integer])
bfinfoItems key = sendRequest ["BF.INFO", key, "ITEMS"]

-- |Returns the expansion rate of a Bloom filter (<https://redis.io/commands/bf.info>).
--
-- $O(1)$
--
-- Returns Nothing for the non scaling filters.
--
-- Since RedisBloom 1.0.0
bfinfoExpansion
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Bloom filter.
    -> m (f [Maybe Integer])
bfinfoExpansion key = sendRequest ["BF.INFO", key, "EXPANSION"]

-- |Adds one or more items to a Bloom filter, creating it when needed (<https://redis.io/commands/bf.insert>).
--
-- This is equivalent to inserting with default options and automatic creation enabled.
--
-- $O(k \cdot n)$, where $k$ is the number of hash functions and $n$ is the number of items.
--
-- Since RedisBloom 1.0.0
bfinsert
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Bloom filter.
    -> NonEmpty ByteString -- ^ Items to add.
    -> m (f [Bool])
bfinsert key items = bfinsertOpts key items defaultBFInsertOpts

-- |Adds one or more items to a Bloom filter, creating it when needed (<https://redis.io/commands/bf.insert>).
--
-- $O(k \cdot n)$, where $k$ is the number of hash functions and $n$ is the number of items.
--
-- Since RedisBloom 1.0.0
bfinsertOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Bloom filter.
    -> NonEmpty ByteString -- ^ Items to add.
    -> BFInsertOpts -- ^ Optional creation and scaling parameters.
    -> m (f [Bool])
bfinsertOpts key items opts =
    sendRequest $ ["BF.INSERT", key] ++ bfInsertOptsToArgs opts ++ ["ITEMS"] ++ NE.toList items

-- |Adds one or more items to a Bloom filter (<https://redis.io/commands/bf.madd>).
--
-- A filter is created automatically if the key does not exist.
--
-- $O(k \cdot n)$, where $k$ is the number of hash functions and $n$ is the number of items.
--
-- Since RedisBloom 1.0.0
bfmadd
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Bloom filter.
    -> NonEmpty ByteString -- ^ Items to add.
    -> m (f [Bool])
bfmadd key items = sendRequest $ ["BF.MADD", key] ++ NE.toList items

-- |Checks whether one or more items were added to a Bloom filter (<https://redis.io/commands/bf.mexists>).
--
-- A 'False' result means the item is definitely absent, or the key does not exist.
--
-- $O(k \cdot n)$, where $k$ is the number of hash functions and $n$ is the number of items.
--
-- Since RedisBloom 1.0.0
bfmexists
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Bloom filter.
    -> NonEmpty ByteString -- ^ Items to check.
    -> m (f [Bool])
bfmexists key items = sendRequest $ ["BF.MEXISTS", key] ++ NE.toList items

-- |Creates an empty Bloom filter (<https://redis.io/commands/bf.reserve>).
--
-- The filter will fail if the key already exists.
--
-- $O(1)$
--
-- Since RedisBloom 1.0.0
bfreserve
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Bloom filter to create.
    -> Double -- ^ Desired false positive probability, between @0@ and @1@.
    -> Integer -- ^ Initial capacity.
    -> m (f Status)
bfreserve key errorRate capacity = bfreserveOpts key errorRate capacity defaultBFReserveOpts

-- |Creates an empty Bloom filter (<https://redis.io/commands/bf.reserve>).
--
-- $O(1)$
--
-- Since RedisBloom 1.0.0
bfreserveOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Bloom filter to create.
    -> Double -- ^ Desired false positive probability, between @0@ and @1@.
    -> Integer -- ^ Initial capacity.
    -> BFReserveOpts -- ^ Scaling options for the reserved filter.
    -> m (f Status)
bfreserveOpts key errorRate capacity opts =
    sendRequest $ ["BF.RESERVE", key, encode errorRate, encode capacity] ++ bfReserveOptsToArgs opts
