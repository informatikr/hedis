{-# LANGUAGE OverloadedStrings, FlexibleInstances,
    UndecidableInstances, OverlappingInstances #-}

module Database.Redis (
    module Database.Redis.Internal,
    module Database.Redis.Reply,
    module Database.Redis.PubSub,
    RedisBool,
    RedisInt,
    RedisKey,
    RedisValue,
    RedisHash,
    exists, incr, hgetall, lrange, sunion
) where

import Control.Applicative
import Control.Monad
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.ByteString
import Database.Redis.Internal
import Database.Redis.PubSub
import Database.Redis.Reply


------------------------------------------------------------------------------
-- Classes of types Redis understands
--
class RedisBool a where
    decodeBool :: Reply -> Maybe a

class RedisInt a where
    decodeInt :: Reply -> Maybe a

class RedisKey a where
    decodeKey :: Reply -> Maybe a

class RedisValue a where
    decodeValue :: Reply -> Maybe a

class RedisList a where
    decodeList :: Reply -> Maybe a

class RedisSet a where
    decodeSet :: Reply -> Maybe a

class RedisHash a where
    decodeHash :: Reply -> Maybe a


------------------------------------------------------------------------------
-- Redis commands
--
exists :: RedisBool a => ByteString -> Redis (Maybe a)
exists key = decodeBool <$> sendRequest ["EXISTS", key]

incr :: RedisInt a => ByteString -> Redis (Maybe a)
incr key = decodeInt <$> sendRequest ["INCR", key]

hgetall :: RedisHash a => ByteString -> Redis (Maybe a)
hgetall key = decodeHash <$> sendRequest ["HGETALL", key]

lrange :: RedisList a =>
          ByteString -> ByteString -> ByteString -> Redis (Maybe a)
lrange key start stop =
    decodeList <$> sendRequest ["LRANGE", key, start, stop]

sunion :: RedisSet a => [ByteString] -> Redis (Maybe a)
sunion keys = decodeSet <$> sendRequest ("SUNION" : keys)


------------------------------------------------------------------------------
-- RedisBool instances
--
instance RedisBool Bool where
    decodeBool (Integer 1) = Just True
    decodeBool (Integer 0) = Just False
    decodeBool _           = Nothing

instance (Num a) => (RedisBool a) where
    decodeBool (Integer 1) = Just 1
    decodeBool (Integer 0) = Just 0
    decodeBool _           = Nothing


------------------------------------------------------------------------------
-- RedisInt instances
--
instance (Integral a) => RedisInt a where
    decodeInt (Integer i) = Just $ fromIntegral i
    decodeInt _           = Nothing


------------------------------------------------------------------------------
-- RedisKey instances
--
instance RedisKey ByteString where
    decodeKey (Bulk k) = k
    decodeKey _        = Nothing


------------------------------------------------------------------------------
-- RedisValue instances
--
instance RedisValue ByteString where
    decodeValue (Bulk v) = v
    decodeValue _        = Nothing


------------------------------------------------------------------------------
-- RedisList instances
--
instance RedisValue a => RedisList [a] where
    decodeList (MultiBulk (Just rs)) = mapM decodeValue rs
    decodeList _                     = Nothing


------------------------------------------------------------------------------
-- RedisSet instances
--
instance (Ord a, RedisValue a) => RedisSet (Set.Set a) where
    decodeSet = liftM Set.fromList . decodeList

instance (RedisValue a) => RedisSet [a] where
    decodeSet = decodeList


------------------------------------------------------------------------------
-- RedisHash instances
--
instance (RedisKey k, RedisValue v) => RedisHash [(k,v)] where
    decodeHash reply = 
        case reply of
            (MultiBulk (Just rs)) -> pairs rs
            _                     -> Nothing
      where
        pairs []         = Just []
        pairs (_:[])     = Nothing
        pairs (r1:r2:rs) =
            let kv = (,) <$> decodeKey r1 <*> decodeValue r2
            in (:) <$> kv <*> pairs rs

instance (Ord k , RedisKey k, RedisValue v) => RedisHash (Map.Map k v) where
    decodeHash = liftM Map.fromList . decodeHash
