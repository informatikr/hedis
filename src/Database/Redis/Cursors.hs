{-# LANGUAGE OverloadedStrings, FlexibleContexts, FlexibleInstances #-}

module Database.Redis.Cursors where

import Data.ByteString (ByteString)
import Database.Redis.Core
import Database.Redis.Protocol
import Database.Redis.Types

scan
    :: (RedisCtx m f)
    => ByteString -- ^ cursor
    -> m (f (ByteString, [ByteString])) -- ^ next cursor and values
scan cursor =
    sendRequest ["SCAN", encode cursor]

sscan
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ cursor
    -> m (f (ByteString, [ByteString])) -- ^ next cursor and values
sscan key cursor =
    sendRequest ["SSCAN", encode key, encode cursor]

zscan
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ cursor
    -> m (f (ByteString, [(ByteString, Double)])) -- ^ next cursor and values
zscan key cursor =
    sendRequest ["ZSCAN", encode key, encode cursor]

hscan
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ cursor
    -> m (f (ByteString, [(ByteString, ByteString)])) -- ^ next cursor and key-value pairs
hscan key cursor =
    sendRequest ["HSCAN", encode key, encode cursor]
