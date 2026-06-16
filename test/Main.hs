{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE LambdaCase #-}
module Main (main) where

import qualified Test.Framework as Test
import Database.Redis
import Tests
import PubSubTest
import System.Environment
import Text.Read (readMaybe)
import Network.Socket (PortNumber)

main :: IO ()
main = do
    redisPort <- ((readMaybe @PortNumber =<<) <$> lookupEnv "REDIS_PORT") >>= \case
            Just port -> return port
            _ -> return 6379
    host <- lookupEnv "REDIS_HOST" >>= \case
        Just host -> return host
        Nothing -> return "localhost"
    conn <- connect defaultConnectInfo { connectAddr = ConnectAddrHostPort host redisPort }
    Test.defaultMain (tests host redisPort conn)

tests :: String -> PortNumber -> Connection -> [Test.Test]
tests host port conn = map ($ conn) $ concat
    [ testsMisc, testsKeys, testsStrings, [testHashes], testsLists, testsSets, [testHyperLogLog]
    , testsZSets, [testPubSub], [testTransaction], [testScripting]
    , testsConnection host port
    , testsClient, testsServer
    , [testScans, testSScan, testHScan, testZScan], [testZrangelex]
    , [testXAddRead, testXReadGroup, testXRange, testXpending, testXClaim, testXInfo, testXDel, testXTrim]
    , [testBloomFilter, testCountMinSketch, testTopk, testCuckooFilter, testJSON]
    , testPubSubThreaded
      -- should always be run last as connection gets closed after it
    , [testQuit]
    ]


testsClient :: [Test]
testsClient = [testClientId, testClientName, testClientUnpause]

testsServer :: [Test]
testsServer =
    [testServer, testBgrewriteaof, testFlushall, testInfo, testConfig
    ,testSlowlog, testDebugObject]

testsConnection :: String -> PortNumber -> [Test]
testsConnection host port =
    [ testConnectAuth host port
    , testConnectAuthUnexpected host port
    , testConnectAuthAcl host port
    , testConnectDb host port
    , testConnectDbUnexisting host port
    , testEcho
    , testPing
    , testSelect
    ]

testsKeys :: [Test]
testsKeys = [ testKeys, testCopy, testKeysNoncluster, testExpireAt, testSort, testGetType, testObject ]
