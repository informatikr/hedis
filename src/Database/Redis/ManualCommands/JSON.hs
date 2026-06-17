{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Database.Redis.ManualCommands.JSON where

import Data.ByteString (ByteString)
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE

import Database.Redis.Core
import Database.Redis.Protocol
import Database.Redis.Types

data JSONGetOpts = JSONGetOpts
    { jsonGetIndent :: Maybe ByteString
    , jsonGetNewline :: Maybe ByteString
    , jsonGetSpace :: Maybe ByteString
    , jsonGetPaths :: [ByteString]
    } deriving (Show, Eq)

defaultJSONGetOpts :: JSONGetOpts
defaultJSONGetOpts = JSONGetOpts
    { jsonGetIndent = Nothing
    , jsonGetNewline = Nothing
    , jsonGetSpace = Nothing
    , jsonGetPaths = []
    }

data JSONSetCondition
    = JSONSetIfNotExists
    | JSONSetIfExists
    deriving (Show, Eq)

instance RedisArg JSONSetCondition where
    encode JSONSetIfNotExists = "NX"
    encode JSONSetIfExists = "XX"

data JSONSetFPHA
    = JSONSetFP16
    | JSONSetBF16
    | JSONSetFP32
    | JSONSetFP64
    deriving (Show, Eq)

instance RedisArg JSONSetFPHA where
    encode JSONSetFP16 = "FP16"
    encode JSONSetBF16 = "BF16"
    encode JSONSetFP32 = "FP32"
    encode JSONSetFP64 = "FP64"

data JSONSetOpts = JSONSetOpts
    { jsonSetCondition :: Maybe JSONSetCondition
    , jsonSetFPHA :: Maybe JSONSetFPHA
    } deriving (Show, Eq)

defaultJSONSetOpts :: JSONSetOpts
defaultJSONSetOpts = JSONSetOpts
    { jsonSetCondition = Nothing
    , jsonSetFPHA = Nothing
    }

data JSONArrIndexOpts
    = JSONArrIndexAll
    | JSONArrIndexFrom Integer
    | JSONArrIndexFromTo Integer Integer
    deriving (Show, Eq)

defaultJSONArrIndexOpts :: JSONArrIndexOpts
defaultJSONArrIndexOpts = JSONArrIndexAll

jsonGetOptsToArgs :: JSONGetOpts -> [ByteString]
jsonGetOptsToArgs JSONGetOpts{..} =
    indentArg ++ newlineArg ++ spaceArg ++ jsonGetPaths
  where
    indentArg = maybe [] (\indent -> ["INDENT", indent]) jsonGetIndent
    newlineArg = maybe [] (\newline -> ["NEWLINE", newline]) jsonGetNewline
    spaceArg = maybe [] (\space -> ["SPACE", space]) jsonGetSpace

jsonSetOptsToArgs :: JSONSetOpts -> [ByteString]
jsonSetOptsToArgs JSONSetOpts{..} =
    conditionArg ++ fphaArg
  where
    conditionArg = maybe [] (\condition -> [encode condition]) jsonSetCondition
    fphaArg = maybe [] (\fpha -> ["FPHA", encode fpha]) jsonSetFPHA

jsonArrIndexOptsToArgs :: JSONArrIndexOpts -> [ByteString]
jsonArrIndexOptsToArgs JSONArrIndexAll = []
jsonArrIndexOptsToArgs (JSONArrIndexFrom start) = [encode start]
jsonArrIndexOptsToArgs (JSONArrIndexFromTo start stop) = [encode start, encode stop]

-- |Appends one or more JSON values into the array at path after the last element in it (<https://redis.io/commands/json.arrappend>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(1)/ when path is evaluated to a single value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonArrappend
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to the array.
    -> NonEmpty ByteString -- ^ Serialized JSON values to append.
    -> m (f Reply)
jsonArrappend key path values =
    sendRequest $ ["JSON.ARRAPPEND", key, path] ++ NE.toList values

-- |Returns the index of the first occurrence of a JSON scalar value in the array at path (<https://redis.io/commands/json.arrindex>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(N)/ when path is evaluated to a single value where /N/ is the size of the array, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonArrindex
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to the array.
    -> ByteString -- ^ Serialized JSON scalar to search for.
    -> m (f Reply)
jsonArrindex key path value = jsonArrindexOpts key path value defaultJSONArrIndexOpts

-- |Returns the index of the first occurrence of a JSON scalar value in the array at path (<https://redis.io/commands/json.arrindex>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(N)/ when path is evaluated to a single value where /N/ is the size of the array, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonArrindexOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to the array.
    -> ByteString -- ^ Serialized JSON scalar to search for.
    -> JSONArrIndexOpts -- ^ Optional search range.
    -> m (f Reply)
jsonArrindexOpts key path value opts =
    sendRequest $ ["JSON.ARRINDEX", key, path, value] ++ jsonArrIndexOptsToArgs opts

-- |Returns the length of the array at the root path (<https://redis.io/commands/json.arrlen>).
--
-- /O(1)/ where path is evaluated to a single value, /O(N)/ where path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonArrlen
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> m (f Reply)
jsonArrlen key = sendRequest ["JSON.ARRLEN", key]

-- |Returns the length of the array at path (<https://redis.io/commands/json.arrlen>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(1)/ where path is evaluated to a single value, /O(N)/ where path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonArrlenAt
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to the array.
    -> m (f Reply)
jsonArrlenAt key path = sendRequest ["JSON.ARRLEN", key, path]

-- |Inserts the JSON scalar(s) value at the specified index in the array at path (<https://redis.io/commands/json.arrinsert>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(N)/ when path is evaluated to a single value where /N/ is the size of the array, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonArrinsert
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to the array.
    -> Integer -- ^ Insertion index.
    -> NonEmpty ByteString -- ^ Serialized JSON values to insert.
    -> m (f Reply)
jsonArrinsert key path index values =
    sendRequest $ ["JSON.ARRINSERT", key, path, encode index] ++ NE.toList values

-- |Removes and returns the element at the end of the array at the root path (<https://redis.io/commands/json.arrpop>).
--
-- /O(1)/ when the popped item is the last element, otherwise /O(N)/ where /N/ is the size of the array
--
-- Since RedisJSON 1.0.0
jsonArrpop
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> m (f Reply)
jsonArrpop key = sendRequest ["JSON.ARRPOP", key]

-- |Removes and returns the element at the end of the array at path (<https://redis.io/commands/json.arrpop>).
--
-- The reply shape depends on the path syntax and popped value type, so this wrapper returns the raw 'Reply'.
--
-- /O(1)/ when the popped item is the last element, otherwise /O(N)/ where /N/ is the size of the array
--
-- Since RedisJSON 1.0.0
jsonArrpopAt
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to the array.
    -> m (f Reply)
jsonArrpopAt key path = sendRequest ["JSON.ARRPOP", key, path]

-- |Removes and returns the element at the specified index in the array at path (<https://redis.io/commands/json.arrpop>).
--
-- The reply shape depends on the path syntax and popped value type, so this wrapper returns the raw 'Reply'.
--
-- /O(N)/ when the specified index is not the last element, otherwise /O(1)/
--
-- Since RedisJSON 1.0.0
jsonArrpopAtIndex
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to the array.
    -> Integer -- ^ Index to pop.
    -> m (f Reply)
jsonArrpopAtIndex key path index =
    sendRequest ["JSON.ARRPOP", key, path, encode index]

-- |Trims the array at path to contain only the specified inclusive range of indices from start to stop (<https://redis.io/commands/json.arrtrim>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(N)/ when path is evaluated to a single value where /N/ is the size of the array, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonArrtrim
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to the array.
    -> Integer -- ^ Start index.
    -> Integer -- ^ Stop index.
    -> m (f Reply)
jsonArrtrim key path start stop =
    sendRequest ["JSON.ARRTRIM", key, path, encode start, encode stop]

-- |Clears all values from an array or an object and sets numeric values at the root path to @0@ (<https://redis.io/commands/json.clear>).
--
-- /O(N)/ when path is evaluated to a single value where /N/ is the size of the values, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 2.0.0
jsonClear
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> m (f Integer)
jsonClear key = sendRequest ["JSON.CLEAR", key]

-- |Clears all values from an array or an object and sets numeric values at path to @0@ (<https://redis.io/commands/json.clear>).
--
-- /O(N)/ when path is evaluated to a single value where /N/ is the size of the values, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 2.0.0
jsonClearAt
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to clear.
    -> m (f Integer)
jsonClearAt key path = sendRequest ["JSON.CLEAR", key, path]

-- |Executes the JSON debug container command (<https://redis.io/commands/json.debug>).
--
-- This is a container command for debugging related tasks.
--
-- N\/A
--
-- Since RedisJSON 1.0.0
jsonDebug
    :: (RedisCtx m f)
    => m (f Reply)
jsonDebug = sendRequest ["JSON.DEBUG"]

-- |Reports the size in bytes of a key at the root path (<https://redis.io/commands/json.debug-memory>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(N)/ when path is evaluated to a single value, where /N/ is the size of the value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonDebugMemory
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> m (f Reply)
jsonDebugMemory key = sendRequest ["JSON.DEBUG", "MEMORY", key]

-- |Reports the size in bytes of a key at path (<https://redis.io/commands/json.debug-memory>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(N)/ when path is evaluated to a single value, where /N/ is the size of the value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonDebugMemoryAt
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to inspect.
    -> m (f Reply)
jsonDebugMemoryAt key path = sendRequest ["JSON.DEBUG", "MEMORY", key, path]

-- |Deletes a value at the root path (<https://redis.io/commands/json.del>).
--
-- /O(N)/ when path is evaluated to a single value where /N/ is the size of the deleted value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonDel
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> m (f Integer)
jsonDel key = sendRequest ["JSON.DEL", key]

-- |Deletes a value at path (<https://redis.io/commands/json.del>).
--
-- /O(N)/ when path is evaluated to a single value where /N/ is the size of the deleted value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonDelAt
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to delete.
    -> m (f Integer)
jsonDelAt key path = sendRequest ["JSON.DEL", key, path]

-- |Deletes a value at the root path (<https://redis.io/commands/json.forget>).
--
-- /O(N)/ when path is evaluated to a single value where /N/ is the size of the deleted value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonForget
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> m (f Integer)
jsonForget key = sendRequest ["JSON.FORGET", key]

-- |Deletes a value at path (<https://redis.io/commands/json.forget>).
--
-- /O(N)/ when path is evaluated to a single value where /N/ is the size of the deleted value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonForgetAt
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to delete.
    -> m (f Integer)
jsonForgetAt key path = sendRequest ["JSON.FORGET", key, path]

-- |Gets the value at the root path in JSON serialized form (<https://redis.io/commands/json.get>).
--
-- /O(N)/ when path is evaluated to a single value where /N/ is the size of the value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonGet
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> m (f (Maybe ByteString))
jsonGet key = jsonGetOpts key defaultJSONGetOpts

-- |Gets the value at one or more paths in JSON serialized form (<https://redis.io/commands/json.get>).
--
-- /O(N)/ when path is evaluated to a single value where /N/ is the size of the value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonGetOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> JSONGetOpts -- ^ Formatting and path selection options.
    -> m (f (Maybe ByteString))
jsonGetOpts key opts =
    sendRequest $ ["JSON.GET", key] ++ jsonGetOptsToArgs opts

-- |Merges a given JSON value into matching paths (<https://redis.io/commands/json.merge>).
--
-- Consequently, JSON values at matching paths are updated, deleted, or expanded with new children.
--
-- /O(M+N)/ when path is evaluated to a single value where /M/ is the size of the original value and /N/ is the size of the new value, /O(M+N)/ when path is evaluated to multiple values where /M/ is the size of the key and /N/ is the size of the new value times the number of matches
--
-- Since RedisJSON 2.6.0
jsonMerge
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to merge into.
    -> ByteString -- ^ Serialized JSON value.
    -> m (f Status)
jsonMerge key path value = sendRequest ["JSON.MERGE", key, path, value]

-- |Returns the values at a path from one or more keys (<https://redis.io/commands/json.mget>).
--
-- /O(M*N)/ when path is evaluated to a single value where /M/ is the number of keys and /N/ is the size of the value, /O(N1+N2+\dots+Nm)/ when path is evaluated to multiple values
--
-- Since RedisJSON 1.0.0
jsonMget
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ Keys holding JSON values.
    -> ByteString -- ^ Path to fetch from each key.
    -> m (f [Maybe ByteString])
jsonMget keys path = sendRequest $ "JSON.MGET" : NE.toList keys ++ [path]

-- |Sets or updates the JSON value of one or more keys (<https://redis.io/commands/json.mset>).
--
-- /O(K*(M+N))/ where /K/ is the number of keys in the command
--
-- Since RedisJSON 2.6.0
jsonMset
    :: (RedisCtx m f)
    => NonEmpty (ByteString, ByteString, ByteString) -- ^ Key, path, serialized JSON value triplets.
    -> m (f Status)
jsonMset triplets =
    sendRequest $ "JSON.MSET" : concatMap encodeTriplet (NE.toList triplets)
  where
    encodeTriplet (key, path, value) = [key, path, value]

-- |Increments the numeric value at path by a value (<https://redis.io/commands/json.numincrby>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(1)/ when path is evaluated to a single value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonNumincrby
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to the numeric value.
    -> Double -- ^ Increment value.
    -> m (f Reply)
jsonNumincrby key path value =
    sendRequest ["JSON.NUMINCRBY", key, path, encode value]

-- |Multiplies the numeric value at path by a value (<https://redis.io/commands/json.nummultby>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(1)/ when path is evaluated to a single value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonNummultby
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to the numeric value.
    -> Double -- ^ Multiplier value.
    -> m (f Reply)
jsonNummultby key path value =
    sendRequest ["JSON.NUMMULTBY", key, path, encode value]

-- |Returns the key names of JSON objects at the root path (<https://redis.io/commands/json.objkeys>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(N)/ when path is evaluated to a single value, where /N/ is the number of keys in the object, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonObjkeys
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> m (f Reply)
jsonObjkeys key = sendRequest ["JSON.OBJKEYS", key]

-- |Returns the key names of JSON objects at path (<https://redis.io/commands/json.objkeys>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(N)/ when path is evaluated to a single value, where /N/ is the number of keys in the object, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonObjkeysAt
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to the object.
    -> m (f Reply)
jsonObjkeysAt key path = sendRequest ["JSON.OBJKEYS", key, path]

-- |Returns the number of keys in JSON objects at the root path (<https://redis.io/commands/json.objlen>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(1)/ when path is evaluated to a single value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonObjlen
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> m (f Reply)
jsonObjlen key = sendRequest ["JSON.OBJLEN", key]

-- |Returns the number of keys in JSON objects at path (<https://redis.io/commands/json.objlen>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(1)/ when path is evaluated to a single value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonObjlenAt
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to the object.
    -> m (f Reply)
jsonObjlenAt key path = sendRequest ["JSON.OBJLEN", key, path]

-- |Returns the JSON value at the root path in Redis Serialization Protocol (RESP) (<https://redis.io/commands/json.resp>).
--
-- The reply may be any RESP shape depending on the JSON value, so this wrapper returns the raw 'Reply'.
--
-- /O(N)/ when path is evaluated to a single value, where /N/ is the size of the value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonResp
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> m (f Reply)
jsonResp key = sendRequest ["JSON.RESP", key]

-- |Returns the JSON value at path in Redis Serialization Protocol (RESP) (<https://redis.io/commands/json.resp>).
--
-- The reply may be any RESP shape depending on the JSON value, so this wrapper returns the raw 'Reply'.
--
-- /O(N)/ when path is evaluated to a single value, where /N/ is the size of the value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonRespAt
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to inspect.
    -> m (f Reply)
jsonRespAt key path = sendRequest ["JSON.RESP", key, path]

-- |Sets or updates the JSON value at a path (<https://redis.io/commands/json.set>).
--
-- $O(M+N)$ when path is evaluated to a single value where $M$ is the size of the original value and $N$ is the size of the new value, $O(M+N)$ when path is evaluated to multiple values where $M$ is the size of the key and $N$ is the size of the new value times the number of matches
--
-- Since RedisJSON 1.0.0
jsonSet
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to set.
    -> ByteString -- ^ Serialized JSON value.
    -> m (f (Maybe Status))
jsonSet key path value = jsonSetOpts key path value defaultJSONSetOpts

-- |Sets or updates the JSON value at a path (<https://redis.io/commands/json.set>).
--
-- /O(M+N)/ when path is evaluated to a single value where /M/ is the size of the original value and /N/ is the size of the new value, /O(M+N)/ when path is evaluated to multiple values where /M/ is the size of the key and /N/ is the size of the new value times the number of matches
--
-- Since RedisJSON 1.0.0
jsonSetOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to set.
    -> ByteString -- ^ Serialized JSON value.
    -> JSONSetOpts -- ^ Conditional and FPHA options.
    -> m (f (Maybe Status))
jsonSetOpts key path value opts =
    sendRequest $ ["JSON.SET", key, path, value] ++ jsonSetOptsToArgs opts

-- |Appends a string to JSON strings at the root path (<https://redis.io/commands/json.strappend>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(1)/ when path is evaluated to a single value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonStrappend
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ String value to append.
    -> m (f Reply)
jsonStrappend key value = sendRequest ["JSON.STRAPPEND", key, value]

-- |Appends a string to JSON strings at path (<https://redis.io/commands/json.strappend>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(1)/ when path is evaluated to a single value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonStrappendAt
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to the JSON string.
    -> ByteString -- ^ String value to append.
    -> m (f Reply)
jsonStrappendAt key path value = sendRequest ["JSON.STRAPPEND", key, path, value]

-- |Toggles a boolean value (<https://redis.io/commands/json.toggle>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(1)/ when path is evaluated to a single value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 2.0.0
jsonToggle
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to the boolean value.
    -> m (f Reply)
jsonToggle key path = sendRequest ["JSON.TOGGLE", key, path]

-- |Returns the type of the JSON value at the root path (<https://redis.io/commands/json.type>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(1)/ when path is evaluated to a single value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonType
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> m (f Reply)
jsonType key = sendRequest ["JSON.TYPE", key]

-- |Returns the type of the JSON value at path (<https://redis.io/commands/json.type>).
--
-- The reply shape depends on the path syntax, so this wrapper returns the raw 'Reply'.
--
-- /O(1)/ when path is evaluated to a single value, /O(N)/ when path is evaluated to multiple values, where /N/ is the size of the key
--
-- Since RedisJSON 1.0.0
jsonTypeAt
    :: (RedisCtx m f)
    => ByteString -- ^ Key holding a JSON value.
    -> ByteString -- ^ Path to inspect.
    -> m (f Reply)
jsonTypeAt key path = sendRequest ["JSON.TYPE", key, path]
