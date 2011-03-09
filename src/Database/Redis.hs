{-# LANGUAGE OverloadedStrings, TemplateHaskell, CPP #-}

module Database.Redis (
    module Database.Redis.Internal,
    module Database.Redis.Reply,
    module Database.Redis.PubSub,
    module Database.Redis.Types,
    -- * Commands
    -- ** Keys
    del, exists, expire, expireat, keys, move, persist, randomkey, rename,
    renamex, ttl,
    -- ** Strings
    append, decr, decrby, get, getbit, getrange, getset, incr, incrby, mget,
    mset, msetnx, set, setbit, setex, setnx, setrange, strlen,
    -- ** Other
    hgetall, lrange, sunion, ping, flushall
) where

import Control.Applicative
import Data.ByteString (ByteString)
import Database.Redis.CommandTemplates
import Database.Redis.Internal
import Database.Redis.PubSub
import Database.Redis.Reply
import Database.Redis.Types

------------------------------------------------------------------------------
-- Redis commands
--

#define comment(cmd) Redis Command, see <http://redis.io/commands/cmd>


cmdVar intRT "del" "" "ks"
cmd boolRT "exists" "key"
cmd boolRT "expire" "key seconds"
cmd boolRT "expireat" "key timestamp"
cmd listRT "keys" "pattern"
cmd boolRT "move" "key db"
cmd boolRT "persist" "key"
cmd keyRT "randomkey" ""
cmd statusRT "rename" "key newkey"
cmd boolRT "renamex" "key newkey"
cmd intRT "ttl" "key"

cmd intRT "append" "key value"
cmd intRT "decr" "key"
cmd intRT "decrby" "key decrement"
cmd valueRT "get" "key"
cmd intRT "getbit" "key offset"
cmd valueRT "getrange" "key start end"
cmd valueRT "getset" "key value"
cmd intRT "incr" "key"
cmd intRT "incrby" "key increment"
cmdVar listRT "mget" "" "ks"
cmdVar statusRT "mset" "" "keysvalues"
cmdVar boolRT "msetnx" "" "keysvalues"
cmd statusRT "set" "key value"
cmd intRT "setbit" "key offset value"
cmd statusRT "setex" "key seconds value"
cmd boolRT "setnx" "key value"
cmd intRT "setrange" "key offset value"
cmd intRT "strlen" "key"



-- TODO sort, type
-- TODO what about commands taking varArg _PAIRS_ (mset)

{- |comment(ping) -}
cmd statusRT "ping" ""

{- |comment(hgetall) -}
cmd hashRT "hgetall" "key"

{- |comment(lrange) -}
cmd listRT "lrange" "key start stop"

{- |comment(sunion) -}
cmdVar setRT "sunion" "" "ks"

cmd statusRT "flushall" ""