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

------------------------------------------------------------------------------
-- Main and helpers
--
main :: IO ()
main = withSocketsDo $ do
    c <- newConnPool 1 "127.0.0.1" (PortNumber 6379)
    runTestTT $ Test.TestList $ map ($c) tests
    disconnectConnPool c


type Test = ConnPool -> Test.Test

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
    [testsKeys, testsStrings, testsHashes, testsConnection, [testQuit]]


------------------------------------------------------------------------------
-- Keys
--
testsKeys :: [Test]
testsKeys =
    [ testDel, testExists, testExpire, testExpireAt, testKeys, testMove
    , testPersist, testRandomkey, testRename, testRenamenx, testSort
    , testTtl, testGetType
    ]

testDel :: Test
testDel = testCase "del" $ do
    set "key" "value" >>=? Just Ok
    get "key"         >>=? Just ("value" :: ByteString)
    del ["key"]       >>=? Just (1 :: Int)
    get "key"         >>=? (Nothing :: Maybe ByteString)

testExists :: Test
testExists = testCase "exists" $ do
    exists "key"      >>=? Just False
    set "key" "value" >>=? Just Ok
    exists "key"      >>=? Just True

testExpire :: Test
testExpire = testCase "expire" $ do
    set "key" "value"     >>=? Just Ok
    expire "key" "1"      >>=? Just True
    expire "notAkey" "1"  >>=? Just False
    ttl "key"             >>=? Just (1 :: Int)
    
testExpireAt :: Test
testExpireAt = testCase "expireat" $ do
    set "key" "value"         >>=? Just Ok
    TOD seconds _ <- liftIO getClockTime
    let expiry = seconds + 1
    expireat "key" expiry     >>=? Just True
    expireat "notAkey" expiry >>=? Just False
    ttl "key"                 >>=? Just (1 :: Int)

testKeys :: Test
testKeys = testCase "keys" $ do
    keys "key*"       >>=? Just ([] :: [Maybe ByteString])
    set "key1" "val1" >>=? Just Ok
    set "key2" "val2" >>=? Just Ok
    Just ks <- keys "key*"
    2    @=? length (ks :: [Maybe ByteString])
    True @=? elem (Just "key1") ks
    True @=? elem (Just "key2") ks

testMove :: Test
testMove = testCase "move" $ do
    set "key" "value" >>=? Just Ok
    move "key" "13"   >>=? Just True
    get "key"         >>=? (Nothing :: Maybe ByteString)
    select "13"       >>=? Just Ok
    get "key"         >>=? Just ("value" :: ByteString)

testPersist :: Test
testPersist = testCase "persist" $ do
    set "key" "value" >>=? Just Ok
    expire "key" "1"  >>=? Just True
    ttl "key"         >>=? Just (1 :: Int)
    persist "key"     >>=? Just True
    ttl "key"         >>=? Just (-1 :: Int)

testRandomkey :: Test
testRandomkey = testCase "randomkey" $ do
    set "key1" "v1" >>=? Just Ok
    set "key2" "v2" >>=? Just Ok
    Just k <- randomkey
    True @=? ((k :: ByteString) `elem` ["key1", "key2"])

testRename :: Test
testRename = testCase "rename" $ do
    set "key1" "value"   >>=? Just Ok
    rename "key1" "key2" >>=? Just Ok
    get "key1"           >>=? (Nothing :: Maybe ByteString)
    get "key2"           >>=? Just ("value" :: ByteString)

testRenamenx :: Test
testRenamenx = testCase "renamenx" $ do
    set "key1" "value1"    >>=? Just Ok
    set "key2" "value2"    >>=? Just Ok
    renamenx "key1" "key2" >>=? Just False
    renamenx "key1" "key3" >>=? Just True

testSort :: Test
testSort = testCase "sort" $ return () -- TODO needs sort-implementation

testTtl :: Test
testTtl = testCase "ttl" $ do
    set "key" "value" >>=? Just Ok
    ttl "notAKey"     >>=? Just (-1 :: Int)
    ttl "key"         >>=? Just (-1 :: Int)
    expire "key" "42" >>=? Just True
    ttl "key"         >>=? Just (42 :: Int)

testGetType :: Test
testGetType = testCase "getType" $ do
    getType "key"     >>=? Just None
    forM_ ts $ \(setKey, typ) -> do
        setKey
        getType "key" >>=? Just typ
        del ["key"]   >>=? Just (1 :: Int)
  where
    ts = [ (set "key" "value"            >>=? Just Ok        , String)
         , (hset "key" "field" "value"   >>=? Just True      , Hash)
         , (lpush "key" ["value"]        >>=? Just (1 :: Int), List)
         , (sadd "key" ["member"]        >>=? Just (1 :: Int), Set)
         , (zadd "key" [(42 :: Double,"member" :: ByteString)
                       ,(12.3,"mem2")] >>=? Just (2 :: Int), ZSet)
         ]


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
    set "key" "x"    >>=? Just Ok
    append "key" "y" >>=? Just (2 :: Int)
    get "key"        >>=? Just ("xy" :: ByteString)

testDecr :: Test
testDecr = testCase "decr" $ do
    set "key" "42" >>=? Just Ok
    decr "key"     >>=? Just (41 :: Int)

testDecrby :: Test
testDecrby = testCase "decrby" $ do
    set "key" "42"   >>=? Just Ok
    decrby "key" "2" >>=? Just (40 :: Int)

testGetbit :: Test
testGetbit = testCase "getbit" $ getbit "key" "42" >>=? Just (0 :: Int)

testGetrange :: Test
testGetrange = testCase "getrange" $ do
    set "key" "value"       >>=? Just Ok
    getrange "key" "1" "-2" >>=? Just ("alu" :: ByteString)

testGetset :: Test
testGetset = testCase "getset" $ do
    getset "key" "v1" >>=? (Nothing :: Maybe ByteString)
    getset "key" "v2" >>=? Just ("v1" :: ByteString)

testIncr :: Test
testIncr = testCase "incr" $ do
    set "key" "42" >>=? Just Ok
    incr "key"     >>=? Just (43 :: Int)

testIncrby :: Test
testIncrby = testCase "incrby" $ do
    set "key" "42"   >>=? Just Ok
    incrby "key" "2" >>=? Just (44 :: Int)

testMget :: Test
testMget = testCase "mget" $ do
    set "key1" "v1"                  >>=? Just Ok
    set "key2" "v2"                  >>=? Just Ok
    mget ["key1", "key2", "notAKey"] >>=? Just [ Just "v1"
                                               , Just ("v2" :: ByteString)
                                               , Nothing
                                               ]

testMset :: Test
testMset = testCase "mset" $ do
    mset [("k1","v1"), ("k2","v2")] >>=? Just Ok
    get "k1"                        >>=? Just ("v1" :: ByteString)
    get "k2"                        >>=? Just ("v2" :: ByteString)

testMsetnx :: Test
testMsetnx = testCase "msetnx" $ do
    msetnx [("k1","v1"), ("k2","v2")] >>=? Just True
    msetnx [("k1","v1"), ("k2","v2")] >>=? Just False

testSetbit :: Test
testSetbit = testCase "setbit" $ do
    setbit "key" "42" "1" >>=? Just (0 :: Int)
    setbit "key" "42" "0" >>=? Just (1 :: Int)
    
testSetex :: Test
testSetex = testCase "setex" $ do
    setex "key" "1" "value" >>=? Just Ok
    ttl "key"               >>=? Just (1 :: Int)

testSetnx :: Test
testSetnx = testCase "setnx" $ do
    setnx "key" "v1" >>=? Just True
    setnx "key" "v2" >>=? Just False

testSetrange :: Test
testSetrange = testCase "setrange" $ do
    set "key" "value"        >>=? Just Ok
    setrange "key" "1" "ers" >>=? Just (5 :: Int)
    get "key"                >>=? Just ("verse" :: ByteString)

testStrlen :: Test
testStrlen = testCase "strlen" $ do
    set "key" "value" >>=? Just Ok
    strlen "key"      >>=? Just (5 :: Int)

testSetAndGet :: Test
testSetAndGet = testCase "set/get" $ do    
    get "key"         >>=? (Nothing :: Maybe ByteString)
    set "key" "value" >>=? Just Ok
    get "key"         >>=? Just ("value" :: ByteString)


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
    hdel "key" []              >>=? (Nothing :: Maybe Int)
    hdel "key" ["field"]       >>=? Just False
    hset "key" "field" "value" >>=? Just True
    hdel "key" ["field"]       >>=? Just True

testHexists :: Test
testHexists = testCase "hexists" $ do
    hexists "key" "field"      >>=? Just False
    hset "key" "field" "value" >>=? Just True
    hexists "key" "field"      >>=? Just True

testHget :: Test
testHget = testCase "hget" $ do
    hget "key" "field"         >>=? (Nothing :: Maybe ByteString)
    hset "key" "field" "value" >>=? Just True
    hget "key" "field"         >>=? Just ("value" :: ByteString)

testHgetall :: Test
testHgetall = testCase "hgetall" $ do
    hgetall "key" >>=? Just ([] :: [(ByteString, ByteString)])
    hmset "key" [("f1","v1"), ("f2","v2")]
                  >>=? Just Ok
    hgetall "key" >>=? Just [ ("f1", "v1")
                            , ("f2" :: ByteString, "v2" :: ByteString)
                            ]
    
testHincrby :: Test
testHincrby = testCase "hincrby" $ do
    hset "key" "field" "42"    >>=? Just True
    hincrby "key" "field" "-2" >>=? Just (40 :: Int)

testHkeys :: Test
testHkeys = testCase "hkeys" $ do
    hset "key" "field" "value" >>=? Just True
    hkeys "key"                >>=? Just ["field" :: ByteString]

testHlen :: Test
testHlen = testCase "hlen" $ do
    hlen "key"                 >>=? Just (0 :: Int)
    hset "key" "field" "value" >>=? Just True
    hlen "key"                 >>=? Just (1 :: Int)

testHmget :: Test
testHmget = testCase "hmget" $ do
    hmset "key" [("f1","v1"), ("f2","v2")] >>=? Just Ok
    hmget "key" ["f1", "f2", "nofield"]    >>=?
        Just [Just ("v1" :: ByteString), Just "v2", Nothing]

testHmset :: Test
testHmset = testCase "hmset" $ do
    let m :: [(ByteString,ByteString)]
        m = [("f1","v1"), ("f2","v2")]
    hmset "key" m >>=? Just Ok

testHset :: Test
testHset = testCase "hset" $ do
    hset "key" "field" "value" >>=? Just True
    hset "key" "field" "value" >>=? Just False

testHsetnx :: Test
testHsetnx = testCase "hsetnx" $ do
    hsetnx "key" "field" "value" >>=? Just True
    hsetnx "key" "field" "value" >>=? Just False

testHvals :: Test
testHvals = testCase "hvals" $ do
    hset "key" "field" "value" >>=? Just True
    hvals "key"                >>=? Just ["value" :: ByteString]


------------------------------------------------------------------------------
-- Lists
--


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
testsConnection = [ testAuth, testEcho, testPing, testSelect ]

testAuth :: Test
testAuth = testCase "auth" $ return () -- TODO test auth

testEcho :: Test
testEcho = testCase "echo" $ echo "value" >>=? Just ("value" :: ByteString)

testPing :: Test
testPing = testCase "ping" $ ping >>=? Just Pong

testQuit :: Test
testQuit = testCase "quit" $ quit >>=? Just Ok

testSelect :: Test
testSelect = testCase "select" $ do
    select "13" >>=? Just Ok
    select "0"  >>=? Just Ok


------------------------------------------------------------------------------
-- Server
--
