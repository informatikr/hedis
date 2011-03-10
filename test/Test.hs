{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
module Main (main) where

import Control.Concurrent
import Control.Monad.Trans
import Data.ByteString.Char8 (ByteString, pack)
import System.Time
import qualified Test.HUnit as Test
import Test.HUnit (Assertion, Test(..), runTestTT)

import Database.Redis

------------------------------------------------------------------------------
-- Main and helpers
--
main :: IO ()
main = withSocketsDo $ do
    c <- connectTo "127.0.0.1" (PortNumber 6379)
    runTestTT $ TestList $ map (TestCase . testCase c) tests
    disconnect c

testCase :: Connection -> Redis () -> Assertion
testCase conn r = runRedis conn $ flushall >>=? Just Ok >> r

(>>=?) :: (Eq a, Show a) => Redis a -> a -> Redis ()
redis >>=? expected = redis >>= liftIO . (Test.@=?) expected

(@=?) :: (Eq a, Show a) => a -> a -> Redis ()
x @=? y = liftIO $ (Test.@=?) x y


------------------------------------------------------------------------------
-- Tests
--
tests :: [Redis ()]
tests =
    [ testDel, testExists, testExpire, testExpireAt, testKeys, testMove
    , testPersist, testRandomkey, testRename, testRenamenx, testSort
    , testTtl, testGetType
    , testPing, testSetGet]


testDel :: Redis ()
testDel = do
    set "key" "value" >>=? Just Ok
    get "key"         >>=? Just ("value" :: ByteString)
    del ["key"]       >>=? Just (1 :: Int)
    get "key"         >>=? (Nothing :: Maybe ByteString)

testExists :: Redis ()
testExists = do
    exists "key"      >>=? Just False
    set "key" "value" >>=? Just Ok
    exists "key"      >>=? Just True

testExpire :: Redis ()
testExpire = do
    set "key" "value"     >>=? Just Ok
    expire "key" "1"      >>=? Just True
    expire "notAkey" "1"  >>=? Just False
    -- TODO sleep in another thread?
    liftIO $ threadDelay 2000000 -- 2.0s
    get "key"             >>=? (Nothing :: Maybe ByteString)
    
testExpireAt :: Redis ()
testExpireAt = do
    set "key" "value"         >>=? Just Ok
    TOD seconds _ <- liftIO getClockTime
    let expiry = pack . show $ seconds + 1
    expireat "key" expiry     >>=? Just True
    expireat "notAkey" expiry >>=? Just False
    -- TODO sleep in another thread?
    liftIO $ threadDelay 2000000 -- 2.0s
    get "key"                 >>=? (Nothing :: Maybe ByteString)

testKeys :: Redis ()
testKeys = do
    keys "key*"       >>=? Just ([] :: [ByteString])
    set "key1" "val1" >>=? Just Ok
    set "key2" "val2" >>=? Just Ok
    Just ks <- keys "key*"
    2    @=? length (ks :: [ByteString])
    True @=? elem "key1" ks
    True @=? elem "key2" ks

testMove :: Redis ()
testMove = return () -- TODO requires ability to switch DBs

testPersist :: Redis ()
testPersist = do
    set "key" "value" >>=? Just Ok
    expire "key" "1"  >>=? Just True
    persist "key"     >>=? Just True
    -- TODO sleep in another thread?
    liftIO $ threadDelay 2000000 -- 2.0s
    get "key"         >>=? Just ("value" :: ByteString)

testRandomkey :: Redis ()
testRandomkey = do
    set "key1" "v1" >>=? Just Ok
    set "key2" "v2" >>=? Just Ok
    Just k <- randomkey
    True @=? ((k :: ByteString) `elem` ["key1", "key2"])

testRename :: Redis ()
testRename = do
    set "key1" "value"   >>=? Just Ok
    rename "key1" "key2" >>=? Just Ok
    get "key1"           >>=? (Nothing :: Maybe ByteString)
    get "key2"           >>=? Just ("value" :: ByteString)

testRenamenx :: Redis ()
testRenamenx = do
    set "key1" "value1"    >>=? Just Ok
    set "key2" "value2"    >>=? Just Ok
    renamenx "key1" "key2" >>=? Just False
    renamenx "key1" "key3" >>=? Just True

testSort :: Redis ()
testSort = return () -- TODO needs sort-implementation

testTtl :: Redis ()
testTtl = do
    set "key" "value" >>=? Just Ok
    ttl "notAKey"     >>=? Just (-1 :: Int)
    ttl "key"         >>=? Just (-1 :: Int)
    expire "key" "42" >>=? Just True
    ttl "key"         >>=? Just (42 :: Int)

testGetType :: Redis ()
testGetType = return () -- TODO needs getType implementation    





testPing :: Redis ()
testPing = ping >>=? Just Pong

testSetGet :: Redis ()
testSetGet = do    
    get "key"         >>=? (Nothing :: Maybe ByteString)
    set "key" "value" >>=? Just Ok
    get "key"         >>=? Just ("value" :: ByteString)
