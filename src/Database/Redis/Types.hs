{-# LANGUAGE FlexibleInstances, UndecidableInstances, OverlappingInstances #-}

module Database.Redis.Types where

import Control.Applicative
import Control.Monad
import Data.ByteString
import qualified Data.Map as Map
import qualified Data.Set as Set
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
