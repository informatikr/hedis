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
tests = testsKeys ++ [testPing, testSetGet]

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
    -- TODO sleep in another thread?
    liftIO $ threadDelay 2000000 -- 2.0s
    get "key"             >>=? (Nothing :: Maybe ByteString)
    
testExpireAt :: Test
testExpireAt = testCase "expireat" $ do
    set "key" "value"         >>=? Just Ok
    TOD seconds _ <- liftIO getClockTime
    let expiry = pack . show $ seconds + 1
    expireat "key" expiry     >>=? Just True
    expireat "notAkey" expiry >>=? Just False
    -- TODO sleep in another thread?
    liftIO $ threadDelay 2000000 -- 2.0s
    get "key"                 >>=? (Nothing :: Maybe ByteString)

testKeys :: Test
testKeys = testCase "keys" $ do
    keys "key*"       >>=? Just ([] :: [ByteString])
    set "key1" "val1" >>=? Just Ok
    set "key2" "val2" >>=? Just Ok
    Just ks <- keys "key*"
    2    @=? length (ks :: [ByteString])
    True @=? elem "key1" ks
    True @=? elem "key2" ks

testMove :: Test
testMove = testCase "move" $ return () -- TODO requires ability to switch DBs

testPersist :: Test
testPersist = testCase "persist" $ do
    set "key" "value" >>=? Just Ok
    expire "key" "1"  >>=? Just True
    persist "key"     >>=? Just True
    -- TODO sleep in another thread?
    liftIO $ threadDelay 2000000 -- 2.0s
    get "key"         >>=? Just ("value" :: ByteString)

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
    ts = [ (set "key" "value"          >>=? Just Ok        , String)
         , (hset "key" "field" "value" >>=? Just True      , Hash)
         , (lpush "key" "value"        >>=? Just (1 :: Int), List)
         , (sadd "key" "member"        >>=? Just True      , Set)
         , (zadd "key" "42" "member"   >>=? Just True      , ZSet)
         ]




testPing :: Test
testPing = testCase "ping" $ ping >>=? Just Pong

testSetGet :: Test
testSetGet = testCase "set/get" $ do    
    get "key"         >>=? (Nothing :: Maybe ByteString)
    set "key" "value" >>=? Just Ok
    get "key"         >>=? Just ("value" :: ByteString)
