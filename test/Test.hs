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
    Test.TestCase $ runRedis conn $ flushall >>=? Just Ok >> r
    

(>>=?) :: (Eq a, Show a) => Redis a -> a -> Redis ()
redis >>=? expected = redis >>= liftIO . (Test.@=?) expected

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
    let [k,v] = ["key","value"] :: [BS]
    set k v >>=? Just Ok
    get k   >>=? Just ("value" :: BS)
    del [k] >>=? Just (1 :: Int)
    get k   >>=? (Nothing :: Maybe ByteString)

testExists :: Test
testExists = testCase "exists" $ do
    let [k,v] = ["key","value"] :: [BS]
    exists k >>=? Just False
    set k v  >>=? Just Ok
    exists k >>=? Just True

testExpire :: Test
testExpire = testCase "expire" $ do
    let [k,v,notAKey] = ["key","value","notAKey"] :: [BS]
    set k v          >>=? Just Ok
    expire k (1 :: Int)       >>=? Just True
    expire notAKey (1 :: Int) >>=? Just False
    ttl k            >>=? Just (1 :: Int)
    
testExpireAt :: Test
testExpireAt = testCase "expireat" $ do
    let [k,v,notAKey] = ["key","value","notAKey"] :: [BS]
    set k v                 >>=? Just Ok
    TOD seconds _ <- liftIO getClockTime
    let expiry = seconds + 1
    expireat k expiry       >>=? Just True
    expireat notAKey expiry >>=? Just False
    ttl k                   >>=? Just (1 :: Int)

testKeys :: Test
testKeys = testCase "keys" $ do
    let [k1,k2,v,pat] = ["key1","key2","val","key*"] :: [BS]
    keys pat >>=? Just ([] :: [Maybe ByteString])
    set k1 v >>=? Just Ok
    set k2 v >>=? Just Ok
    Just ks <- keys pat
    (2 :: Int)    @=? length (ks :: [Maybe ByteString])
    True @=? elem (Just "key1") ks
    True @=? elem (Just "key2") ks

testMove :: Test
testMove = testCase "move" $ do
    let [k,v] = ["key","value"] :: [BS]
    set k v   >>=? Just Ok
    move k (13 :: Int) >>=? Just True
    get k     >>=? (Nothing :: Maybe ByteString)
    select (13 :: Int) >>=? Just Ok
    get k     >>=? Just ("value" :: BS)

testPersist :: Test
testPersist = testCase "persist" $ do
    let [k,v] = ["key","val"] :: [BS]
    set k v    >>=? Just Ok
    expire k (1 :: Int) >>=? Just True
    ttl k      >>=? Just (1 :: Int)
    persist k  >>=? Just True
    ttl k      >>=? Just (-1 :: Int)

testRandomkey :: Test
testRandomkey = testCase "randomkey" $ do
    let [k1,k2,v] = ["k1","k2","value"] :: [BS]
    set k1 v >>=? Just Ok
    set k2 v >>=? Just Ok
    Just k <- randomkey
    True @=? ((k :: BS) `elem` ["k1", "k2"])

testRename :: Test
testRename = testCase "rename" $ do
    let [k1,k2,v] = ["k1","k2","value"] :: [BS]
    set k1 v     >>=? Just Ok
    rename k1 k2 >>=? Just Ok
    get k1       >>=? (Nothing :: Maybe ByteString)
    get k2       >>=? Just ("value" :: BS)

testRenamenx :: Test
testRenamenx = testCase "renamenx" $ do
    let [k1,k2,k3,v] = ["k1","k2","k3","value"] :: [BS]
    set k1 v       >>=? Just Ok
    set k2 v       >>=? Just Ok
    renamenx k1 k2 >>=? Just False
    renamenx k1 k3 >>=? Just True

testSort :: Test
testSort = testCase "sort" $ return () -- TODO needs sort-implementation

testTtl :: Test
testTtl = testCase "ttl" $ do
    let [k,v] = ["key","value"] :: [BS]
    set k v >>=? Just Ok
    ttl ("notAKey" :: BS) >>=? Just (-1 :: Int)
    ttl k                 >>=? Just (-1 :: Int)
    expire k (42 :: Int)           >>=? Just True
    ttl k                 >>=? Just (42 :: Int)

testGetType :: Test
testGetType = testCase "getType" $ do
    getType k     >>=? Just None
    forM_ ts $ \(setKey, typ) -> do
        setKey
        getType k >>=? Just typ
        del [k]   >>=? Just (1 :: Int)
  where
    [k,v,f,mem] = ["key","value","field","member"] :: [BS]
    ts = [ (set k v      >>=? Just Ok        , String)
         , (hset k f v   >>=? Just True      , Hash)
         , (lpush k [v]  >>=? Just (1 :: Int), List)
         , (sadd k [mem] >>=? Just (1 :: Int), Set)
         , (zadd k [(42,mem),(12.3 :: Double,v)] >>=? Just (2 :: Int), ZSet)
         ]

testObject :: Test
testObject = testCase "object" $ do
    let [k,v] = ["key","value"] :: [BS]
    set k v          >>=? Just Ok
    objectRefcount k >>=? Just (1 :: Int)
    Just _ <- objectEncoding k :: Redis (Maybe BS)
    objectIdletime k >>=? Just (0 :: Int)

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
    let [k,hello,world] = ["key","hello","world"] :: [BS]
    set k hello    >>=? Just Ok
    append k world >>=? Just (10 :: Int)
    get k          >>=? Just ("helloworld" :: BS)

testDecr :: Test
testDecr = testCase "decr" $ do
    let k = "key" :: BS
    set k ("42" :: BS) >>=? Just Ok
    decr k             >>=? Just (41 :: Int)

testDecrby :: Test
testDecrby = testCase "decrby" $ do
    let k = "key" :: BS
    set k ("42" :: BS) >>=? Just Ok
    decrby k (2 :: Int)         >>=? Just (40 :: Int)

testGetbit :: Test
testGetbit = testCase "getbit" $ getbit ("key" :: BS) (42 :: Int) >>=? Just (0 :: Int)

testGetrange :: Test
testGetrange = testCase "getrange" $ do
    let [k,v] = ["key","value"] :: [BS]
    set k v           >>=? Just Ok
    getrange k (1 :: Int) ((-2) :: Int) >>=? Just ("alu" :: BS)

testGetset :: Test
testGetset = testCase "getset" $ do
    let [k,v1,v2] = ["key","v1","v2"] :: [BS]
    getset k v1 >>=? (Nothing :: Maybe ByteString)
    getset k v2 >>=? Just ("v1" :: BS)

testIncr :: Test
testIncr = testCase "incr" $ do
    let k = "key" :: BS
    set k ("42" :: BS) >>=? Just Ok
    incr k             >>=? Just (43 :: Int)

testIncrby :: Test
testIncrby = testCase "incrby" $ do
    let k = "key" :: BS
    set k ("40" :: BS) >>=? Just Ok
    incrby k (2 :: Int)         >>=? Just (42 :: Int)

testMget :: Test
testMget = testCase "mget" $ do
    let [k1,k2,v1,v2] = ["k1","k2","v1","v2"] :: [BS]
    set k1 v1                    >>=? Just Ok
    set k2 v2                    >>=? Just Ok
    mget [k1,k2,"notAKey" :: BS] >>=? Just [ Just "v1"
                                           , Just ("v2" :: BS)
                                           , Nothing
                                           ]

testMset :: Test
testMset = testCase "mset" $ do
    let [k1,k2,v1,v2] = ["k1","k2","v1","v2"] :: [BS]
    mset [(k1,v1), (k2,v2)] >>=? Just Ok
    get k1                  >>=? Just ("v1" :: BS)
    get k2                  >>=? Just ("v2" :: BS)

testMsetnx :: Test
testMsetnx = testCase "msetnx" $ do
    let [k1,k2,v1,v2] = ["k1","k2","v1","v2"] :: [BS]
    msetnx [(k1,v1), (k2,v2)] >>=? Just True
    msetnx [(k1,v1), (k2,v2)] >>=? Just False

testSetbit :: Test
testSetbit = testCase "setbit" $ do
    let [k,one,zero] = ["key","1","0"] :: [BS]
    setbit k (42 :: Int) one  >>=? Just (0 :: Int)
    setbit k (42 :: Int) zero >>=? Just (1 :: Int)
    
testSetex :: Test
testSetex = testCase "setex" $ do
    let [k,v] = ["key","value"] :: [BS]
    setex k (1 :: Int) v >>=? Just Ok
    ttl k       >>=? Just (1 :: Int)

testSetnx :: Test
testSetnx = testCase "setnx" $ do
    let [k,v1,v2] = ["key","v1","v2"] :: [BS]
    setnx k v1 >>=? Just True
    setnx k v2 >>=? Just False

testSetrange :: Test
testSetrange = testCase "setrange" $ do
    let [k,v] = ["key","value"] :: [BS]
    set k v                    >>=? Just Ok
    setrange k (1  :: Int)("ers" :: BS) >>=? Just (5 :: Int)
    get k                      >>=? Just ("verse" :: BS)

testStrlen :: Test
testStrlen = testCase "strlen" $ do
    let [k,v] = ["key","value"] :: [BS]
    set k v  >>=? Just Ok
    strlen k >>=? Just (5 :: Int)

testSetAndGet :: Test
testSetAndGet = testCase "set/get" $ do
    let [k,v] = ["key","value"] :: [BS]
    get k   >>=? (Nothing :: Maybe ByteString)
    set k v >>=? Just Ok
    get k   >>=? Just ("value" :: BS)


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
    let [k,f,v] = ["key","field","value"] :: [BS]
    hdel k ([] :: [BS])  >>=? (Nothing :: Maybe Int)
    hdel k [f]           >>=? Just False
    hset k f v           >>=? Just True
    hdel k [f]           >>=? Just True

testHexists :: Test
testHexists = testCase "hexists" $ do
    let [k,f,v] = ["key","field","value"] :: [BS]
    hexists k f >>=? Just False
    hset k f v  >>=? Just True
    hexists k f >>=? Just True

testHget :: Test
testHget = testCase "hget" $ do
    let [k,f,v] = ["key","field","value"] :: [BS]
    hget k f   >>=? (Nothing :: Maybe ByteString)
    hset k f v >>=? Just True
    hget k f   >>=? Just ("value" :: BS)

testHgetall :: Test
testHgetall = testCase "hgetall" $ do
    let k          = "key" :: BS
        fieldsVals = [("f1","v1"), ("f2","v2")] :: [(BS,BS)]
    
    hgetall k          >>=? Just ([] :: [(ByteString, ByteString)])
    hmset k fieldsVals >>=? Just Ok
    hgetall k          >>=? Just [ ("f1", "v1")
                                 , ("f2" :: BS, "v2" :: BS)
                                 ]
    
testHincrby :: Test
testHincrby = testCase "hincrby" $ do
    let [k,f,v] = ["key","field","40"] :: [BS]
    hset k f v    >>=? Just True
    hincrby k f (2 :: Int) >>=? Just (42 :: Int)

testHkeys :: Test
testHkeys = testCase "hkeys" $ do
    let [k,f,v] = ["key","field","value"] :: [BS]
    hset k f v >>=? Just True
    hkeys k    >>=? Just ["field" :: BS]

testHlen :: Test
testHlen = testCase "hlen" $ do
    let [k,f,v] = ["key","field","value"] :: [BS]
    hlen k     >>=? Just (0 :: Int)
    hset k f v >>=? Just True
    hlen k     >>=? Just (1 :: Int)

testHmget :: Test
testHmget = testCase "hmget" $ do
    let fieldsVals = [("f1","v1"), ("f2","v2")] :: [(BS,BS)]
        k          = "key" :: BS
    hmset k fieldsVals                    >>=? Just Ok
    hmget k ["f1", "f2", "nofield" :: BS] >>=?
        Just [Just ("v1" :: BS), Just "v2", Nothing]

testHmset :: Test
testHmset = testCase "hmset" $ do
    let fieldsVals = [("f1","v1"), ("f2","v2")] :: [(BS,BS)]
    hmset ("key" :: BS) fieldsVals >>=? Just Ok

testHset :: Test
testHset = testCase "hset" $ do
    let [k,f,v] = ["key","field","value"] :: [BS]
    hset k f v >>=? Just True
    hset k f v >>=? Just False

testHsetnx :: Test
testHsetnx = testCase "hsetnx" $ do
    let [k,f,v] = ["key","field","value"] :: [BS]
    hsetnx k f v >>=? Just True
    hsetnx k f v >>=? Just False

testHvals :: Test
testHvals = testCase "hvals" $ do
    let [k,f,v] = ["key","field","value"] :: [BS]
    hset k f v  >>=? Just True
    hvals k     >>=? Just [v]


------------------------------------------------------------------------------
-- Lists
--
testsLists :: [Test]
testsLists =
    [testBlpop, testBrpoplpush, testLpop, testLinsert, testLpushx, testLset]

testBlpop :: Test
testBlpop = testCase "blpop/brpop" $ do
    let [k,notAKey,v1,v2,v3] = ["key","notAKey","v1","v2","v3"] :: [BS]
    lpush k [v3,v2,v1]  >>=? Just (3 :: Int)
    blpop [notAKey,k] (1 :: Int) >>=? Just ("key" :: BS, "v1" :: BS)
    brpop [notAKey,k] (1 :: Int) >>=? Just ("key" :: BS, "v3" :: BS)

testBrpoplpush :: Test
testBrpoplpush = testCase "brpoplpush/rpoplpush" $ do
    let [k1,k2,v1,v2] = ["k1","k2","v1","v2"] :: [BS]
    rpush k1 [v1,v2]   >>=? Just (2 :: Int)
    brpoplpush k1 k2 (1 :: Int) >>=? Just ("v2" :: BS)
    rpoplpush k1 k2    >>=? Just ("v1" :: BS)
    llen k2            >>=? Just (2 :: Int)
    llen k1            >>=? Just (0 :: Int)

testLpop :: Test
testLpop = testCase "lpop/rpop" $ do
    let [k,v1,v2,v3] = ["key","v1","v2","v3"] :: [BS]
    lpush k [v3,v2,v1] >>=? Just (3 :: Int)
    lpop k             >>=? Just ("v1" :: BS)
    llen k             >>=? Just (2 :: Int)
    rpop k             >>=? Just ("v3" :: BS)

testLinsert :: Test
testLinsert = testCase "linsert" $ do
    let [k,notAVal,v1,v2,v3] = ["key","notAVal","v1","v2","v3"] :: [BS]
    rpush k [v2]               >>=? Just (1 :: Int)
    linsertBefore k v2 v1      >>=? Just (2 :: Int)
    linsertBefore k notAVal v3 >>=? Just ((-1) :: Int)
    linsertAfter k v2 v3       >>=? Just (3 :: Int)    
    linsertAfter k notAVal v3  >>=? Just ((-1) :: Int)
    lindex k (0 :: Int)                 >>=? Just ("v1" :: BS)
    lindex k (2 :: Int)                 >>=? Just ("v3" :: BS)

testLpushx :: Test
testLpushx = testCase "lpushx/rpushx" $ do
    let [k,notAKey,v1,v2,v3] = ["key","notAKey","v1","v2","v3"] :: [BS]
    lpushx notAKey v1 >>=? Just (0 :: Int)
    lpush k [v2]      >>=? Just (1 :: Int)
    lpushx k v1       >>=? Just (2 :: Int)
    rpushx k v3       >>=? Just (3 :: Int)

testLset :: Test
testLset = testCase "lset/lrem/ltrim" $ do
    let [k,v1,v2,v3] = ["key","v1","v2","v3"] :: [BS]
    lpush k [v3,v2,v2,v1,v1] >>=? Just (5 :: Int)
    lset k (1 :: Int) v2              >>=? Just Ok
    lrem k (2 :: Int) v2              >>=? Just (2 :: Int)
    llen k                   >>=? Just (3 :: Int)
    ltrim k (0 :: Int) (1 :: Int)              >>=? Just Ok
    lrange k (0 :: Int) (1 :: Int)             >>=? Just [Just "v1", Just ("v2" :: BS)]

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
    echo ("value" :: BS) >>=? Just ("value" :: BS)

testPing :: Test
testPing = testCase "ping" $ ping >>=? Just Pong

testQuit :: Test
testQuit = testCase "quit" $ quit >>=? Just Ok

testSelect :: Test
testSelect = testCase "select" $ do
    select (13 :: Int) >>=? Just Ok
    select (0  :: Int) >>=? Just Ok


------------------------------------------------------------------------------
-- Server
--
testsServer = [testBgrewriteaof, testFlushall, testInfo, testConfig]

testBgrewriteaof :: Test
testBgrewriteaof = testCase "bgrewriteaof/bgsave/save" $ do
    save >>=? Just Ok
    -- TODO return types not as documented
    -- bgsave       >>=? Just BgSaveStarted
    -- bgrewriteaof >>=? Just BgAOFRewriteStarted

testConfig :: Test
testConfig = testCase "config/auth" $ do
    let [requirepass,pass,nil] = ["requirepass","pass",""] :: [BS]
    configSet requirepass pass >>=? Just Ok
    auth pass                  >>=? Just Ok
    configSet requirepass nil  >>=? Just Ok
    
testFlushall :: Test
testFlushall = testCase "flushall/flushdb" $ do
    flushall >>=? Just Ok
    flushdb  >>=? Just Ok

testInfo :: Test
testInfo = testCase "info/lastsave/dbsize" $ do
    Just (_ :: BS)      <- info
    Just (_ :: Integer) <- lastsave
    dbsize          >>=? Just (0 :: Int)
    configResetstat >>=? Just Ok
