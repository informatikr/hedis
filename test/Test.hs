{-# LANGUAGE OverloadedStrings, RecordWildCards #-}
module Main (main) where

import Prelude hiding (catch)
import Control.Applicative
import Control.Concurrent
import Control.Monad
import Control.Monad.Trans
import Data.Monoid (mappend)
import Data.Time
import Data.Time.Clock.POSIX
import qualified Test.HUnit as Test
import Test.HUnit (runTestTT, (~:))

import Database.Redis


------------------------------------------------------------------------------
-- Main and helpers
--
main :: IO ()
main = do
    c <- connect defaultConnectInfo
    runTestTT $ Test.TestList $ map ($c) tests
    return ()

type Test = Connection -> Test.Test

testCase :: String -> Redis () -> Test
testCase name r conn = name ~:
    Test.TestCase $ runRedis conn $ flushdb >>=? Ok >> r
    
(>>=?) :: (Eq a, Show a) => Redis (Either Reply a) -> a -> Redis ()
redis >>=? expected = do
    a <- redis
    liftIO $ case a of
        Left reply   -> Test.assertFailure $ "Redis error: " ++ show reply
        Right actual -> expected Test.@=? actual

assert :: Bool -> Redis ()
assert = liftIO . Test.assert

------------------------------------------------------------------------------
-- Tests
--
tests :: [Test]
tests = concat
    [ testsMisc, testsKeys, [testStrings], [testHashes], testsLists, testsZSets
    , [testPubSub], [testTransaction], [testScripting], testsConnection
    , testsServer, [testQuit]
    ]

------------------------------------------------------------------------------
-- Miscellaneous
--
testsMisc :: [Test]
testsMisc = [testConstantSpacePipelining, testForceErrorReply, testPipelining]

testConstantSpacePipelining :: Test
testConstantSpacePipelining = testCase "constant-space pipelining" $ do
    -- This testcase should not exceed the maximum heap size, as set in
    -- the run-test.sh script.
    replicateM_ 100000 ping
    -- If the program didn't crash, pipelining takes constant memory.
    assert True

testForceErrorReply :: Test
testForceErrorReply = testCase "force error reply" $ do
    set "key" "value"
    -- key is not a hash -> wrong kind of value
    reply <- hkeys "key"
    assert $ case reply of
        Left (Error _) -> True
        _              -> False

testPipelining :: Test
testPipelining = testCase "pipelining" $ do
    let n = 10
    tPipe <- deltaT $ do
        pongs <- replicateM n ping
        assert $ pongs == replicate n (Right Pong)
    
    tNoPipe <- deltaT $ replicateM_ n (ping >>=? Pong)
    -- pipelining should at least be twice as fast.    
    assert $ tNoPipe / tPipe > 2
  where
    deltaT redis = do
        start <- liftIO $ getCurrentTime
        redis
        liftIO $ fmap (`diffUTCTime` start) getCurrentTime

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
    ttl "key"             >>=? 1
    persist "key"         >>=? True
    rename "key" "key'"   >>=? Ok
    renamenx "key'" "key" >>=? True
    del ["key"]           >>=? 1
    select 0              >>=? Ok
    
testExpireAt :: Test
testExpireAt = testCase "expireat" $ do
    set "key" "value"         >>=? Ok
    seconds <- floor . utcTimeToPOSIXSeconds <$> liftIO getCurrentTime
    let expiry = seconds + 1
    expireat "key" expiry     >>=? True
    expireat "notAKey" expiry >>=? False
    ttl "key"                 >>=? 1


testSort :: Test
testSort = testCase "sort" $ do
    lpush "ids"     ["1","2","3"]                >>=? 3
    sort "ids" defaultSortOpts                   >>=? ["1","2","3"]
    sortStore "ids" "anotherKey" defaultSortOpts >>=? 3
    mset [("weight_1","1")
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
    decr "key"                        >>=? 41
    decrby "key" 1                    >>=? 40
    incr "key"                        >>=? 41
    incrby "key" 1                    >>=? 42
    setbit "key" 42 "1"               >>=? 0
    getbit "key" 42                   >>=? 1

------------------------------------------------------------------------------
-- Hashes
--
testHashes :: Test
testHashes = testCase "hashes" $ do
    hset "key" "field" "value"   >>=? True
    hsetnx "key" "field" "value" >>=? False
    hexists "key" "field"        >>=? True
    hlen "key"                   >>=? 1
    hget "key" "field"           >>=? Just "value"
    hmget "key" ["field", "-"]   >>=? [Just "value", Nothing]
    hgetall "key"                >>=? [("field","value")]
    hkeys "key"                  >>=? ["field"]
    hvals "key"                  >>=? ["value"]
    hdel "key" ["field"]         >>=? True
    hmset "key" [("field","40")] >>=? Ok
    hincrby "key" "field" 2      >>=? 42

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
    -- run into timeout
    blpop ["notAKey"] 1          >>=? Nothing
    rpush "k1" ["v1","v2"]       >>=? 2
    brpoplpush "k1" "k2" 1       >>=? Just "v2"
    rpoplpush "k1" "k2"          >>=? Just "v1"
    -- run into timeout
    brpoplpush "notAKey" "k2" 1  >>=? Nothing    
    
------------------------------------------------------------------------------
-- Sets
--

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
    zadd "k1" [(1, "v1"), (2, "v2")]
    zadd "k2" [(2, "v2"), (3, "v3")]
    zinterstore "newkey" ["k1","k2"] Sum                >>=? 1
    zinterstoreWeights "newkey" [("k1",1),("k2",2)] Max >>=? 1
    zunionstore "newkey" ["k1","k2"] Sum                >>=? 3
    zunionstoreWeights "newkey" [("k1",1),("k2",2)] Min >>=? 3


------------------------------------------------------------------------------
-- Pub/Sub
--
testPubSub :: Test
testPubSub conn = testCase "pubSub" go conn
  where
    go = do
        -- producer
        liftIO $ forkIO $ do
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
            liftIO $ Test.assertFailure "no subs: should return immediately"
            undefined

------------------------------------------------------------------------------
-- Transaction
--
testTransaction :: Test
testTransaction = testCase "transaction" $ do
    watch ["k1", "k2"] >>=? Ok
    unwatch            >>=? Ok
    set "foo" "foo"
    set "bar" "bar"
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
        eval script [] []                       >>=? scriptRes
        evalsha scriptHash [] []                >>=? scriptRes
        scriptExists [scriptHash, "notAScript"] >>=? [True, False]
        scriptFlush                             >>=? Ok
        -- start long running script from another client
        liftIO $ do
            forkIO $ runRedis conn $ do
                Left _ <- eval "while true do end" [] []
                    :: Redis (Either Reply Integer)
                return ()
            threadDelay $ 10^(5 :: Int)
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
    [testBgrewriteaof, testFlushall, testInfo, testConfig, testSlowlog
    ,testDebugObject]

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
    -- Right Ok <- debugSegfault
    return ()
