{-# LANGUAGE CPP, OverloadedStrings, RecordWildCards #-}
module Main (main) where

#if __GLASGOW_HASKELL__ < 710
import Control.Applicative
import Data.Monoid (mappend)
#endif
import Control.Concurrent
import Control.Monad
import Control.Monad.Trans
import qualified Data.List as L (sort)
import Data.Time
import Data.Time.Clock.POSIX
import SlaveThread (fork)
import qualified Test.Framework as Test (Test, defaultMain, testGroup)
import qualified Test.Framework.Providers.HUnit as Test (testCase)
import qualified Test.HUnit as HUnit

import Database.Redis


------------------------------------------------------------------------------
-- Main and helpers
--
main :: IO ()
main = do
    conn <- connect defaultConnectInfo
    Test.defaultMain (tests conn)

type Test = Connection -> Test.Test

testCase :: String -> Redis () -> Test
testCase name r conn = Test.testCase name $ do
    withTimeLimit 0.5 $ runRedis conn $ flushdb >>=? Ok >> r
  where
    withTimeLimit limit act = do
        start <- getCurrentTime
        _ <- act
        deltaT <-fmap (`diffUTCTime` start) getCurrentTime
        when (deltaT > limit) $
            putStrLn $ name ++ ": " ++ show deltaT

(>>=?) :: (Eq a, Show a) => Redis (Either Reply a) -> a -> Redis ()
redis >>=? expected = do
    a <- redis
    liftIO $ case a of
        Left reply   -> HUnit.assertFailure $ "Redis error: " ++ show reply
        Right actual -> expected HUnit.@=? actual

assert :: Bool -> Redis ()
assert = liftIO . HUnit.assert

------------------------------------------------------------------------------
-- Tests
--
-- Defines all the test groups.

tests :: Connection -> [Test.Test]
tests conn =
    [ def "Misc" testsMisc
    , def "Keys" testsKeys
    , def "Strings" testsStrings
    , def "Hashes" testHashes
    , def "Lists" testsLists
    , def "Sets" testsSets
    , def "HyperLogLog" [testHyperLogLog]
    , def "ZSets" testsZSets
    , def "PubSub" [testPubSub]
    , def "Transaction" [testTransaction]
    , def "Scripting" [testScripting]
    , def "Connection" testsConnection
    , def "Server" testsServer
    , def "Quit" [testQuit]
    ]
    where def name l = Test.testGroup name $ map ($ conn) l

------------------------------------------------------------------------------
-- Miscellaneous
--
testsMisc :: [Test]
testsMisc =
    [ testConstantSpacePipelining
    , testForceErrorReply
    , testPipelining
    , testEvalReplies
    ]

testConstantSpacePipelining :: Test
testConstantSpacePipelining = testCase "constant-space pipelining" $ do
    -- This testcase should not exceed the maximum heap size, as set in
    -- the run-test.sh script.
    replicateM_ 100000 ping
    -- If the program didn't crash, pipelining takes constant memory.
    assert True

testForceErrorReply :: Test
testForceErrorReply = testCase "force error reply" $ do
    Right _ <- set "key" "value"
    -- key is not a hash -> wrong kind of value
    reply <- hkeys "key"
    assert $ case reply of
        Left (Error _) -> True
        _              -> False

testPipelining :: Test
testPipelining = testCase "pipelining" $ do
    let n = 100
    tPipe <- deltaT $ do
        pongs <- replicateM n ping
        assert $ pongs == replicate n (Right Pong)

    tNoPipe <- deltaT $ replicateM_ n (ping >>=? Pong)
    -- pipelining should at least be twice as fast.
    assert $ tNoPipe / tPipe > 2
  where
    deltaT redis = do
        start <- liftIO $ getCurrentTime
        _ <- redis
        liftIO $ fmap (`diffUTCTime` start) getCurrentTime

testEvalReplies :: Test
testEvalReplies conn = testCase "eval unused replies" go conn
  where
    go = do
        _ignored <- set "key" "value"
        (liftIO $ do
            threadDelay $ 10^(5::Int)
            mvar <- newEmptyMVar
            _ <- fork $ runRedis conn (get "key") >>= putMVar mvar
            takeMVar mvar)
          >>=? Just "value"

------------------------------------------------------------------------------
-- Keys
--
testsKeys :: [Test]
testsKeys = [ testKeys, testExpireAt, testSort, testGetType, testObject ]

testKeys :: Test
testKeys = testCase "keys" $ do
    set "key" "value"     >>=? Ok
    get "key"             >>=? Just "value"
    exists "key"          >>=? True
    keys "*"              >>=? ["key"]
    randomkey             >>=? Just "key"
    move "key" 13         >>=? True
    select 13             >>=? Ok
    expire "key" 1        >>=? True
    pexpire "key" 1000    >>=? True
    Right t <- ttl "key"
    assert $ t `elem` [0..1]
    Right pt <- pttl "key"
    assert $ pt `elem` [990..1000]
    persist "key"         >>=? True
    Right s <- dump "key"
    restore "key'" 0 s    >>=? Ok
    rename "key" "key'"   >>=? Ok
    renamenx "key'" "key" >>=? True
    del ["key"]           >>=? 1
    select 0              >>=? Ok

testExpireAt :: Test
testExpireAt = testCase "expireat" $ do
    set "key" "value"             >>=? Ok
    t <- ceiling . utcTimeToPOSIXSeconds <$> liftIO getCurrentTime
    let expiry = t+1
    expireat "key" expiry         >>=? True
    pexpireat "key" (expiry*1000) >>=? True

testSort :: Test
testSort = testCase "sort" $ do
    lpush "ids"     ["1","2","3"]                >>=? 3
    sort "ids" defaultSortOpts                   >>=? ["1","2","3"]
    sortStore "ids" "anotherKey" defaultSortOpts >>=? 3
    Right _ <- mset
         [("weight_1","1")
         ,("weight_2","2")
         ,("weight_3","3")
         ,("object_1","foo")
         ,("object_2","bar")
         ,("object_3","baz")
         ]
    let opts = defaultSortOpts { sortOrder = Desc, sortAlpha = True
                               , sortLimit = (1,2)
                               , sortBy    = Just "weight_*"
                               , sortGet   = ["#", "object_*"] }
    sort "ids" opts >>=? ["2", "bar", "1", "foo"]


testGetType :: Test
testGetType = testCase "getType" $ do
    getType "key"     >>=? None
    forM_ ts $ \(setKey, typ) -> do
        setKey
        getType "key" >>=? typ
        del ["key"]   >>=? 1
  where
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
testsStrings = [testStrings, testBitops, testBITPOS]

testStrings :: Test
testStrings = testCase "strings" $ do
    setnx "key" "value"               >>=? True
    getset "key" "hello"              >>=? Just "value"
    append "key" "world"              >>=? 10
    strlen "key"                      >>=? 10
    setrange "key" 0 "hello"          >>=? 10
    getrange "key" 0 4                >>=? "hello"
    mset [("k1","v1"), ("k2","v2")]   >>=? Ok
    msetnx [("k1","v1"), ("k2","v2")] >>=? False
    mget ["key"]                      >>=? [Just "helloworld"]
    setex "key" 1 "42"                >>=? Ok
    psetex "key" 1000 "42"            >>=? Ok
    decr "key"                        >>=? 41
    decrby "key" 1                    >>=? 40
    incr "key"                        >>=? 41
    incrby "key" 1                    >>=? 42
    incrbyfloat "key" 1               >>=? 43
    del ["key"]                       >>=? 1
    setbit "key" 42 "1"               >>=? 0
    getbit "key" 42                   >>=? 1
    bitcount "key"                    >>=? 1
    bitcountRange "key" 0 (-1)        >>=? 1

testBitops :: Test
testBitops = testCase "bitops" $ do
    set "k1" "a"               >>=? Ok
    set "k2" "b"               >>=? Ok
    bitopAnd "k3" ["k1", "k2"] >>=? 1
    bitopOr "k3" ["k1", "k2"]  >>=? 1
    bitopXor "k3" ["k1", "k2"] >>=? 1
    bitopNot "k3" "k1"         >>=? 1

testBITPOS :: Test
testBITPOS = testCase "BITPOS" $ do
  set "k1" "\xff\xf0\x00" >>=? Ok
  bitpos "k1" 0 0 2       >>=? 12

  set "k2" "\x00\x00\x00" >>=? Ok
  bitpos "k2" 1 0 2       >>=? (-1)

  bitpos "k3" 0 0 1       >>=? 0

------------------------------------------------------------------------------
-- Hashes
--

testHashes :: [Test]
testHashes = [testHashesAll, testHSTRLEN]

testHashesAll :: Test
testHashesAll = testCase "hashes" $ do
    hset "key" "field" "value"   >>=? True
    hsetnx "key" "field" "value" >>=? False
    hexists "key" "field"        >>=? True
    hlen "key"                   >>=? 1
    hget "key" "field"           >>=? Just "value"
    hmget "key" ["field", "-"]   >>=? [Just "value", Nothing]
    hgetall "key"                >>=? [("field","value")]
    hkeys "key"                  >>=? ["field"]
    hvals "key"                  >>=? ["value"]
    hdel "key" ["field"]         >>=? 1
    hmset "key" [("field","40")] >>=? Ok
    hincrby "key" "field" 2      >>=? 42
    hincrbyfloat "key" "field" 2 >>=? 44

testHSTRLEN :: Test
testHSTRLEN = testCase "HSTRLEN" $ do
  hset "key" "field" "value" >>=? True
  hstrlen "key" "field"      >>=? 5

------------------------------------------------------------------------------
-- Lists
--
testsLists :: [Test]
testsLists =
    [testLists, testBpop]

testLists :: Test
testLists = testCase "lists" $ do
    lpushx "notAKey" "-"          >>=? 0
    rpushx "notAKey" "-"          >>=? 0
    lpush "key" ["value"]         >>=? 1
    lpop "key"                    >>=? Just "value"
    rpush "key" ["value"]         >>=? 1
    rpop "key"                    >>=? Just "value"
    rpush "key" ["v2"]            >>=? 1
    linsertBefore "key" "v2" "v1" >>=? 2
    linsertAfter "key" "v2" "v3"  >>=? 3
    lindex "key" 0                >>=? Just "v1"
    lrange "key" 0 (-1)           >>=? ["v1", "v2", "v3"]
    lset "key" 1 "v2"             >>=? Ok
    lrem "key" 0 "v2"             >>=? 1
    llen "key"                    >>=? 2
    ltrim "key" 0 1               >>=? Ok

testBpop :: Test
testBpop = testCase "blocking push/pop" $ do
    lpush "key" ["v3","v2","v1"] >>=? 3
    blpop ["key"] 1              >>=? Just ("key","v1")
    brpop ["key"] 1              >>=? Just ("key","v3")
    rpush "k1" ["v1","v2"]       >>=? 2
    brpoplpush "k1" "k2" 1       >>=? Just "v2"
    rpoplpush "k1" "k2"          >>=? Just "v1"

------------------------------------------------------------------------------
-- Sets
--
testsSets :: [Test]
testsSets =
  [ testSADD
  , testSISMEMBER
  , testSCARD
  , testSMEMBERS
  , testSRANDMEMBER
  , testSPOP
  , testSREM
  , testSMOVE
  , testSDIFF
  , testSUNION
  , testSINTER
  , testSDIFFSTORE
  , testSUNIONSTORE
  , testSINTERSTORE
  ]

testSADD :: Test
testSADD = testCase "SADD" $ do
  sadd "s1" ["a"] >>=? 1

testSISMEMBER :: Test
testSISMEMBER = testCase "SISMEMBER" $ do
  sadd "s1" ["a"]    >>=? 1
  sismember "s1" "a" >>=? True
  sismember "s1" "b" >>=? False

testSCARD :: Test
testSCARD = testCase "SCARD" $ do
  scard "s1"      >>=? 0
  sadd "s1" ["a"] >>=? 1
  scard "s1"      >>=? 1

testSMEMBERS :: Test
testSMEMBERS = testCase "SMEMBERS" $ do
  smembers "s1"        >>=? []
  sadd "s1" ["a", "b"] >>=? 2
  Right mem <- smembers "s1"
  assert $ L.sort mem == ["a", "b"]

testSRANDMEMBER :: Test
testSRANDMEMBER = testCase "SRANDMEMBER" $ do
  srandmember "s1" >>=? Nothing
  sadd "s1" l >>=? 3
  Right (Just mem) <- srandmember "s1"
  assert $ mem `elem` l
  where l = ["a", "b", "c"]

testSPOP :: Test
testSPOP = testCase "SPOP" $ do
  spop "s1" >>=? Nothing
  sadd "s1" l >>=? 3
  Right (Just mem) <- spop "s1"
  assert $ mem `elem` l

  where l = ["a", "b", "c"]

testSREM :: Test
testSREM = testCase "SREM" $ do
  srem "s1" ["a"]      >>=? 0
  sadd "s1" ["a", "b"] >>=? 2
  srem "s1" ["a"]      >>=? 1

testSMOVE :: Test
testSMOVE = testCase "SMOVE" $ do
  sadd "s1" ["a"]     >>=? 1
  smove "s1" "s2" "a" >>=? True
  smembers "s2"       >>=? ["a"]

testSDIFF :: Test
testSDIFF = testCase "SDIFF" $ do
  sadd "s1" ["a", "b"] >>=? 2
  sadd "s2" ["a"]      >>=? 1
  sdiff ["s1", "s2"]   >>=? ["b"]

testSUNION :: Test
testSUNION = testCase "SUNION" $ do
  sadd "s1" ["a"] >>=? 1
  sadd "s2" ["b"] >>=? 1
  Right res <- sunion ["s1", "s2"]
  assert $ L.sort res == ["a", "b"]

testSINTER :: Test
testSINTER = testCase "SINTER" $ do
  sadd "s1" ["a", "b"] >>=? 2
  sadd "s2" ["b", "c"] >>=? 2
  sinter ["s1", "s2"]  >>=? ["b"]

testSDIFFSTORE :: Test
testSDIFFSTORE = testCase "SDIFFSTORE" $ do
  sadd "s1" ["a", "b"] >>=? 2
  sadd "s2" ["a"] >>=? 1
  sdiffstore "s3" ["s1", "s2"] >>=? 1
  smembers "s3" >>=? ["b"]

testSUNIONSTORE :: Test
testSUNIONSTORE = testCase "SUNIONSTORE" $ do
  sadd "s1" ["a"] >>=? 1
  sadd "s2" ["b"] >>=? 1
  sunionstore "s3" ["s1", "s2"] >>=? 2
  Right m <- smembers "s3"
  assert $ L.sort m == ["a", "b"]

testSINTERSTORE :: Test
testSINTERSTORE = testCase "SINTERSTORE" $ do
  sadd "s1" ["a", "b", "c"] >>=? 3
  sadd "s2" ["a", "b"] >>=? 2
  sinterstore "s3" ["s1", "s2"] >>=? 2
  Right m <- smembers "s3"
  assert $ L.sort m == ["a", "b"]

------------------------------------------------------------------------------
-- Sorted Sets
--
testsZSets :: [Test]
testsZSets = [testZSets, testZStore]

testZSets :: Test
testZSets = testCase "sorted sets" $ do
    zadd "key" [(1,"v1"),(2,"v2"),(40,"v3")]          >>=? 3
    zcard "key"                                       >>=? 3
    zscore "key" "v3"                                 >>=? Just 40
    zincrby "key" 2 "v3"                              >>=? 42

    zrank "key" "v1"                                  >>=? Just 0
    zrevrank "key" "v1"                               >>=? Just 2
    zcount "key" 10 100                               >>=? 1

    zrange "key" 0 1                                  >>=? ["v1","v2"]
    zrevrange "key" 0 1                               >>=? ["v3","v2"]
    zrangeWithscores "key" 0 1                        >>=? [("v1",1),("v2",2)]
    zrevrangeWithscores "key" 0 1                     >>=? [("v3",42),("v2",2)]
    zrangebyscore "key" 0.5 1.5                       >>=? ["v1"]
    zrangebyscoreWithscores "key" 0.5 1.5             >>=? [("v1",1)]
    zrangebyscoreLimit "key" 0.5 2.5 0 1              >>=? ["v1"]
    zrangebyscoreWithscoresLimit "key" 0.5 2.5 0 1    >>=? [("v1",1)]
    zrevrangebyscore "key" 1.5 0.5                    >>=? ["v1"]
    zrevrangebyscoreWithscores "key" 1.5 0.5          >>=? [("v1",1)]
    zrevrangebyscoreLimit "key" 2.5 0.5 0 1           >>=? ["v2"]
    zrevrangebyscoreWithscoresLimit "key" 2.5 0.5 0 1 >>=? [("v2",2)]

    zrem "key" ["v2"]                                 >>=? 1
    zremrangebyscore "key" 10 100                     >>=? 1
    zremrangebyrank "key" 0 0                         >>=? 1

testZStore :: Test
testZStore = testCase "zunionstore/zinterstore" $ do
    Right _ <- zadd "k1" [(1, "v1"), (2, "v2")]
    Right _ <- zadd "k2" [(2, "v2"), (3, "v3")]
    zinterstore "newkey" ["k1","k2"] Sum                >>=? 1
    zinterstoreWeights "newkey" [("k1",1),("k2",2)] Max >>=? 1
    zunionstore "newkey" ["k1","k2"] Sum                >>=? 3
    zunionstoreWeights "newkey" [("k1",1),("k2",2)] Min >>=? 3

------------------------------------------------------------------------------
-- HyperLogLog
--

testHyperLogLog :: Test
testHyperLogLog = testCase "hyperloglog" $ do
  -- test creation
  Right _ <- pfadd "hll1" ["a"]
  pfcount ["hll1"] >>=? 1
  -- test cardinality
  Right _ <- pfadd "hll1" ["a"]
  pfcount ["hll1"] >>=? 1
  Right _ <- pfadd "hll1" ["b", "c", "foo", "bar"]
  pfcount ["hll1"] >>=? 5
  -- test merge
  Right _ <- pfadd "hll2" ["1", "2", "3"]
  Right _ <- pfadd "hll3" ["4", "5", "6"]
  Right _ <- pfmerge "hll4" ["hll2", "hll3"]
  pfcount ["hll4"] >>=? 6
  -- test union cardinality
  pfcount ["hll2", "hll3"] >>=? 6

------------------------------------------------------------------------------
-- Pub/Sub
--
testPubSub :: Test
testPubSub conn = testCase "pubSub" go conn
  where
    go = do
        -- producer
        _ <- liftIO $ fork $ do
            runRedis conn $ do
                let t = 10^(5 :: Int)
                liftIO $ threadDelay t
                publish "chan1" "hello" >>=? 1
                liftIO $ threadDelay t
                publish "chan2" "world" >>=? 1
            return ()

        -- consumer
        pubSub (subscribe ["chan1"]) $ \msg -> do
            -- ready for a message
            case msg of
                Message{..} -> return
                    (unsubscribe [msgChannel] `mappend` psubscribe ["chan*"])
                PMessage{..} -> return (punsubscribe [msgPattern])

        pubSub (subscribe [] `mappend` psubscribe []) $ \_ -> do
            liftIO $ HUnit.assertFailure "no subs: should return immediately"
            undefined

------------------------------------------------------------------------------
-- Transaction
--
testTransaction :: Test
testTransaction = testCase "transaction" $ do
    watch ["k1", "k2"] >>=? Ok
    unwatch            >>=? Ok
    Right _ <- set "foo" "foo"
    Right _ <- set "bar" "bar"
    foobar <- multiExec $ do
        foo <- get "foo"
        bar <- get "bar"
        return $ (,) <$> foo <*> bar
    assert $ foobar == TxSuccess (Just "foo", Just "bar")


------------------------------------------------------------------------------
-- Scripting
--
testScripting :: Test
testScripting conn = testCase "scripting" go conn
  where
    go = do
        let script    = "return {false, 42}"
            scriptRes = (False, 42 :: Integer)
        Right scriptHash <- scriptLoad script
        eval script [] []                       >>=? scriptRes
        evalsha scriptHash [] []                >>=? scriptRes
        scriptExists [scriptHash, "notAScript"] >>=? [True, False]
        scriptFlush                             >>=? Ok
        -- start long running script from another client
        configSet "lua-time-limit" "100"        >>=? Ok
        liftIO $ do
            _ <- fork $ runRedis conn $ do
                -- we must pattern match to block the thread
                Left _ <- eval "while true do end" [] []
                    :: Redis (Either Reply Integer)
                return ()
            threadDelay 500000 -- 0.5s
        scriptKill                              >>=? Ok

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
testsServer :: [Test]
testsServer =
    [testServer, testBgrewriteaof, testFlushall, testInfo, testConfig
    ,testSlowlog, testDebugObject]

testServer :: Test
testServer = testCase "server" $ do
    Right (_,_) <- time
    slaveof "no" "one" >>=? Ok
    return ()

testBgrewriteaof :: Test
testBgrewriteaof = testCase "bgrewriteaof/bgsave/save" $ do
    save >>=? Ok
    Right (Status _) <- bgsave
    -- Redis needs time to finish the bgsave
    liftIO $ threadDelay (10^(5 :: Int))
    Right (Status _) <- bgrewriteaof
    return ()

testConfig :: Test
testConfig = testCase "config/auth" $ do
    configGet "requirepass"        >>=? [("requirepass", "")]
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
    slowlogReset >>=? Ok
    slowlogGet 5 >>=? []
    slowlogLen   >>=? 0

testDebugObject :: Test
testDebugObject = testCase "debugObject/debugSegfault" $ do
    set "key" "value" >>=? Ok
    Right _ <- debugObject "key"
    return ()
