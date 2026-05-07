{-# LANGUAGE LambdaCase #-}
module Main (main) where

import qualified Test.Framework as Test
import Database.Redis
import Tests
import PubSubTest
import System.Environment

main :: IO ()
main = do
    host <- lookupEnv "REDIS_HOST" >>= \case
        Just host -> return host
        Nothing -> return "localhost"
    conn <- connect defaultConnectInfo { connectAddr = ConnectAddrHostPort host 6379 }
    Test.defaultMain (tests host conn)

tests :: String -> Connection -> [Test.Test]
tests host conn = map ($ conn) $ concat
    [ testsMisc, testsKeys, testsStrings, [testHashes], testsLists, testsSets, [testHyperLogLog]
    , testsZSets, [testPubSub], [testTransaction], [testScripting]
    , testsConnection host
    , testsClient, testsServer
    , [testScans, testSScan, testHScan, testZScan], [testZrangelex]
    , [testXAddRead, testXReadGroup, testXRange, testXpending, testXClaim, testXInfo, testXDel, testXTrim]
    , testPubSubThreaded
      -- should always be run last as connection gets closed after it
    , [testQuit]
    ]


testsClient :: [Test]
testsClient = [testClientId, testClientName]

testsServer :: [Test]
testsServer =
    [testServer, testBgrewriteaof, testFlushall, testInfo, testConfig
    ,testSlowlog, testDebugObject]

testsConnection :: String -> [Test]
testsConnection host =
    [ testConnectAuth host
    , testConnectAuthUnexpected host
    , testConnectAuthAcl host
    , testConnectDb host
    , testConnectDbUnexisting host
    , testEcho
    , testPing
    , testSelect
    ]

testsKeys :: [Test]
testsKeys = [ testKeys, testKeysNoncluster, testExpireAt, testSort, testGetType, testObject ]
