{-# LANGUAGE OverloadedStrings, FlexibleContexts, OverloadedLists #-}

module Database.Redis.Commands (

-- ** Connection

-- *** auth
-- $auth
auth,
authOpts,
AuthOpts(..),
defaultAuthOpts,
-- *** Other commands
echo,
ping,
quit,
select,

-- ** Keys
del,
dump,
exists,
expire,
ExpireOpts(..),
expireOpts,
expireat,
expireatOpts,
keys,
MigrateOpts(..),
defaultMigrateOpts,
migrate,
migrateMultiple,
move,
objectRefcount,
objectEncoding,
objectIdletime,
persist,
pexpire,
pexpireat,
pexpireatOpts,
pttl,
randomkey,
rename,
renamenx,
restore,
restoreReplace,
Cursor,
cursor0,
ScanOpts(..),
defaultScanOpts,
scan,
scanOpts,
SortOpts(..),
defaultSortOpts,
SortOrder(..),
sort,
sortStore,
ttl,
RedisType(..),
getType,
wait,

-- ** Hashes
hdel,
hexists,
hget,
hgetall,
hincrby,
hincrbyfloat,
hkeys,
hlen,
hmget,
hmset,
hscan,
hscanOpts,
hset,
hsetnx,
hstrlen,
hvals,

-- ** HyperLogLogs
pfadd, 
pfcount,
pfmerge,

-- ** Lists
blpop, 
blpopFloat,
brpop,
brpopFloat,
brpoplpush,
lindex,
linsertBefore,
linsertAfter,
llen,
lpop,
lpopCount,
lpush,
lpushx,
lrange,
lrem,
lset,
ltrim,
rpop, 
rpopCount,
rpoplpush,
rpush,
rpushx,

-- ** Scripting
eval,
evalsha,
DebugMode,
scriptDebug,
scriptExists,
scriptFlush,
scriptKill,
scriptLoad,

-- ** Server
bgrewriteaof,
bgsave,
bgsaveSchedule,
clientGetname,
clientId,
clientList,
clientPause,
ReplyMode,
clientReply,
clientSetname,
commandCount,
commandInfo,
configGet,
configResetstat,
configRewrite,
configSet,
dbsize,
debugObject,
flushall,
flushallOpts,
FlushOpts(..),
flushdb,
flushdbOpts,
info, -- |Get information and statistics about the server (<http://redis.io/commands/info>). The Redis command @INFO@ is split up into 'info', 'infoSection'. Since Redis 1.0.0
infoSection, -- |Get information and statistics about the server (<http://redis.io/commands/info>). The Redis command @INFO@ is split up into 'info', 'infoSection'. Since Redis 1.0.0
lastsave, -- |Get the UNIX time stamp of the last successful save to disk (<http://redis.io/commands/lastsave>). Since Redis 1.0.0
save,
slaveof,
Slowlog(..),
slowlogGet, -- |Manages the Redis slow queries log (<http://redis.io/commands/slowlog>). The Redis command @SLOWLOG@ is split up into 'slowlogGet', 'slowlogLen', 'slowlogReset'. Since Redis 2.2.12
slowlogLen, -- |Manages the Redis slow queries log (<http://redis.io/commands/slowlog>). The Redis command @SLOWLOG@ is split up into 'slowlogGet', 'slowlogLen', 'slowlogReset'. Since Redis 2.2.12
slowlogReset, -- |Manages the Redis slow queries log (<http://redis.io/commands/slowlog>). The Redis command @SLOWLOG@ is split up into 'slowlogGet', 'slowlogLen', 'slowlogReset'. Since Redis 2.2.12
time,

-- ** Sets
sadd,
scard,
sdiff,
sdiffstore,
sinter,
sinterstore,
sismember,
smembers,
smove,
spop,
spopN,
srandmember,
srandmemberN,
srem,
sscan,
sscanOpts,
sunion,
sunionstore,

-- ** Sorted Sets
ZaddOpts(..),
defaultZaddOpts,
zadd,
zaddOpts,
SizeCondition(..),
zcard,
zcount,
zincrby,
Aggregate(..),
zinterstore,
zinterstoreWeights,
zlexcount,
zrange,
zrangeWithscores,
RangeLex(..),
zrangebylex, zrangebylexLimit,
zrangebyscore, -- |Return a range of members in a sorted set, by score (<http://redis.io/commands/zrangebyscore>). The Redis command @ZRANGEBYSCORE@ is split up into 'zrangebyscore', 'zrangebyscoreWithscores', 'zrangebyscoreLimit', 'zrangebyscoreWithscoresLimit'. Since Redis 1.0.5
zrangebyscoreWithscores, -- |Return a range of members in a sorted set, by score (<http://redis.io/commands/zrangebyscore>). The Redis command @ZRANGEBYSCORE@ is split up into 'zrangebyscore', 'zrangebyscoreWithscores', 'zrangebyscoreLimit', 'zrangebyscoreWithscoresLimit'. Since Redis 1.0.5
zrangebyscoreLimit, -- |Return a range of members in a sorted set, by score (<http://redis.io/commands/zrangebyscore>). The Redis command @ZRANGEBYSCORE@ is split up into 'zrangebyscore', 'zrangebyscoreWithscores', 'zrangebyscoreLimit', 'zrangebyscoreWithscoresLimit'. Since Redis 1.0.5
zrangebyscoreWithscoresLimit, -- |Return a range of members in a sorted set, by score (<http://redis.io/commands/zrangebyscore>). The Redis command @ZRANGEBYSCORE@ is split up into 'zrangebyscore', 'zrangebyscoreWithscores', 'zrangebyscoreLimit', 'zrangebyscoreWithscoresLimit'. Since Redis 1.0.5
zrank,
zrankWithScore,
zrem,
zremrangebylex,
zremrangebyrank,
zremrangebyscore,
zrevrange, -- |Return a range of members in a sorted set, by index, with scores ordered from high to low (<http://redis.io/commands/zrevrange>). The Redis command @ZREVRANGE@ is split up into 'zrevrange', 'zrevrangeWithscores'. Since Redis 1.2.0
zrevrangeWithscores, -- |Return a range of members in a sorted set, by index, with scores ordered from high to low (<http://redis.io/commands/zrevrange>). The Redis command @ZREVRANGE@ is split up into 'zrevrange', 'zrevrangeWithscores'. Since Redis 1.2.0
zrevrangebyscore, -- |Return a range of members in a sorted set, by score, with scores ordered from high to low (<http://redis.io/commands/zrevrangebyscore>). The Redis command @ZREVRANGEBYSCORE@ is split up into 'zrevrangebyscore', 'zrevrangebyscoreWithscores', 'zrevrangebyscoreLimit', 'zrevrangebyscoreWithscoresLimit'. Since Redis 2.2.0
zrevrangebyscoreWithscores, -- |Return a range of members in a sorted set, by score, with scores ordered from high to low (<http://redis.io/commands/zrevrangebyscore>). The Redis command @ZREVRANGEBYSCORE@ is split up into 'zrevrangebyscore', 'zrevrangebyscoreWithscores', 'zrevrangebyscoreLimit', 'zrevrangebyscoreWithscoresLimit'. Since Redis 2.2.0
zrevrangebyscoreLimit, -- |Return a range of members in a sorted set, by score, with scores ordered from high to low (<http://redis.io/commands/zrevrangebyscore>). The Redis command @ZREVRANGEBYSCORE@ is split up into 'zrevrangebyscore', 'zrevrangebyscoreWithscores', 'zrevrangebyscoreLimit', 'zrevrangebyscoreWithscoresLimit'. Since Redis 2.2.0
zrevrangebyscoreWithscoresLimit, -- |Return a range of members in a sorted set, by score, with scores ordered from high to low (<http://redis.io/commands/zrevrangebyscore>). The Redis command @ZREVRANGEBYSCORE@ is split up into 'zrevrangebyscore', 'zrevrangebyscoreWithscores', 'zrevrangebyscoreLimit', 'zrevrangebyscoreWithscoresLimit'. Since Redis 2.2.0
zrevrank,
zrevrankWithScore,
zscan, -- |Incrementally iterate sorted sets elements and associated scores (<http://redis.io/commands/zscan>). The Redis command @ZSCAN@ is split up into 'zscan', 'zscanOpts'. Since Redis 2.8.0
zscanOpts, -- |Incrementally iterate sorted sets elements and associated scores (<http://redis.io/commands/zscan>). The Redis command @ZSCAN@ is split up into 'zscan', 'zscanOpts'. Since Redis 2.8.0
zscore,
zunionstore, -- |Add multiple sorted sets and store the resulting sorted set in a new key (<http://redis.io/commands/zunionstore>). The Redis command @ZUNIONSTORE@ is split up into 'zunionstore', 'zunionstoreWeights'. Since Redis 2.0.0
zunionstoreWeights, -- |Add multiple sorted sets and store the resulting sorted set in a new key (<http://redis.io/commands/zunionstore>). The Redis command @ZUNIONSTORE@ is split up into 'zunionstore', 'zunionstoreWeights'. Since Redis 2.0.0

-- ** Strings
append,
bitcount, -- |Count set bits in a string (<http://redis.io/commands/bitcount>). The Redis command @BITCOUNT@ is split up into 'bitcount', 'bitcountRange'. Since Redis 2.6.0
bitcountRange, -- |Count set bits in a string (<http://redis.io/commands/bitcount>). The Redis command @BITCOUNT@ is split up into 'bitcount', 'bitcountRange'. Since Redis 2.6.0
bitopAnd, -- |Perform bitwise operations between strings (<http://redis.io/commands/bitop>). The Redis command @BITOP@ is split up into 'bitopAnd', 'bitopOr', 'bitopXor', 'bitopNot'. Since Redis 2.6.0
bitopOr, -- |Perform bitwise operations between strings (<http://redis.io/commands/bitop>). The Redis command @BITOP@ is split up into 'bitopAnd', 'bitopOr', 'bitopXor', 'bitopNot'. Since Redis 2.6.0
bitopXor, -- |Perform bitwise operations between strings (<http://redis.io/commands/bitop>). The Redis command @BITOP@ is split up into 'bitopAnd', 'bitopOr', 'bitopXor', 'bitopNot'. Since Redis 2.6.0
bitopNot, -- |Perform bitwise operations between strings (<http://redis.io/commands/bitop>). The Redis command @BITOP@ is split up into 'bitopAnd', 'bitopOr', 'bitopXor', 'bitopNot'. Since Redis 2.6.0
bitpos,
bitposOpts,
BitposOpts(..),
BitposType(..),
decr,
decrby,
get,
getbit,
getrange,
getset,
incr,
incrby,
incrbyfloat,
mget,
mset,
msetnx,
psetex,
Condition(..),
SetOpts(..),
set, -- |Set the string value of a key (<http://redis.io/commands/set>). The Redis command @SET@ is split up into 'set', 'setOpts', 'setGet', 'setGetOpts'. Since Redis 1.0.0
setOpts, -- |Set the string value of a key (<http://redis.io/commands/set>). The Redis command @SET@ is split up into 'set', 'setOpts', 'setGet', 'setGetOpts'. Since Redis 1.0.0
setGet, -- |Set the string value of a key (<http://redis.io/commands/set>). The Redis command @SET@ is split up into 'set', 'setOpts', 'setGet', 'setGetOpts'. Since Redis 1.0.0
setGetOpts, -- |Set the string value of a key (<http://redis.io/commands/set>). The Redis command @SET@ is split up into 'set', 'setOpts', 'setGet', 'setGetOpts'. Since Redis 1.0.0
setbit,
setex,
setnx,
setrange,
strlen,


-- ** Streams
XReadOpts(..),
defaultXreadOpts,
XReadResponse(..),
StreamsRecord(..),
TrimOpts(..),
xadd,
xaddOpts,
XAddOpts(..),
defaultXAddOpts,
TrimStrategy(..),
TrimType(..),
trimOpts,
xread, -- |Read values from a stream (<https://redis.io/commands/xread>). The Redis command @XREAD@ is split up into 'xread', 'xreadOpts'. Since Redis 5.0.0
xreadOpts, -- |Read values from a stream (<https://redis.io/commands/xread>). The Redis command @XREAD@ is split up into 'xread', 'xreadOpts'. Since Redis 5.0.0
xreadGroup, -- |Read values from a stream as part of a consumer group (https://redis.io/commands/xreadgroup). The redis command @XREADGROUP@ is split up into 'xreadGroup' and 'xreadGroupOpts'. Since Redis 5.0.0
xreadGroupOpts, -- |Read values from a stream as part of a consumer group (https://redis.io/commands/xreadgroup). The redis command @XREADGROUP@ is split up into 'xreadGroup' and 'xreadGroupOpts'. Since Redis 5.0.0
xack, -- |Acknowledge receipt of a message as part of a consumer group. Since Redis 5.0.0

-- *** XGROUP CREATE
-- $xgroupCreate
xgroupCreate,
xgroupCreateOpts,
XGroupCreateOpts(..),
defaultXGroupCreateOpts,

-- *** XGROUP CREATECONSUMER
xgroupCreateConsumer,

-- *** XGROUP SETID
-- $xgroupSetId
xgroupSetId,
xgroupSetIdOpts,
XGroupSetIdOpts(..),
defaultXGroupSetIdOpts,

-- *** XGROUP DESTROY
xgroupDestroy,

-- *** XGROUP DELCONSUMER
xgroupDelConsumer,

xrange, -- |Read values from a stream within a range (https://redis.io/commands/xrange). Since Redis 5.0.0
xrevRange, -- |Read values from a stream within a range in reverse order (https://redis.io/commands/xrevrange). Since Redis 5.0.0
xlen, -- |Get the number of entries in a stream (https://redis.io/commands/xlen). Since Redis 5.0.0

-- *** XPENDING
-- $xpending
xpendingSummary,
XPendingSummaryResponse(..),
XPendingDetailOpts(..),
defaultXPendingDetailOpts,
XPendingDetailRecord(..),
xpendingDetail,

XClaimOpts(..),
defaultXClaimOpts,
xclaim, -- |Change ownership of some messages to the given consumer, returning the updated messages. The Redis @XCLAIM@ command is split into 'xclaim' and 'xclaimJustIds'. Since Redis 5.0.0
xclaimJustIds, -- |Change ownership of some messages to the given consumer, returning only the changed message IDs. The Redis @XCLAIM@ command is split into 'xclaim' and 'xclaimJustIds'. Since Redis 5.0.0

-- *** Autoclaim
-- $autoclaim
xautoclaim,
xautoclaimOpts,
XAutoclaimOpts(..),
XAutoclaimStreamsResult,
XAutoclaimResult(..),
xautoclaimJustIds,
xautoclaimJustIdsOpts,
XAutoclaimJustIdsResult,
XInfoConsumersResponse(..),
xinfoConsumers,
XInfoGroupsResponse(..),
xinfoGroups,
XInfoStreamResponse(..),
xinfoStream,
xdel,
xtrim,
inf,
ClusterNodesResponse(..),
ClusterNodesResponseEntry(..),
ClusterNodesResponseSlotSpec(..),
clusterNodes,
ClusterSlotsResponse(..),
ClusterSlotsResponseEntry(..),
ClusterSlotsNode(..),
clusterSlots,
clusterSetSlotNode,
clusterSetSlotStable,
clusterSetSlotImporting,
clusterSetSlotMigrating,
clusterGetKeysInSlot,
command
-- * Unimplemented Commands
-- |These commands are not implemented, as of now. Library
--  users can implement these or other commands from
--  experimental Redis versions by using the 'sendRequest'
--  function.
--
-- * COMMAND (<http://redis.io/commands/command>)
--
--
-- * COMMAND GETKEYS (<http://redis.io/commands/command-getkeys>)
--
--
-- * ROLE (<http://redis.io/commands/role>)
--
--
-- * CLIENT KILL (<http://redis.io/commands/client-kill>)
--
--
-- * ZREVRANGEBYLEX (<http://redis.io/commands/zrevrangebylex>)
--
--
-- * ZRANGEBYSCORE (<http://redis.io/commands/zrangebyscore>)
--
--
-- * ZREVRANGEBYSCORE (<http://redis.io/commands/zrevrangebyscore>)
--
--
-- * MONITOR (<http://redis.io/commands/monitor>)
--
--
-- * SYNC (<http://redis.io/commands/sync>)
--
--
-- * SHUTDOWN (<http://redis.io/commands/shutdown>)
--
--
-- * DEBUG SEGFAULT (<http://redis.io/commands/debug-segfault>)
--
) where

import Prelude hiding (min,max)
import Data.Int
import Data.ByteString (ByteString)
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE
import Database.Redis.ManualCommands
import Database.Redis.Types
import Database.Redis.Core(sendRequest, RedisCtx)

-- | /O(1)/
-- Get the time to live for a key (<http://redis.io/commands/ttl>).
-- Since Redis 1.0.0
--
-- This command returns:
--   * -2 if the key does not exist
--   * -1 if the key exists but has no associated value
--
ttl
    :: (RedisCtx m f)
    => ByteString -- ^ Key to check.
    -> m (f Integer)
ttl key = sendRequest ["TTL", encode key]

-- | /O(1)/
-- Sets the value of a key, only if the key does not exist (<http://redis.io/commands/setnx>).
--
-- Returns a result if a value was set.
--
-- Since Redis 1.0.0
setnx
    :: (RedisCtx m f)
    => ByteString -- ^ Key to set.
    -> ByteString -- ^ Value to set.
    -> m (f Bool)
setnx key value = sendRequest ["SETNX", encode key, encode value]

-- | /O(1)/
-- Get the time to live for a key in milliseconds (<http://redis.io/commands/pttl>).
-- Since Redis 2.6.0
--
-- This command returns @-2@ if the key does not exist.
-- This command returns @-1@ if the key exists but has no associated value
pttl
    :: (RedisCtx m f)
    => ByteString -- ^ Key.
    -> m (f Integer)
pttl key = sendRequest ["PTTL", encode key]

-- | /O(1)/
-- Get total number of Redis commands (<http://redis.io/commands/command-count>).
-- Since Redis 2.8.13
commandCount
    :: (RedisCtx m f)
    => m (f Integer)
commandCount  = sendRequest ["COMMAND","COUNT"]

-- | Set the current connection name (<http://redis.io/commands/client-setname>).
-- Since Redis 2.6.9
clientSetname
    :: (RedisCtx m f)
    => ByteString -- ^ Connection Name.
    -> m (f Status)
clientSetname connectionName = sendRequest ["CLIENT","SETNAME",encode connectionName]

-- | Determine the index of a member in a sorted set (<http://redis.io/commands/zrank>).
--
-- Since Redis 2.0.0
zrank
    :: (RedisCtx m f)
    => ByteString -- ^ Key.of the set.
    -> ByteString -- ^ Member
    -> m (f (Maybe Integer))
zrank key member = sendRequest ["ZRANK", encode key, encode member]

-- |
-- Since  Redis 7.2.0: fails on earlier versions
zrankWithScore
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the set.
    -> ByteString -- ^ Member.
    -> m (f (Maybe (Integer,Double)))
zrankWithScore key member = sendRequest ["ZRANK", encode key, encode member, "WITHSCORE"]

-- | /O(log(N)+M)/ with @N@ number of elements in the set, @M@ number of elements to be removed.
--
-- Remove all members in a sorted set within the given scores (<http://redis.io/commands/zremrangebyscore>).
--
-- Returns a number of elements that were removed.
--
-- Since Redis 1.2.0
zremrangebyscore
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Double -- ^ min
    -> Double -- ^ max
    -> m (f Integer)
zremrangebyscore key min max =
  sendRequest ["ZREMRANGEBYSCORE",encode key,encode min,encode max]

-- | /O(N)/ where @N@ is size of the hash.
-- Get all the fields in a hash (<http://redis.io/commands/hkeys>).
-- Since Redis 2.0.0
hkeys
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f [ByteString])
hkeys key = sendRequest ["HKEYS",encode key]

-- |Make the server a slave of another instance, or promote it as master (<http://redis.io/commands/slaveof>).
-- Deprecated in Redis, can be replaced by replicaif since redis 5.0
-- Since Redis 1.0.0
slaveof
    :: (RedisCtx m f)
    => ByteString -- ^ host
    -> ByteString -- ^ port
    -> m (f Status)
slaveof host port = sendRequest ["SLAVEOF",encode host,encode port]

-- | /O(1)/ for each element added.
-- Append a value to a list, only if the list exists (<http://redis.io/commands/rpushx>).
-- Since Redis 2.2.0
rpushx
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> NonEmpty ByteString -- ^ value
    -> m (f Integer)
rpushx key (value:|values) = sendRequest ("RPUSHX":encode key:value:values)

-- |Get debugging information about a key (<http://redis.io/commands/debug-object>). Since Redis 1.0.0
debugObject
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f ByteString)
debugObject key = sendRequest ["DEBUG","OBJECT",encode key]

-- |Asynchronously save the dataset to disk (<http://redis.io/commands/bgsave>).
--
-- Since Redis 1.0.0
bgsave
    :: (RedisCtx m f)
    => m (f Status)
bgsave  = sendRequest ["BGSAVE"]

-- |Asynchronously save the dataset to disk (<http://redis.io/commands/bgsave>).
--
-- Immediately returns OK when an AOF rewrite is in progress and schedule the background save
-- to run at the next opportunity.
--
-- A client may bee able to check if the operation succeeded using the 'lastsave' command
--
-- Since Redis 3.2.2
bgsaveSchedule
    :: (RedisCtx m f)
    => m (f Status)
bgsaveSchedule = sendRequest ["BGSAVE", "SCHEDULE"]


-- | /O(1)/ Get the number of fields in a hash (<http://redis.io/commands/hlen>).
--
-- Since Redis 2.0.0
hlen
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f Integer)
hlen key = sendRequest ["HLEN", key]

-- |Remove the last element in a list, prepend it to another list and return that
-- element f it existed (<http://redis.io/commands/rpoplpush>).
-- Since Redis 1.2.0
rpoplpush
    :: (RedisCtx m f)
    => ByteString -- ^ source
    -> ByteString -- ^ destination
    -> m (f (Maybe ByteString))
rpoplpush source destination = sendRequest ["RPOPLPUSH",encode source,encode destination]

-- | /O(N)/
-- Remove and get the last element in a list, or block until one is available (<http://redis.io/commands/brpop>).
--
-- Since Redis 2.0.0
brpop
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ key
    -> Integer -- ^ timeout
    -> m (f (Maybe (ByteString,ByteString)))
brpop (key:|rest) timeout = sendRequest (("BRPOP":key:rest)  ++ [encode timeout])

-- | /O(N)/
-- Remove and get the last element in a list, or block until one is available (<http://redis.io/commands/brpop>).
--
-- Since Redis 2.0.0
brpopFloat
    :: (RedisCtx m f)
    => [ByteString] -- ^ key
    -> Double -- ^ timeout
    -> m (f (Maybe (ByteString,ByteString)))
brpopFloat key timeout = sendRequest (["BRPOP"] ++ map encode key ++ [encode timeout])

-- |Asynchronously rewrite the append-only file (<http://redis.io/commands/bgrewriteaof>). Since Redis 1.0.0
bgrewriteaof
    :: (RedisCtx m f)
    => m (f Status)
bgrewriteaof  = sendRequest ["BGREWRITEAOF"]

-- | /O(log(N))/
--
-- Increment the score of a member in a sorted set (<http://redis.io/commands/zincrby>).
--
-- Returns new score of the element.
--
-- Since Redis 1.2.0
zincrby
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ increment
    -> ByteString -- ^ member
    -> m (f Double)
zincrby key increment member = sendRequest ["ZINCRBY",encode key,encode increment,encode member]

-- | Get all the fields and values in a hash (<http://redis.io/commands/hgetall>).
--
-- Since Redis 2.0.0.
hgetall
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f [(ByteString,ByteString)])
hgetall key = sendRequest ["HGETALL", encode key]


-- | Set multiple hash fields to multiple values (<http://redis.io/commands/hmset>).
--
-- Deprecated by Redis, consider using 'hset' with multiple field-value pairs.
--
-- Since Redis 2.0.0
hmset
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> NonEmpty (ByteString,ByteString) -- ^ fieldValue
    -> m (f Status)
hmset key ((field,value):|fieldValues) =
  sendRequest ("HMSET":key:field:value: concatMap (\(x,y) -> [x,y]) fieldValues)

-- |Intersect multiple sets (<http://redis.io/commands/sinter>).
-- Since Redis 1.0.0
sinter
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ Keys.
    -> m (f [ByteString])
sinter (key:|keys_) = sendRequest ("SINTER":key:keys_)

-- | /O(1)/
-- Adds all the elements arguments to the HyperLogLog data structure stored at the variable name specified as first argument (<http://redis.io/commands/pfadd>).
-- Since Redis 2.8.9
pfadd
    :: (RedisCtx m f)
    => ByteString -- ^ Key.
    -> NonEmpty ByteString -- ^ Value.
    -> m (f Integer)
pfadd key (value:|values) = sendRequest ("PFADD":key:value:values)

-- | /O(log(N)+M/ with @N@ being the number of elements in the sorted set and @M@ the number of elemnts removed by the operation.
--
-- Remove all members in a sorted set within the given indexes (<http://redis.io/commands/zremrangebyrank>).
--
-- Returns a number of elements that were removed.
--
-- Since Redis 2.0.0
zremrangebyrank
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ stop
    -> m (f Integer)
zremrangebyrank key start stop =
  sendRequest ["ZREMRANGEBYRANK",encode key,encode start,encode stop]

-- |Remove all keys from the current database (<http://redis.io/commands/flushdb>).
-- Since Redis 1.0.0
flushdb
    :: (RedisCtx m f)
    => m (f Status)
flushdb = sendRequest ["FLUSHDB"]

-- | /O(1)/ for each element added.
-- Add one or more members to a set (<http://redis.io/commands/sadd>).
-- Since Redis 1.0.0
sadd
    :: (RedisCtx m f)
    => ByteString -- ^ Key where set is stored.
    -> NonEmpty ByteString -- ^ Member to add to the set.
    -> m (f Integer)
sadd key member = sendRequest ("SADD":encode key:NE.toList (fmap encode member))

-- |Get an element from a list by its index (<http://redis.io/commands/lindex>).
-- Since Redis 1.0.0
lindex
    :: (RedisCtx m f)
    => ByteString -- ^ Key.
    -> Integer -- ^ Index
    -> m (f (Maybe ByteString))
lindex key index = sendRequest ["LINDEX",encode key,encode index]

-- | Prepend one or multiple values to a list (<http://redis.io/commands/lpush>).
-- Since Redis 1.0.0
lpush
    :: (RedisCtx m f)
    => ByteString -- ^ Key
    -> NonEmpty ByteString -- ^ Value
    -> m (f Integer)
lpush key (value:|values) = sendRequest ("LPUSH":key:value:values)

-- |Get the length of the value of a hash field (<http://redis.io/commands/hstrlen>).
-- Since Redis 3.2.0
hstrlen
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ field
    -> m (f Integer)
hstrlen key field = sendRequest ["HSTRLEN", key, field]

-- |
-- Move a member from one set to another (<http://redis.io/commands/smove>).
-- Since Redis 1.0.0
smove
    :: (RedisCtx m f)
    => ByteString -- ^ source
    -> ByteString -- ^ destination
    -> ByteString -- ^ member
    -> m (f Bool)
smove source destination member =
  sendRequest ["SMOVE", source, destination, member]

-- |Get the score associated with the given member in a sorted set (<http://redis.io/commands/zscore>).
-- Since Redis 1.2.0
zscore
    :: (RedisCtx m f)
    => ByteString -- ^ Key.
    -> ByteString -- ^ Member.
    -> m (f (Maybe Double))
zscore key member = sendRequest ["ZSCORE",encode key,encode member]

-- |Reset the stats returned by INFO (<http://redis.io/commands/config-resetstat>).
-- Since Redis 2.0.0
configResetstat
    :: (RedisCtx m f)
    => m (f Status)
configResetstat  = sendRequest ["CONFIG","RESETSTAT"]

-- |
-- Return the approximated cardinality of the set(s) observed by the HyperLogLog at key(s) (<http://redis.io/commands/pfcount>).
-- Since Redis 2.8.9
pfcount
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ key
    -> m (f Integer)
pfcount (key:|keys_) = sendRequest ("PFCOUNT": key: keys_)

-- | Delete one or more hash fields (<http://redis.io/commands/hdel>).
-- Since Redis 2.0.0
hdel
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> NonEmpty ByteString -- ^ field
    -> m (f Integer)
hdel key (field:|fields) = sendRequest ("HDEL":key:field:fields)

-- |Increment the float value of a key by the given amount (<http://redis.io/commands/incrbyfloat>). 
-- Since Redis 2.6.0
incrbyfloat
    :: (RedisCtx m f)
    => ByteString -- ^ Key.
    -> Double -- ^ Increment.
    -> m (f Double)
incrbyfloat key increment = sendRequest ["INCRBYFLOAT", key, encode increment]

-- |Sets or clears the bit at offset in the string value stored at key (<http://redis.io/commands/setbit>).
-- Since Redis 2.2.0
setbit
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ offset
    -> ByteString -- ^ value
    -> m (f Integer)
setbit key offset value = sendRequest ["SETBIT", key, encode offset, value]

-- | Remove all keys from all databases (<http://redis.io/commands/flushall>). Since Redis 1.0.0
flushall
    :: (RedisCtx m f)
    => m (f Status)
flushall  = sendRequest ["FLUSHALL"]

-- |Increment the integer value of a key by the given amount (<http://redis.io/commands/incrby>).
-- Since Redis 1.0.0
incrby
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ increment
    -> m (f Integer)
incrby key increment = sendRequest ["INCRBY", key, encode increment]

-- | Return the current server time (<http://redis.io/commands/time>).
-- Since Redis 2.6.0
time
    :: (RedisCtx m f)
    => m (f (Integer,Integer))
time  = sendRequest ["TIME"]

-- |Get all the members in a set (<http://redis.io/commands/smembers>). Since Redis 1.0.0
smembers
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f [ByteString])
smembers key = sendRequest ["SMEMBERS", key]

-- |Count the number of members in a sorted set between a given lexicographical range (<http://redis.io/commands/zlexcount>).
-- Since Redis 2.8.9
zlexcount
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ min
    -> ByteString -- ^ max
    -> m (f Integer)
zlexcount key min max = sendRequest ["ZLEXCOUNT", key, min, max]

-- |Add multiple sets (<http://redis.io/commands/sunion>).
-- Since Redis 1.0.0
sunion
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ key
    -> m (f [ByteString])
sunion (key:|keys_) = sendRequest ("SUNION":key:keys_)

-- |Intersect multiple sets and store the resulting set in a key (<http://redis.io/commands/sinterstore>).
-- Since Redis 1.0.0
sinterstore
    :: (RedisCtx m f)
    => ByteString -- ^ destination
    -> NonEmpty ByteString -- ^ key
    -> m (f Integer)
sinterstore destination (key:|keys_) =
  sendRequest ("SINTERSTORE":destination:key:keys_)

-- | Get all the values in a hash (<http://redis.io/commands/hvals>).
-- Since Redis 2.0.0
hvals
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f [ByteString])
hvals key = sendRequest ["HVALS", key]

-- |Set a configuration parameter to the given value (<http://redis.io/commands/config-set>).
-- Since Redis 2.0.0
configSet
    :: (RedisCtx m f)
    => ByteString -- ^ parameter
    -> ByteString -- ^ value
    -> m (f Status)
configSet parameter value = sendRequest ["CONFIG","SET", parameter, value]

-- |Remove all the scripts from the script cache (<http://redis.io/commands/script-flush>).
-- Since Redis 2.6.0
scriptFlush
    :: (RedisCtx m f)
    => m (f Status)
scriptFlush  = sendRequest ["SCRIPT","FLUSH"]

-- |Return the number of keys in the selected database (<http://redis.io/commands/dbsize>).
-- Since Redis 1.0.0
dbsize
    :: (RedisCtx m f)
    => m (f Integer)
dbsize  = sendRequest ["DBSIZE"]

-- |Wait for the synchronous replication of all the write commands sent in the context of the current connection (<http://redis.io/commands/wait>).
-- Since Redis 3.0.0
wait
    :: (RedisCtx m f)
    => Integer -- ^ numslaves
    -> Integer -- ^ timeout
    -> m (f Integer)
wait numslaves timeout = sendRequest ["WAIT", encode numslaves, encode timeout]

-- |Remove and get the first element in a list (<http://redis.io/commands/lpop>). Since Redis 1.0.0
lpop
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f (Maybe ByteString))
lpop key = sendRequest ["LPOP", encode key]

-- |
-- Remove and get the first element in a list (<http://redis.io/commands/lpop>).
-- The reply will consist of up to count elements, depending on the list's length.
-- Since Redis 1.0.0
lpopCount 
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer
    -> m (f [ByteString])
lpopCount key count = sendRequest ["LPOP", key, encode count]

-- |Stop processing commands from clients for some time (<http://redis.io/commands/client-pause>).
-- Since Redis 2.9.50
clientPause
    :: (RedisCtx m f)
    => Integer -- ^ timeout
    -> m (f Status)
clientPause timeout = sendRequest ["CLIENT","PAUSE", encode timeout]

-- |Set a key's time to live in seconds (<http://redis.io/commands/expire>). Since Redis 1.0.0
expire
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ seconds
    -> m (f Bool)
expire key seconds = sendRequest ["EXPIRE", key, encode seconds]

-- |Get the values of all the given keys (<http://redis.io/commands/mget>).
-- Since Redis 1.0.0
mget
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ key
    -> m (f [Maybe ByteString])
mget (key:|keys_) = sendRequest ("MGET":key:keys_)

-- |
-- Find first bit set or clear in a string (<http://redis.io/commands/bitpos>).
-- Since Redis 2.8.7
bitpos
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ bit
    -> Integer -- ^ start
    -> Integer -- ^ end
    -> m (f Integer)
bitpos key bit start end = sendRequest ["BITPOS", key, encode bit, encode start, encode end]

lastsave
    :: (RedisCtx m f)
    => m (f Integer)
lastsave  = sendRequest (["LASTSAVE"] )

-- | Set a key's time to live in milliseconds (<http://redis.io/commands/pexpire>).
-- Since Redis 2.6.0
pexpire
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ milliseconds
    -> m (f Bool)
pexpire key milliseconds = sendRequest ["PEXPIRE", key, encode milliseconds]

-- |Get the list of client connections (<http://redis.io/commands/client-list>). Since Redis 2.4.0
clientList
    :: (RedisCtx m f)
    => m (f [ByteString])
clientList  = sendRequest (["CLIENT","LIST"] )

-- |Rename a key, only if the new key does not exist (<http://redis.io/commands/renamenx>). Since Redis 1.0.0
renamenx
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ newkey
    -> m (f Bool)
renamenx key newkey = sendRequest ["RENAMENX", key, newkey]

-- |Merge N different HyperLogLogs into a single one (<http://redis.io/commands/pfmerge>). Since Redis 2.8.9
pfmerge
    :: (RedisCtx m f)
    => ByteString -- ^ destkey
    -> [ByteString] -- ^ sourcekey
    -> m (f ByteString)
pfmerge destkey sourcekey = sendRequest ("PFMERGE": destkey: sourcekey)

-- | Remove elements from a list (<http://redis.io/commands/lrem>). Since Redis 1.0.0
lrem
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ count
    -> ByteString -- ^ value
    -> m (f Integer)
lrem key count value = sendRequest ["LREM", key, encode count, value]

-- |Subtract multiple sets (<http://redis.io/commands/sdiff>). Since Redis 1.0.0
sdiff
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ key
    -> m (f [ByteString])
sdiff (key_:|keys_) = sendRequest ("SDIFF":key_:keys_)

-- |Get the value of a key (<http://redis.io/commands/get>). Since Redis 1.0.0
get
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f (Maybe ByteString))
get key = sendRequest (["GET"] ++ [encode key] )

-- |Get a substring of the string stored at a key (<http://redis.io/commands/getrange>).
-- Since Redis 2.4.0
getrange
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ end
    -> m (f ByteString)
getrange key start end = sendRequest ["GETRANGE", key, encode start, encode end]

-- |Subtract multiple sets and store the resulting set in a key (<http://redis.io/commands/sdiffstore>). Since Redis 1.0.0
sdiffstore
    :: (RedisCtx m f)
    => ByteString -- ^ destination
    -> NonEmpty ByteString -- ^ key
    -> m (f Integer)
sdiffstore destination (key_:|keys_) = sendRequest ("SDIFFSTORE": destination: key_: keys_)

-- |Count the members in a sorted set with scores within the given values (<http://redis.io/commands/zcount>). Since Redis 2.0.0
zcount
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Double -- ^ min
    -> Double -- ^ max
    -> m (f Integer)
zcount key min max = sendRequest ["ZCOUNT", key, encode min, encode max]

-- |Load the specified Lua script into the script cache (<http://redis.io/commands/script-load>). Since Redis 2.6.0
scriptLoad
    :: (RedisCtx m f)
    => ByteString -- ^ script
    -> m (f ByteString)
scriptLoad script = sendRequest ["SCRIPT","LOAD", encode script]

-- |Set the string value of a key and return its old value (<http://redis.io/commands/getset>). Since Redis 1.0.0
getset
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ value
    -> m (f (Maybe ByteString))
getset key value = sendRequest ["GETSET", key, value]

-- |Return a serialized version of the value stored at the specified key (<http://redis.io/commands/dump>). Since Redis 2.6.0
dump
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f ByteString)
dump key = sendRequest ["DUMP", key]

-- |Find all keys matching the given pattern (<http://redis.io/commands/keys>). Since Redis 1.0.0
keys
    :: (RedisCtx m f)
    => ByteString -- ^ pattern
    -> m (f [ByteString])
keys pattern = sendRequest ["KEYS", pattern]

-- |Get the value of a configuration parameter (<http://redis.io/commands/config-get>). Since Redis 2.0.0
configGet
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ parameter
    -> m (f [(ByteString,ByteString)])
configGet (parameter:|parameters) = sendRequest ("CONFIG":"GET":parameter:parameters)

-- |Append one or multiple values to a list (<http://redis.io/commands/rpush>). Since Redis 1.0.0
rpush
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> NonEmpty ByteString -- ^ value
    -> m (f Integer)
rpush key (value:|values) = sendRequest ("RPUSH": encode key:value:values)

-- |Return a random key from the keyspace (<http://redis.io/commands/randomkey>). Since Redis 1.0.0
randomkey
    :: (RedisCtx m f)
    => m (f (Maybe ByteString))
randomkey  = sendRequest ["RANDOMKEY"]

-- |Set the value of a hash field, only if the field does not exist (<http://redis.io/commands/hsetnx>). Since Redis 2.0.0
hsetnx
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ field
    -> ByteString -- ^ value
    -> m (f Bool)
hsetnx key field value = sendRequest ["HSETNX", key, field, value]

-- |Set multiple keys to multiple values (<http://redis.io/commands/mset>). Since Redis 1.0.1
mset
    :: (RedisCtx m f)
    => NonEmpty (ByteString,ByteString) -- ^ keyValue
    -> m (f Status)
mset ((key_,value):|keyValue) =
  sendRequest ("MSET":key_:value: concatMap (\(x,y) -> [encode x,encode y]) keyValue)

-- |Set the value and expiration of a key (<http://redis.io/commands/setex>).
-- Regarded as deprected since 2.6 as it can be replaced by SET with the EX argument when
-- migrating or writing new code.
-- Since Redis 2.0.0
setex
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ seconds
    -> ByteString -- ^ value
    -> m (f Status)
setex key seconds value = sendRequest ["SETEX", key, encode seconds, value]

-- |Set the value and expiration in milliseconds of a key (<http://redis.io/commands/psetex>).
-- Condidered deprecated since it can be replaced by SET with the PX argument when migrating or writing new code
-- Since Redis 2.6.0
psetex
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ milliseconds
    -> ByteString -- ^ value
    -> m (f Status)
psetex key milliseconds value = sendRequest ["PSETEX", key, encode milliseconds, value]

-- |Get the number of members in a set (<http://redis.io/commands/scard>). Since Redis 1.0.0
scard
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f Integer)
scard key = sendRequest ["SCARD", key]

-- |Check existence of scripts in the script cache (<http://redis.io/commands/script-exists>). Since Redis 2.6.0
scriptExists
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ script
    -> m (f [Bool])
scriptExists (script:|scripts) = sendRequest ("SCRIPT":"EXISTS":script:scripts)

-- |Add multiple sets and store the resulting set in a key (<http://redis.io/commands/sunionstore>). Since Redis 1.0.0
sunionstore
    :: (RedisCtx m f)
    => ByteString -- ^ destination
    -> NonEmpty ByteString -- ^ key
    -> m (f Integer)
sunionstore destination (key_:|keys_) =
  sendRequest ("SUNIONSTORE":destination:key_:keys_)

-- |Remove the expiration from a key (<http://redis.io/commands/persist>). Since Redis 2.2.0
persist
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f Bool)
persist key = sendRequest ["PERSIST", key]

-- |Get the length of the value stored in a key (<http://redis.io/commands/strlen>). Since Redis 2.2.0
strlen
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f Integer)
strlen key = sendRequest ["STRLEN", encode key]

-- |Prepend a value to a list, only if the list exists (<http://redis.io/commands/lpushx>). Since Redis 2.2.0
lpushx
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> NonEmpty ByteString -- ^ value
    -> m (f Integer)
lpushx key (value:|values) = sendRequest ("LPUSHX":key:value:values)

-- |Set the string value of a hash field (<http://redis.io/commands/hset>).
--
-- This command oveerides keys if they exist in the hash.
--
-- Since Redis 2.0.0
hset
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> NonEmpty (ByteString, ByteString) -- ^ Values.
    -> m (f Integer)
hset key ((field,value):|fieldValues) =
  sendRequest ("HSET":encode key:encode field:encode value:concatMap (\(f,v) ->[f,v]) fieldValues)

-- |Pop a value from a list, push it to another list and return it; or block until one is available (<http://redis.io/commands/brpoplpush>).
--
-- Since Redis 6.0 this command considered deprecated: it can be replaced by BLMOVE with the RIGHT and LEFT arguments when migrating or writing new code.
--
-- Since Redis 2.2.0
brpoplpush
    :: (RedisCtx m f)
    => ByteString -- ^ source
    -> ByteString -- ^ destination
    -> Integer -- ^ timeout
    -> m (f (Maybe ByteString))
brpoplpush source destination timeout =
  sendRequest ["BRPOPLPUSH", source, destination, encode timeout]

-- |Determine the index of a member in a sorted set, with scores ordered from high to low (<http://redis.io/commands/zrevrank>).
-- Since Redis 2.0.0
zrevrank
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ member
    -> m (f (Maybe Integer))
zrevrank key member = sendRequest ["ZREVRANK", key, member]

zrevrankWithScore
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ member
    -> m (f (Maybe (Integer, Double)))
zrevrankWithScore key member = sendRequest ["ZREVRANK", key, member]

-- |Kill the script currently in execution (<http://redis.io/commands/script-kill>). Since Redis 2.6.0
scriptKill
    :: (RedisCtx m f)
    => m (f Status)
scriptKill  = sendRequest ["SCRIPT","KILL"]

-- |Overwrite part of a string at key starting at the specified offset (<http://redis.io/commands/setrange>).
--
-- Returns the lenght of the string after it was modified.
--
-- Since Redis 2.2.0
setrange
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ offset
    -> ByteString -- ^ value
    -> m (f Integer)
setrange key offset value = sendRequest ["SETRANGE", key, encode offset, value]

-- | Delete a key (<http://redis.io/commands/del>).
-- Returns a number of keys that were removed.
-- Since Redis 1.0.0
del
    :: (RedisCtx m f)
    => NonEmpty ByteString -- ^ List of keys to delete.
    -> m (f Integer)
del (key:|rest) = sendRequest ("DEL":key:rest)

-- |Increment the float value of a hash field by the given amount (<http://redis.io/commands/hincrbyfloat>).
-- Since Redis 2.6.0
hincrbyfloat
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ field
    -> Double -- ^ increment
    -> m (f Double)
hincrbyfloat key field increment = sendRequest ["HINCRBYFLOAT", key, field, encode increment]

-- | Increment the integer value of a hash field by the given number (<http://redis.io/commands/hincrby>). Since Redis 2.0.0
hincrby
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ field
    -> Int64 -- ^ increment
    -> m (f Int64)
hincrby key field increment = sendRequest ["HINCRBY", encode key, encode field, encode increment]

-- | O(log(N)+M) with @N@ being thee number of elements in thee sorted set and @M@ the number
-- of elements removed by the operation.
--
-- Remove all members in a sorted set between the given lexicographical range (<http://redis.io/commands/zremrangebylex>).
--
-- Returns number of elements that were removed.
--
-- Since Redis 2.8.9
zremrangebylex
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ min
    -> ByteString -- ^ max
    -> m (f Integer)
zremrangebylex key min max = sendRequest (["ZREMRANGEBYLEX"] ++ [encode key] ++ [encode min] ++ [encode max] )

-- |Remove and get the last element in a list (<http://redis.io/commands/rpop>).
-- Since Redis 1.0.0
rpop
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f (Maybe ByteString))
rpop key = sendRequest ["RPOP", encode key]

-- |Remove and get the last element in a list (<http://redis.io/commands/rpop>).
--
-- Result will have no more than @N@ arguments.
--
-- Since Redis 1.0.0
rpopCount
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer
    -> m (f (Maybe ByteString))
rpopCount key count = sendRequest (["RPOP",key, encode count] )

-- |Rename a key (<http://redis.io/commands/rename>). Since Redis 1.0.0
--
-- Does not return a error even if newkey existed.
rename
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ newkey
    -> m (f Status)
rename key newkey = sendRequest ["RENAME",  encode key, encode newkey]

-- | /O(M*log(N))/ with @N@ number of elements in the sorted set, @M@ number of elements to be
-- removed.
--
-- Removes one or more members from a sorted set (<http://redis.io/commands/zrem>).
--
-- Since Redis 1.2.0
zrem
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> NonEmpty ByteString -- ^ member
    -> m (f Integer)
zrem key (member:|members) = sendRequest ("ZREM":encode key:encode member:members)

-- |Determine if a hash field exists (<http://redis.io/commands/hexists>).
-- Since Redis 2.0.0
hexists
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ field
    -> m (f Bool)
hexists key field = sendRequest ["HEXISTS", key, field]

-- |Get the current connection ID (<http://redis.io/commands/client-id>). Since Redis 5.0.0
clientId
    :: (RedisCtx m f)
    => m (f Integer)
clientId  = sendRequest ["CLIENT","ID"]

-- |Get the current connection name (<http://redis.io/commands/client-getname>). Since Redis 2.6.9
clientGetname
    :: (RedisCtx m f)
    => m (f (Maybe ByteString))
clientGetname  = sendRequest ["CLIENT","GETNAME"]

-- |Rewrite the configuration file with the in memory configuration (<http://redis.io/commands/config-rewrite>). Since Redis 2.8.0
configRewrite
    :: (RedisCtx m f)
    => m (f Status)
configRewrite  = sendRequest ["CONFIG","REWRITE"]

-- |Decrement the integer value of a key by one (<http://redis.io/commands/decr>).
-- Since Redis 1.0.0
decr
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f Integer)
decr key = sendRequest ["DECR", key]

-- |Get the values of all the given hash fields (<http://redis.io/commands/hmget>).
-- Since Redis 2.0.0
hmget
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> NonEmpty ByteString -- ^ field
    -> m (f [Maybe ByteString])
hmget key (field:|fields) = sendRequest ("HMGET":key:field:fields)

-- |Get a range of elements from a list (<http://redis.io/commands/lrange>). Since Redis 1.0.0
lrange
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ stop
    -> m (f [ByteString])
lrange key start stop = sendRequest ["LRANGE", key, encode start, encode stop]

-- |Decrement the integer value of a key by the given number (<http://redis.io/commands/decrby>).
-- Since Redis 1.0.0
decrby
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ decrement
    -> m (f Integer)
decrby key decrement = sendRequest ["DECRBY",key, encode decrement]

-- |Get the length of a list (<http://redis.io/commands/llen>). Since Redis 1.0.0
llen
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f Integer)
llen key = sendRequest ["LLEN", encode key]

-- | /O(1)/ Append a value to a key (<http://redis.io/commands/append>). Since Redis 2.0.0
append
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ value
    -> m (f Integer)
append key value = sendRequest ["APPEND", key, value]

-- |Increment the integer value of a key by one (<http://redis.io/commands/incr>). Since Redis 1.0.0
incr
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f Integer)
incr key = sendRequest ["INCR", key]

-- |Get the value of a hash field (<http://redis.io/commands/hget>). Since Redis 2.0.0
hget
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> ByteString -- ^ field
    -> m (f (Maybe ByteString))
hget key field = sendRequest ["HGET",key,field]

-- |Set the expiration for a key as a UNIX timestamp specified in milliseconds (<http://redis.io/commands/pexpireat>). Since Redis 2.6.0
pexpireat
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ millisecondsTimestamp
    -> m (f Bool)
pexpireat key millisecondsTimestamp = sendRequest ["PEXPIREAT", key, encode millisecondsTimestamp]

-- | Trim a list to the specified range (<http://redis.io/commands/ltrim>).
-- Since Redis 1.0.0
ltrim
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ start
    -> Integer -- ^ stop
    -> m (f Status)
ltrim key start stop = sendRequest ["LTRIM", key, encode start, encode stop]

-- | /O(1)/
-- Get the number of members in a sorted set (<http://redis.io/commands/zcard>).
-- Since Redis 1.2.0
zcard
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> m (f Integer)
zcard key = sendRequest ["ZCARD", key]

-- | Set the value of an element in a list by its index (<http://redis.io/commands/lset>).
-- Since Redis 1.0.0
lset
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ index
    -> ByteString -- ^ value
    -> m (f Status)
lset key index value = sendRequest ["LSET", key, encode index, value]

-- | Set the expiration for a key as a UNIX timestamp (<http://redis.io/commands/expireat>).
-- Since Redis 1.2.0
expireat
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ timestamp
    -> m (f Bool)
expireat key timestamp = sendRequest ["EXPIREAT", key, encode timestamp]

-- | Synchronously save the dataset to disk (<http://redis.io/commands/save>).
-- Since Redis 1.0.0
save
    :: (RedisCtx m f)
    => m (f Status)
save  = sendRequest ["SAVE"]

-- |
-- Move a key to another database (<http://redis.io/commands/move>).
-- Since Redis 1.0.0
move
    :: (RedisCtx m f)
    => ByteString -- ^ key
    -> Integer -- ^ db
    -> m (f Bool)
move key db = sendRequest ["MOVE", key, encode db]

-- |
-- Returns the bit value at offset in the string value stored at key (<http://redis.io/commands/getbit>). Since Redis 2.2.0
getbit
    :: (RedisCtx m f)
    => ByteString -- ^ Key.
    -> Integer -- ^ Offset.
    -> m (f Integer)
getbit key offset = sendRequest ["GETBIT", key, encode offset]

-- |Set multiple keys to multiple values, only if none of the keys exist (<http://redis.io/commands/msetnx>).
-- Since Redis 1.0.1
msetnx
    :: (RedisCtx m f)
    => NonEmpty (ByteString,ByteString) -- ^ keyValue
    -> m (f Bool)
msetnx ((key,value):|keysValues) =
  sendRequest ("MSETNX":key:value:concatMap (\(x,y) -> [encode x,encode y]) keysValues)

-- |Get array of specific Redis command details (<http://redis.io/commands/command-info>).
-- Since Redis 2.8.13
commandInfo
    :: (RedisCtx m f)
    => [ByteString] -- ^ commandName
    -> m (f [ByteString])
commandInfo commandName = sendRequest ("COMMAND":"INFO":map encode commandName )

-- | Close the connection (<http://redis.io/commands/quit>). Since Redis 1.0.0
quit
    :: (RedisCtx m f)
    => m (f Status)
quit  = sendRequest ["QUIT"]

-- |Remove and get the first element in a list, or block until one is available (<http://redis.io/commands/blpop>). Since Redis 2.0.0
blpop
    :: (RedisCtx m f)
    => [ByteString] -- ^ key
    -> Integer -- ^ timeout
    -> m (f (Maybe (ByteString,ByteString)))
blpop keys_ timeout = sendRequest ("BLPOP":keys_ ++ [encode timeout] )

-- |Remove and get the first element in a list, or block until one is available (<http://redis.io/commands/blpop>). Since Redis 6.0.0
blpopFloat
    :: (RedisCtx m f)
    => [ByteString] -- ^ key
    -> Integer -- ^ timeout
    -> m (f (Maybe (ByteString,ByteString)))
blpopFloat keys_ timeout = sendRequest ("BLPOP":keys_ ++ [encode timeout] )

-- | /O(N)/ where @N@ is the number of members to be removed.
-- Remove one or more members from a set (<http://redis.io/commands/srem>).
--
-- Returns the number of members that were removed from the seet, not including non
-- existing elements.
--
-- Since Redis 1.0.0
srem
    :: (RedisCtx m f)
    => ByteString -- ^ Key of the set.
    -> NonEmpty ByteString -- ^ List of members to be removed.
    -> m (f Integer)
srem key (member:|members) = sendRequest ("SREM":key:member:members)

-- |Echo the given string (<http://redis.io/commands/echo>). Since Redis 1.0.0
echo
    :: (RedisCtx m f)
    => ByteString -- ^ message
    -> m (f ByteString)
echo message = sendRequest ["ECHO", encode message]

-- |Determine if a given value is a member of a set (<http://redis.io/commands/sismember>).
--  Since Redis 1.0.0
sismember
    :: (RedisCtx m f)
    => ByteString -- ^ Key.
    -> ByteString -- ^ member
    -> m (f Bool)
sismember key member = sendRequest ["SISMEMBER",key, member]

-- $autoclaim
--
-- Family of the commands related to the autoclaim command in redis, they provide an
-- ability to claim messages that are not processed for a long time.
--
-- Transfers ownership of pending stream entries that match
-- the specified criteria. The message should be pending for more than \<min-idle-time\>
-- milliseconds and ID should be greater than \<start\>.
--
-- Redis @xautoclaim@ command is split info `xautoclaim`, `xautoclaimOpts`, `xautoclaimJustIds`
-- `xautoclaimJustIdsOpt` functions.
--
-- All commands are available since Redis 7.0

-- $xpending
-- The Redis @XPENDING@ command is split into 'xpendingSummary' and 'xpendingDetail'.

-- $xgroupCreate
-- Create a consumer group. The redis command @XGROUP CREATE@ is split up into 'xgroupCreate', 'xgroupCreateOpts'.

-- $xgroupSetId
-- Sets last delivered ID for a consumer group. The redis command @XGROUP SETID@ is split up into 'xgroupSetId' and 'xgroupSetIdOpts' methods.


-- $auth
-- Authenticate to the server (<http://redis.io/commands/auth>). Since Redis 1.0.0

