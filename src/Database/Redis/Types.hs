{-# LANGUAGE FlexibleInstances, UndecidableInstances, OverlappingInstances,
        TypeSynonymInstances, DeriveDataTypeable #-}

module Database.Redis.Types where

import Control.Applicative
import Control.Exception
import Control.Monad
import Data.ByteString.Char8 (ByteString, unpack, pack)
import Data.ByteString.Lex.Double (readDouble)
import Data.Maybe
import Data.Typeable
import Database.Redis.Reply


------------------------------------------------------------------------------
-- Classes of types Redis understands
--
class RedisArg a where
    encode :: a -> ByteString

class RedisResult a where
    decode :: Reply -> Either ResultError a

data ResultError = ResultError
    deriving (Show, Typeable)

instance Exception ResultError

------------------------------------------------------------------------------
-- RedisArg instances
--
instance RedisArg ByteString where
    encode = id

instance RedisArg Integer where
    encode = pack . show
    
instance RedisArg Int where
    encode = pack . show

instance RedisArg Double where
    encode = pack . show

------------------------------------------------------------------------------
-- RedisResult instances
--
data Status = Ok | Pong | None | String | Hash | List | Set | ZSet | Queued
    deriving (Show, Eq)

instance RedisResult () where
    decode _ = Right ()

-- |'decode'ing to 'Maybe' will never throw a 'ResultError'. It is, however,
--  ambiguous wether the command returned @nil@ or wether decoding failed.
instance (RedisResult a) => RedisResult (Maybe a) where
    decode (Bulk Nothing) = Right Nothing
    decode r              = Right $ either (const Nothing) Just (decode r)

instance RedisResult ByteString where
    decode (SingleLine s)  = Right s
    decode (Bulk (Just s)) = Right s
    decode _               = Left ResultError

instance RedisResult Integer where
    decode (Integer n) = Right n
    decode _           = Left ResultError

instance RedisResult Int where
    decode (Integer n) = Right (fromInteger n)
    decode _           = Left ResultError

instance RedisResult Double where
    decode s = maybe (Left ResultError) (Right . fst) . readDouble =<< decode s

instance RedisResult String where
    decode = liftM unpack . decode

instance RedisResult Status where
    decode r = do
        s <- decode r
        return $ case s of
            "OK"     -> Ok
            "PONG"   -> Pong
            "none"   -> None
            "string" -> String
            "hash"   -> Hash
            "list"   -> List
            "set"    -> Set
            "zset"   -> ZSet
            "QUEUED" -> Queued
            _        -> error $ "unhandled status-code: " ++ s

instance RedisResult Bool where
    decode (Integer 1) = Right True
    decode (Integer 0) = Right False
    decode _           = Left ResultError


instance RedisResult a => RedisResult [a] where
    decode (MultiBulk (Just rs)) = mapM decode rs
    decode _                     = Left ResultError
        
instance (RedisResult k, RedisResult v) => RedisResult [(k,v)] where
    decode r = case r of
                (MultiBulk (Just rs)) -> pairs rs
                _                     -> Left ResultError
      where
        pairs []         = Right []
        pairs (_:[])     = Left ResultError
        pairs (r1:r2:rs) = do
            k   <- decode r1
            v   <- decode r2
            kvs <- pairs rs
            return $ (k,v) : kvs    

instance (RedisResult a, RedisResult b) => RedisResult (a,b) where
    decode (MultiBulk (Just [x, y])) = (,) <$> decode x <*> decode y
    decode _                         = Left ResultError
