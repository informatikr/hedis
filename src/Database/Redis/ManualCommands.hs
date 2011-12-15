{-# LANGUAGE OverloadedStrings #-}

module Database.Redis.ManualCommands where

import Control.Applicative
import Data.ByteString
import Database.Redis.Types
import Database.Redis.Internal

-- |@type@ is a keyword in Haskell, hence the command is renamed to 'getType'.
getType :: (RedisStatus a)
        => ByteString -- ^ key
        -> Redis (Maybe a)
getType key = decodeStatus <$> sendRequest ["TYPE", key]

flushall :: (RedisStatus a) => Redis (Maybe a)
flushall = decodeStatus <$> sendRequest ["FLUSHALL"]

select :: (RedisStatus a) => ByteString -> Redis (Maybe a)
select db = decodeStatus <$> sendRequest ["SELECT", db]

sadd :: (RedisInt a) => ByteString -> [ByteString] -> Redis (Maybe a)
sadd key members = decodeInt <$> sendRequest (["SADD", key] ++ members)

-- TODO supports multiple args
zadd :: (RedisInt a) => ByteString -> ByteString -> ByteString -> Redis (Maybe a)
zadd key score member = decodeInt <$> sendRequest ["ZADD", key, score, member]
