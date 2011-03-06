{-# LANGUAGE OverloadedStrings #-}

module Database.Redis (
    module Database.Redis.Internal,
    module Database.Redis.Reply,
    module Database.Redis.PubSub,
    module Database.Redis.Types,
    exists, incr, hgetall, lrange, sunion, ping, rename
) where

import Control.Applicative
import Data.ByteString
import Database.Redis.CommandTemplates
import Database.Redis.Internal
import Database.Redis.PubSub
import Database.Redis.Reply
import Database.Redis.Types

------------------------------------------------------------------------------
-- Redis commands
--
cmd "exists" "key" bool

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

ping :: RedisStatus a => Redis (Maybe a)
ping = decodeStatus <$> sendRequest ["PING"]

rename :: RedisStatus a => ByteString -> ByteString -> Redis (Maybe a)
rename k k' = decodeStatus <$> sendRequest ["RENAME", k, k']
