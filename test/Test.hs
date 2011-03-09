{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
module Main where

import Control.Concurrent
import Control.Monad.Trans
import Data.ByteString.Char8 (ByteString, pack)
import System.IO (hClose)
import System.Time
import Database.Redis
import qualified Test.HUnit as Test
import Test.HUnit (Assertion, Test(..), runTestTT)


------------------------------------------------------------------------------
-- Main and helpers
--
main :: IO ()
main = withSocketsDo $ do
    c <- connectTo "127.0.0.1" (PortNumber 6379)
    runTestTT $ TestList $ map (TestCase . testCase c) tests
    hClose c

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
    set "key" "value"     >>=? Just Ok
    TOD seconds _ <- liftIO getClockTime
    let expiry = pack . show $ seconds + 1
    expireat "key" expiry      >>=? Just True
    expireat "notAkey" expiry  >>=? Just False
    -- TODO sleep in another thread?
    liftIO $ threadDelay 2000000 -- 2.0s
    get "key"             >>=? (Nothing :: Maybe ByteString)

testKeys :: Redis ()
testKeys = do
    keys "key*"       >>=? Just ([] :: [ByteString])
    set "key1" "val1" >>=? Just Ok
    set "key2" "val2" >>=? Just Ok
    Just keys <- keys "key*"
    2    @=? length (keys :: [ByteString])
    True @=? elem "key1" keys
    True @=? elem "key2" keys

testMove :: Redis ()
testMove = return () -- TODO requires ability to switch DBs



testPing :: Redis ()
testPing = ping >>=? Just Pong

testSetGet :: Redis ()
testSetGet = do    
    set "key" "value" >>=? Just Ok
    get "key"         >>=? Just ("value" :: ByteString)
    get "notAKey"     >>=? (Nothing :: Maybe ByteString)
