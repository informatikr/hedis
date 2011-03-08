{-# LANGUAGE OverloadedStrings, TemplateHaskell #-}

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

cmd status "ping" ""
cmd bool "exists" "key"
cmd int "incr" "key"
cmd hash "hgetall" "key"
cmd list "lrange" "key start stop"
cmd status "rename" "k k'"
cmdVar set "sunion" "" "keys"
