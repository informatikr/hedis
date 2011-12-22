{-# LANGUAGE FlexibleInstances, UndecidableInstances, OverlappingInstances,
        TypeSynonymInstances #-}

module Database.Redis.Types where

import Control.Applicative
import Control.Monad
import Data.ByteString.Char8 (ByteString, unpack, pack)
import Data.ByteString.Lex.Double (readDouble)
import Data.Maybe
import qualified Data.Map as Map
import qualified Data.Set as Set
import Database.Redis.Reply


------------------------------------------------------------------------------
-- Classes of types Redis understands
--
class RedisArgString a where
    encodeString :: a -> ByteString

class RedisArgInt a where
    encodeInt :: a -> ByteString

class RedisArgDouble a where
    encodeDouble :: a -> ByteString


class RedisReturnStatus a where
    decodeStatus :: Reply -> Maybe a

class RedisReturnBool a where
    decodeBool :: Reply -> Maybe a

class RedisReturnInt a where
    decodeInt :: Reply -> Maybe a

class RedisReturnDouble a where
    decodeDouble :: Reply -> Maybe a

class RedisReturnKey a where
    decodeKey :: Reply -> Maybe a

class RedisReturnString a where
    decodeString :: Reply -> Maybe a

class RedisReturnList a where
    decodeList :: Reply -> Maybe a

class RedisReturnSet a where
    decodeSet :: Reply -> Maybe a

class RedisReturnHash a where
    decodeHash :: Reply -> Maybe a

class RedisReturnPair a where
    decodePair :: Reply -> Maybe a


------------------------------------------------------------------------------
-- RedisArgString instances
--
instance RedisArgString ByteString where
    encodeString = id


------------------------------------------------------------------------------
-- RedisArgInt instances
--
instance (Integral a) => RedisArgInt a where
    encodeInt = pack . show . toInteger


------------------------------------------------------------------------------
-- RedisArgDouble instances
--
instance RedisArgDouble Double where
    encodeDouble = pack . show


------------------------------------------------------------------------------
-- RedisReturnStatus instances
--
data Status = Ok | Pong | None | String | Hash | List | Set | ZSet
    deriving (Show, Eq)

instance RedisReturnStatus ByteString where
    decodeStatus (SingleLine s) = Just s
    decodeStatus _              = Nothing

instance RedisReturnStatus String where
    decodeStatus = liftM unpack . decodeStatus

instance RedisReturnStatus Status where
    decodeStatus r = do
        s <- decodeStatus r
        return $ case s of
            "OK"     -> Ok
            "PONG"   -> Pong
            "none"   -> None
            "string" -> String
            "hash"   -> Hash
            "list"   -> List
            "set"    -> Set
            "zset"   -> ZSet
            _        -> error $ "unhandled status-code: " ++ s


------------------------------------------------------------------------------
-- RedisReturnBool instances
--
instance RedisReturnBool Bool where
    decodeBool (Integer 1) = Just True
    decodeBool (Integer 0) = Just False
    decodeBool _           = Nothing

instance (Num a) => (RedisReturnBool a) where
    decodeBool (Integer 1) = Just 1
    decodeBool (Integer 0) = Just 0
    decodeBool _           = Nothing


------------------------------------------------------------------------------
-- RedisReturnInt instances
--
instance (Integral a) => RedisReturnInt a where
    decodeInt (Integer i) = Just $ fromIntegral i
    decodeInt _           = Nothing


------------------------------------------------------------------------------
-- RedisReturnDouble instances
--
instance RedisReturnDouble Double where
    decodeDouble s = fst <$> (readDouble =<< decodeString s)


------------------------------------------------------------------------------
-- RedisReturnKey instances
--
instance RedisReturnKey ByteString where
    decodeKey (Bulk k) = k
    decodeKey _        = Nothing


------------------------------------------------------------------------------
-- RedisReturnString instances
--
instance RedisReturnString ByteString where
    decodeString (Bulk v) = v
    decodeString _        = Nothing


------------------------------------------------------------------------------
-- RedisReturnList instances
--
instance RedisReturnString a => RedisReturnList [Maybe a] where
    decodeList (MultiBulk (Just rs)) = Just $ map decodeString rs
    decodeList _                     = Nothing


------------------------------------------------------------------------------
-- RedisReturnSet instances
--
instance (Ord a, RedisReturnString a) => RedisReturnSet (Set.Set a) where
    decodeSet = liftM Set.fromList . decodeSet

instance (RedisReturnString a) => RedisReturnSet [a] where
    decodeSet r = catMaybes <$> decodeList r


------------------------------------------------------------------------------
-- RedisReturnHash instances
--
instance (RedisReturnKey k, RedisReturnString v) =>
        RedisReturnHash [(k,v)] where
    decodeHash reply = 
        case reply of
            (MultiBulk (Just rs)) -> pairs rs
            _                     -> Nothing
      where
        pairs []         = Just []
        pairs (_:[])     = Nothing
        pairs (r1:r2:rs) =
            let kv = (,) <$> decodeKey r1 <*> decodeString r2
            in (:) <$> kv <*> pairs rs

instance (Ord k , RedisReturnKey k, RedisReturnString v) =>
        RedisReturnHash (Map.Map k v) where
    decodeHash = liftM Map.fromList . decodeHash


------------------------------------------------------------------------------
-- RedisReturnPair instances
--
instance (RedisReturnString a, RedisReturnString b) =>
        RedisReturnPair (a,b) where
    decodePair (MultiBulk (Just [x, y])) =
        (,) <$> decodeString x <*> decodeString y
    decodePair _          = Nothing
