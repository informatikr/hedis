{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Database.Redis.ManualCommands.CF where

import Data.ByteString (ByteString)
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE

import Database.Redis.Core
import Database.Redis.Protocol
import Database.Redis.Types

data CFInfo = CFInfo
    { cfInfoSize :: Integer
      -- ^ Number of bytes allocated for the Cuckoo filter.
    , cfInfoBuckets :: Integer
      -- ^ Number of buckets in the filter.
    , cfInfoFilters :: Integer
      -- ^ Number of sub-filters.
    , cfInfoItemsInserted :: Integer
      -- ^ Number of inserted items tracked by the filter.
    , cfInfoItemsDeleted :: Integer
      -- ^ Number of deleted items tracked by the filter.
    , cfInfoBucketSize :: Integer
      -- ^ Number of entries per bucket.
    , cfInfoExpansion :: Integer
      -- ^ Expansion rate used when additional sub-filters are created.
    , cfInfoMaxIterations :: Integer
      -- ^ Maximum number of displacement attempts during insertion.
    } deriving (Show, Eq)

instance RedisResult CFInfo where
    decode r = do
        fields <- decode r :: Either Reply [(ByteString, Integer)]
        cfInfoSize <- decodeField "Size" fields
        cfInfoBuckets <- decodeField "Number of buckets" fields
        cfInfoFilters <- decodeField "Number of filters" fields
        cfInfoItemsInserted <- decodeField "Number of items inserted" fields
        cfInfoItemsDeleted <- decodeField "Number of items deleted" fields
        cfInfoBucketSize <- decodeField "Bucket size" fields
        cfInfoExpansion <- decodeField "Expansion rate" fields
        cfInfoMaxIterations <- decodeField "Max iterations" fields
        pure CFInfo{..}
      where
        decodeField key fields = maybe (Left r) Right (lookup key fields)

data CFReserveOpts = CFReserveOpts
    { cfReserveBucketSize :: Maybe Integer
      -- ^ Number of entries per bucket.
    , cfReserveMaxIterations :: Maybe Integer
      -- ^ Maximum number of displacement attempts during insertion.
    , cfReserveExpansion :: Maybe Integer
      -- ^ Expansion rate for newly created sub-filters.
    } deriving (Show, Eq)

defaultCFReserveOpts :: CFReserveOpts
defaultCFReserveOpts = CFReserveOpts
    { cfReserveBucketSize = Nothing
    , cfReserveMaxIterations = Nothing
    , cfReserveExpansion = Nothing
    }

data CFInsertOpts = CFInsertOpts
    { cfInsertCapacity :: Maybe Integer
      -- ^ Initial capacity to use if a new filter is created.
    , cfInsertNoCreate :: Bool
      -- ^ Return an error instead of creating the filter when the key does not exist.
    } deriving (Show, Eq)

defaultCFInsertOpts :: CFInsertOpts
defaultCFInsertOpts = CFInsertOpts
    { cfInsertCapacity = Nothing
    , cfInsertNoCreate = False
    }

data CFInsertResult
    = CFInsertAdded
    | CFInsertAlreadyExists
    | CFInsertFilterFull
    deriving (Show, Eq)

instance RedisResult CFInsertResult where
    decode r = do
        result <- decode r :: Either Reply Integer
        case result of
            1 -> Right CFInsertAdded
            0 -> Right CFInsertAlreadyExists
            -1 -> Right CFInsertFilterFull
            _ -> Left r

cfReserveOptsToArgs :: CFReserveOpts -> [ByteString]
cfReserveOptsToArgs CFReserveOpts{..} =
    bucketSizeArg ++ maxIterationsArg ++ expansionArg
  where
    bucketSizeArg = maybe [] (\bucketSize -> ["BUCKETSIZE", encode bucketSize]) cfReserveBucketSize
    maxIterationsArg = maybe [] (\iterations -> ["MAXITERATIONS", encode iterations]) cfReserveMaxIterations
    expansionArg = maybe [] (\expansion -> ["EXPANSION", encode expansion]) cfReserveExpansion

cfInsertOptsToArgs :: CFInsertOpts -> [ByteString]
cfInsertOptsToArgs CFInsertOpts{..} =
    capacityArg ++ noCreateArg
  where
    capacityArg = maybe [] (\capacity -> ["CAPACITY", encode capacity]) cfInsertCapacity
    noCreateArg = ["NOCREATE" | cfInsertNoCreate]

-- |Adds an item to a Cuckoo filter (<https://redis.io/commands/cf.add>).
--
-- A filter is created automatically if the key does not exist.
--
-- $O(k + i)$, where $k$ is the number of sub-filters and $i$ is maxIterations.
--
-- Since RedisBloom 1.0.0
cfadd
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Cuckoo filter.
    -> ByteString -- ^ Item to add.
    -> m (f Bool)
cfadd key item = sendRequest ["CF.ADD", key, item]

-- |Adds an item to a Cuckoo filter only if it did not already exist (<https://redis.io/commands/cf.addnx>).
--
-- A filter is created automatically if the key does not exist.
--
-- $O(k + i)$, where $k$ is the number of sub-filters and $i$ is maxIterations.
--
-- Since RedisBloom 1.0.0
cfaddnx
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Cuckoo filter.
    -> ByteString -- ^ Item to add.
    -> m (f Bool)
cfaddnx key item = sendRequest ["CF.ADDNX", key, item]

-- |Returns the number of times an item might appear in a Cuckoo filter (<https://redis.io/commands/cf.count>).
--
-- Returns @0@ when the key does not exist or the item was not found.
--
-- $O(k)$, where $k$ is the number of sub-filters.
--
-- Since RedisBloom 1.0.0
cfcount
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Cuckoo filter.
    -> ByteString -- ^ Item to count.
    -> m (f Integer)
cfcount key item = sendRequest ["CF.COUNT", key, item]

-- |Deletes an item from a Cuckoo filter (<https://redis.io/commands/cf.del>).
--
-- Returns 'False' when the key does not exist or the item was not found.
--
-- $O(k)$, where $k$ is the number of sub-filters.
--
-- Since RedisBloom 1.0.0
cfdel
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Cuckoo filter.
    -> ByteString -- ^ Item to delete.
    -> m (f Bool)
cfdel key item = sendRequest ["CF.DEL", key, item]

-- |Checks whether an item may exist in a Cuckoo filter (<https://redis.io/commands/cf.exists>).
--
-- Returns 'False' when the key does not exist or the item is definitely absent.
--
-- $O(k)$, where $k$ is the number of sub-filters.
--
-- Since RedisBloom 1.0.0
cfexists
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Cuckoo filter.
    -> ByteString -- ^ Item to check.
    -> m (f Bool)
cfexists key item = sendRequest ["CF.EXISTS", key, item]

-- |Returns information about a Cuckoo filter (<https://redis.io/commands/cf.info>).
--
-- $O(1)$
--
-- Since RedisBloom 1.0.0
cfinfo
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Cuckoo filter.
    -> m (f CFInfo)
cfinfo key = sendRequest ["CF.INFO", key]

-- |Adds one or more items to a Cuckoo filter, creating it when needed (<https://redis.io/commands/cf.insert>).
--
-- This is equivalent to inserting with default options and automatic creation enabled.
--
-- $O(n * (k + i))$, where $n$ is the number of items, $k$ is the number of sub-filters, and $i$ is maxIterations.
--
-- Since RedisBloom 1.0.0
cfinsert
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Cuckoo filter.
    -> NonEmpty ByteString -- ^ Items to add.
    -> m (f [CFInsertResult])
cfinsert key items = cfinsertOpts key items defaultCFInsertOpts

-- |Adds one or more items to a Cuckoo filter, creating it when needed (<https://redis.io/commands/cf.insert>).
--
-- $O(n * (k + i))$, where $n$ is the number of items, $k$ is the number of sub-filters, and $i$ is maxIterations.
--
-- Since RedisBloom 1.0.0
cfinsertOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Cuckoo filter.
    -> NonEmpty ByteString -- ^ Items to add.
    -> CFInsertOpts -- ^ Optional creation parameters.
    -> m (f [CFInsertResult])
cfinsertOpts key items opts =
    sendRequest $ ["CF.INSERT", key] ++ cfInsertOptsToArgs opts ++ ["ITEMS"] ++ NE.toList items

-- |Adds one or more items to a Cuckoo filter only if they did not already exist (<https://redis.io/commands/cf.insertnx>).
--
-- This is equivalent to inserting with default options and automatic creation enabled.
--
-- $O(n * (k + i))$, where $n$ is the number of items, $k$ is the number of sub-filters, and $i$ is maxIterations.
--
-- Since RedisBloom 1.0.0
cfinsertnx
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Cuckoo filter.
    -> NonEmpty ByteString -- ^ Items to add.
    -> m (f [CFInsertResult])
cfinsertnx key items = cfinsertnxOpts key items defaultCFInsertOpts

-- |Adds one or more items to a Cuckoo filter only if they did not already exist (<https://redis.io/commands/cf.insertnx>).
--
-- $O(n * (k + i))$, where $n$ is the number of items, $k$ is the number of sub-filters, and $i$ is maxIterations.
--
-- Since RedisBloom 1.0.0
cfinsertnxOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Cuckoo filter.
    -> NonEmpty ByteString -- ^ Items to add.
    -> CFInsertOpts -- ^ Optional creation parameters.
    -> m (f [CFInsertResult])
cfinsertnxOpts key items opts =
    sendRequest $ ["CF.INSERTNX", key] ++ cfInsertOptsToArgs opts ++ ["ITEMS"] ++ NE.toList items

-- |Checks whether one or more items may exist in a Cuckoo filter (<https://redis.io/commands/cf.mexists>).
--
-- A 'False' result means the item is definitely absent, or the key does not exist.
--
-- $O(k * n)$, where $k$ is the number of sub-filters and $n$ is the number of items.
--
-- Since RedisBloom 1.0.0
cfmexists
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Cuckoo filter.
    -> NonEmpty ByteString -- ^ Items to check.
    -> m (f [Bool])
cfmexists key items = sendRequest $ ["CF.MEXISTS", key] ++ NE.toList items

-- |Creates an empty Cuckoo filter (<https://redis.io/commands/cf.reserve>).
--
-- The filter will fail if the key already exists.
--
-- $O(1)$
--
-- Since RedisBloom 1.0.0
cfreserve
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Cuckoo filter to create.
    -> Integer -- ^ Initial capacity.
    -> m (f Status)
cfreserve key capacity = cfreserveOpts key capacity defaultCFReserveOpts

-- |Creates an empty Cuckoo filter (<https://redis.io/commands/cf.reserve>).
--
-- $O(1)$
--
-- Since RedisBloom 1.0.0
cfreserveOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the Cuckoo filter to create.
    -> Integer -- ^ Initial capacity.
    -> CFReserveOpts -- ^ Bucket and scaling options.
    -> m (f Status)
cfreserveOpts key capacity opts =
    sendRequest $ ["CF.RESERVE", key, encode capacity] ++ cfReserveOptsToArgs opts
