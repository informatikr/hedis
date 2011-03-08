{-# LANGUAGE OverloadedStrings, TemplateHaskell, CPP #-}

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

#define comment(cmd) Redis Command, see <http://redis.io/commands/cmd>

{- |comment(ping) -}
cmd status "ping" ""

{- |comment(exists) -}
cmd bool "exists" "key"

{- |comment(incr) -}
cmd int "incr" "key"

{- |comment(hgetall) -}
cmd hash "hgetall" "key"

{- |comment(lrange) -}
cmd list "lrange" "key start stop"

{- |comment(rename) -}
cmd status "rename" "k k'"

{- |comment(sunion) -}
cmdVar set "sunion" "" "keys"
