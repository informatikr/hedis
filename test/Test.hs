{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
module Main (main) where

import Control.Concurrent
import Control.Monad
import Control.Monad.Trans
import Data.ByteString.Char8 (ByteString, pack)
import System.Time
import qualified Test.HUnit as Test
import Test.HUnit (runTestTT, (~:))

import Database.Redis


type BS = ByteString

------------------------------------------------------------------------------
-- Main and helpers
--
main :: IO ()
main = do
    c <- connect "127.0.0.1" (PortNumber 6379)
    runTestTT $ Test.TestList $ map ($c) tests
    disconnect c

type Test = RedisConn -> Test.Test

testCase :: String -> Redis () -> Test
testCase name r conn = name ~:
    Test.TestCase $ runRedis conn $ flushall >>=? Ok >> r
    
(>>=?) :: (Eq a, Show a) => Redis (Either Reply a) -> a -> Redis ()
redis >>=? expected = do
    a <- redis
    liftIO $ case a of
        Left reply   -> Test.assertFailure $ "Redis error: " ++ show reply
        Right actual -> expected Test.@=? actual

(@=?) :: (Eq a, Show a) => a -> a -> Redis ()
x @=? y = liftIO $ (Test.@=?) x y

------------------------------------------------------------------------------
-- Tests
--
tests :: [Test]
tests = concat
    [ testsKeys, testsStrings, testsHashes, testsLists, testsConnection
    , testsServer, [testQuit]
    ]


------------------------------------------------------------------------------
-- Keys
--
testsKeys :: [Test]
testsKeys =
    [ testDel, testExists, testExpire, testExpireAt, testKeys, testMove
    , testPersist, testRandomkey, testRename, testRenamenx, testSort
    , testTtl, testGetType, testObject
    ]

testDel :: Test
testDel = testCase "del" $ do
    set "key" "value" >>=? Ok
    get "key"         >>=? Just "value"
    del ["key"]       >>=? 1
    get "key"         >>=? Nothing

testExists :: Test
testExists = testCase "exists" $ do
    exists "key"      >>=? False
    set "key" "value" >>=? Ok
    exists "key"      >>=? True

testExpire :: Test
testExpire = testCase "expire" $ do
    set "key" "value"  >>=? Ok
    expire "key" 1     >>=? True
    expire "notAKey" 1 >>=? False
    ttl "key"          >>=? 1
    
testExpireAt :: Test
testExpireAt = testCase "expireat" $ do
    set "key" "value"         >>=? Ok
    TOD seconds _ <- liftIO getClockTime
    let expiry = seconds + 1
    expireat "key" expiry     >>=? True
    expireat "notAKey" expiry >>=? False
    ttl "key"                 >>=? 1

testKeys :: Test
testKeys = testCase "keys" $ do
    keys "key*"      >>=? []
    set "key1" "value" >>=? Ok
    set "key2" "value" >>=? Ok
    Right ks <- keys "key*"
    2    @=? length ks
    True @=? elem "key1" ks
    True @=? elem "key2" ks

testMove :: Test
testMove = testCase "move" $ do
    set "key" "value" >>=? Ok
    move "key" 13     >>=? True
    get "key"         >>=? Nothing
    select 13         >>=? Ok
    get "key"         >>=? Just "value"

testPersist :: Test
testPersist = testCase "persist" $ do
    set "key" "value" >>=? Ok
    expire "key" 1    >>=? True
    ttl "key"         >>=? 1
    persist "key"     >>=? True
    ttl "key"         >>=? (-1)

testRandomkey :: Test
testRandomkey = testCase "randomkey" $ do
    set "k1" "value" >>=? Ok
    set "k2" "value" >>=? Ok
    Right k <- randomkey
    True @=? (k `elem` ["k1", "k2"])

testRename :: Test
testRename = testCase "rename" $ do
    set "k1" "value" >>=? Ok
    rename "k1" "k2" >>=? Ok
    get "k1"         >>=? Nothing
    get "k2"         >>=? Just ("value" )

testRenamenx :: Test
testRenamenx = testCase "renamenx" $ do
    set "k1" "value"   >>=? Ok
    set "k2" "value"   >>=? Ok
    renamenx "k1" "k2" >>=? False
    renamenx "k1" "k3" >>=? True

testSort :: Test
testSort = testCase "sort" $ return () -- TODO needs sort-implementation

testTtl :: Test
testTtl = testCase "ttl" $ do
    set "key" "value" >>=? Ok
    ttl "notAKey"     >>=? (-1)
    ttl "key"         >>=? (-1)
    expire "key" 42   >>=? True
    ttl "key"         >>=? 42

testGetType :: Test
testGetType = testCase "getType" $ do
    getType "key"     >>=? None
    forM_ ts $ \(setKey, typ) -> do
        setKey
        getType "key" >>=? typ
        del ["key"]   >>=? 1
  where
    [k,v,f,mem] = ["key","value","field","member"] 
    ts = [ (set "key" "value"                         >>=? Ok,   String)
         , (hset "key" "field" "value"                >>=? True, Hash)
         , (lpush "key" ["value"]                     >>=? 1,    List)
         , (sadd "key" ["member"]                     >>=? 1,    Set)
         , (zadd "key" [(42,"member"),(12.3,"value")] >>=? 2,    ZSet)
         ]

testObject :: Test
testObject = testCase "object" $ do
    set "key" "value"    >>=? Ok
    objectRefcount "key" >>=? 1
    Right _ <- objectEncoding "key"
    objectIdletime "key" >>=? 0

------------------------------------------------------------------------------
-- Strings
--
testsStrings :: [Test]
testsStrings =
    [ testAppend, testDecr, testDecrby, testGetbit, testGetrange, testGetset
    , testIncr, testIncrby, testMget, testMset, testMsetnx, testSetbit
    , testSetex, testSetnx, testSetrange, testStrlen, testSetAndGet
    ]

testAppend :: Test
testAppend = testCase "append" $ do
    set "key" "hello"    >>=? Ok
    append "key" "world" >>=? 10
    get "key"            >>=? Just "helloworld"

testDecr :: Test
testDecr = testCase "decr" $ do
    set "key" "42" >>=? Ok
    decr "key"     >>=? 41

testDecrby :: Test
testDecrby = testCase "decrby" $ do
    set "key" "42"  >>=? Ok
    decrby "key" 2  >>=? 40

testGetbit :: Test
testGetbit = testCase "getbit" $ getbit "key" 42 >>=? 0

testGetrange :: Test
testGetrange = testCase "getrange" $ do
    set "key" "value"     >>=? Ok
    getrange "key" 1 (-2) >>=? "alu"

testGetset :: Test
testGetset = testCase "getset" $ do
    getset "key" "v1" >>=? Nothing
    getset "key" "v2" >>=? Just "v1"

testIncr :: Test
testIncr = testCase "incr" $ do
    set "key" "42" >>=? Ok
    incr "key"     >>=? 43

testIncrby :: Test
testIncrby = testCase "incrby" $ do
    set "key" "40" >>=? Ok
    incrby "key" 2 >>=? 42

testMget :: Test
testMget = testCase "mget" $ do
    set "k1" "v1"               >>=? Ok
    set "k2" "v2"               >>=? Ok
    mget ["k1","k2","notAKey" ] >>=? [Just "v1", Just "v2", Nothing]

testMset :: Test
testMset = testCase "mset" $ do
    mset [("k1","v1"), ("k2","v2")] >>=? Ok
    get "k1"                        >>=? Just "v1"
    get "k2"                        >>=? Just "v2"

testMsetnx :: Test
testMsetnx = testCase "msetnx" $ do
    msetnx [("k1","v1"), ("k2","v2")] >>=? True
    msetnx [("k1","v1"), ("k2","v2")] >>=? False

testSetbit :: Test
testSetbit = testCase "setbit" $ do
    setbit "key" 42 "1" >>=? 0
    setbit "key" 42 "0" >>=? 1
    
testSetex :: Test
testSetex = testCase "setex" $ do
    setex "key" 1 "value" >>=? Ok
    ttl "key"             >>=? 1

testSetnx :: Test
testSetnx = testCase "setnx" $ do
    setnx "key" "v1" >>=? True
    setnx "key" "v2" >>=? False

testSetrange :: Test
testSetrange = testCase "setrange" $ do
    set "key" "value"      >>=? Ok
    setrange "key" 1 "ers" >>=? 5
    get "key"              >>=? Just "verse"

testStrlen :: Test
testStrlen = testCase "strlen" $ do
    set "key" "value" >>=? Ok
    strlen "key"      >>=? 5

testSetAndGet :: Test
testSetAndGet = testCase "set/get" $ do
    let [k,v] = ["key","value"] 
    get "key"         >>=? Nothing
    set "key" "value" >>=? Ok
    get "key"         >>=? Just "value"


------------------------------------------------------------------------------
-- Hashes
--
testsHashes :: [Test]
testsHashes =
    [ testHdel, testHexists,testHget, testHgetall, testHincrby, testHkeys
    , testHlen, testHmget, testHmset, testHset, testHsetnx, testHvals
    ]

testHdel :: Test
testHdel = testCase "hdel" $ do
    hdel "key" ["field"]       >>=? False
    hset "key" "field" "value" >>=? True
    hdel "key" ["field"]       >>=? True

testHexists :: Test
testHexists = testCase "hexists" $ do
    hexists "key" "field"      >>=? False
    hset "key" "field" "value" >>=? True
    hexists "key" "field"      >>=? True

testHget :: Test
testHget = testCase "hget" $ do
    hget "key" "field"         >>=? Nothing
    hset "key" "field" "value" >>=? True
    hget "key" "field"         >>=? Just "value"

testHgetall :: Test
testHgetall = testCase "hgetall" $ do
    hgetall "key"                         >>=? []
    hmset "key" [("f1","v1"),("f2","v2")] >>=? Ok
    hgetall "key"                         >>=? [("f1","v1"), ("f2","v2")]
    
testHincrby :: Test
testHincrby = testCase "hincrby" $ do
    hset "key" "field" "40" >>=? True
    hincrby "key" "field" 2 >>=? 42

testHkeys :: Test
testHkeys = testCase "hkeys" $ do
    hset "key" "field" "value" >>=? True
    hkeys "key"                >>=? ["field"]

testHlen :: Test
testHlen = testCase "hlen" $ do
    hlen "key"                 >>=? 0
    hset "key" "field" "value" >>=? True
    hlen "key"                 >>=? 1

testHmget :: Test
testHmget = testCase "hmget" $ do
    hmset "key" [("f1","v1"), ("f2","v2")] >>=? Ok
    hmget "key" ["f1", "f2", "nofield" ]   >>=? [Just "v1", Just "v2", Nothing]

testHmset :: Test
testHmset = testCase "hmset" $ do
    hmset "key" [("f1","v1"), ("f2","v2")] >>=? Ok

testHset :: Test
testHset = testCase "hset" $ do
    hset "key" "field" "value" >>=? True
    hset "key" "field" "value" >>=? False

testHsetnx :: Test
testHsetnx = testCase "hsetnx" $ do
    hsetnx "key" "field" "value" >>=? True
    hsetnx "key" "field" "value" >>=? False

testHvals :: Test
testHvals = testCase "hvals" $ do
    hset "key" "field" "value" >>=? True
    hvals "key"                >>=? ["value"]


------------------------------------------------------------------------------
-- Lists
--
testsLists :: [Test]
testsLists =
    [testBlpop, testBrpoplpush, testLpop, testLinsert, testLpushx, testLset]

testBlpop :: Test
testBlpop = testCase "blpop/brpop" $ do
    lpush "key" ["v3","v2","v1"] >>=? 3
    blpop ["notAKey","key"] 1    >>=? ("key","v1")
    brpop ["notAKey","key"] 1    >>=? ("key","v3")

testBrpoplpush :: Test
testBrpoplpush = testCase "brpoplpush/rpoplpush" $ do
    rpush "k1" ["v1","v2"] >>=? 2
    brpoplpush "k1" "k2" 1 >>=? "v2"
    rpoplpush "k1" "k2"    >>=? "v1"
    llen "k2"              >>=? 2
    llen "k1"              >>=? 0

testLpop :: Test
testLpop = testCase "lpop/rpop" $ do
    lpush "key" ["v3","v2","v1"] >>=? 3
    lpop "key"                   >>=? "v1"
    llen "key"                   >>=? 2
    rpop "key"                   >>=? "v3"

testLinsert :: Test
testLinsert = testCase "linsert" $ do
    rpush "key" ["v2"]                 >>=? 1
    linsertBefore "key" "v2" "v1"      >>=? 2
    linsertBefore "key" "notAVal" "v3" >>=? (-1)
    linsertAfter "key" "v2" "v3"       >>=? 3    
    linsertAfter "key" "notAVal" "v3"  >>=? (-1)
    lindex "key" 0                     >>=? "v1"
    lindex "key" 2                     >>=? "v3"

testLpushx :: Test
testLpushx = testCase "lpushx/rpushx" $ do
    lpushx "notAKey" "v1" >>=? 0
    lpush "key" ["v2"]    >>=? 1
    lpushx "key" "v1"     >>=? 2
    rpushx "key" "v3"     >>=? 3

testLset :: Test
testLset = testCase "lset/lrem/ltrim" $ do
    lpush "key" ["v3","v2","v2","v1","v1"] >>=? 5
    lset "key" 1 "v2"                      >>=? Ok
    lrem "key" 2 "v2"                      >>=? 2
    llen "key"                             >>=? 3
    ltrim "key" 0 1                        >>=? Ok
    lrange "key" 0 1                       >>=? ["v1", "v2"]

------------------------------------------------------------------------------
-- Sets
--

------------------------------------------------------------------------------
-- Sorted Sets
--


------------------------------------------------------------------------------
-- Pub/Sub
--

------------------------------------------------------------------------------
-- Transaction
--

------------------------------------------------------------------------------
-- Connection
--
testsConnection :: [Test]
testsConnection = [ testEcho, testPing, testSelect ]

testEcho :: Test
testEcho = testCase "echo" $
    echo ("value" ) >>=? "value"

testPing :: Test
testPing = testCase "ping" $ ping >>=? Pong

testQuit :: Test
testQuit = testCase "quit" $ quit >>=? Ok

testSelect :: Test
testSelect = testCase "select" $ do
    select 13 >>=? Ok
    select 0 >>=? Ok


------------------------------------------------------------------------------
-- Server
--
testsServer =
    [testBgrewriteaof, testFlushall, testInfo, testConfig, testSlowlog]

testBgrewriteaof :: Test
testBgrewriteaof = testCase "bgrewriteaof/bgsave/save" $ do
    save >>=? Ok
    -- TODO return types not as documented
    -- bgsave       >>=? BgSaveStarted
    -- bgrewriteaof >>=? BgAOFRewriteStarted

testConfig :: Test
testConfig = testCase "config/auth" $ do
    configSet "requirepass" "pass" >>=? Ok
    auth "pass"                    >>=? Ok
    configSet "requirepass" ""     >>=? Ok
    
testFlushall :: Test
testFlushall = testCase "flushall/flushdb" $ do
    flushall >>=? Ok
    flushdb  >>=? Ok

testInfo :: Test
testInfo = testCase "info/lastsave/dbsize" $ do
    Right _ <- info
    Right _ <- lastsave
    dbsize          >>=? 0
    configResetstat >>=? Ok

testSlowlog :: Test
testSlowlog = testCase "slowlog" $ do
    reply <- slowlogGet 5
    Right (MultiBulk (Just [])) @=? reply
    slowlogLen   >>=? 0
    slowlogReset >>=? Ok
