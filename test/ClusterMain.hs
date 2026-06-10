{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE LambdaCase #-}

module Main (main) where

import qualified Test.Framework as Test
import Data.ByteString (ByteString)
import Database.Redis
import Network.Socket (PortNumber)
import System.Environment (lookupEnv)
import Tests
import Text.Read (readMaybe)
import PubSubTest (testPubSubThreaded)

main :: IO ()
main = do

    redisPort <- ((readMaybe @PortNumber =<<) <$> lookupEnv "REDIS_PORT") >>= \case
            Just port -> return port
            _ -> return 6379
    redisHost <- lookupEnv "REDIS_HOST" >>= \case
        Just host -> return host
        Nothing -> return "localhost"
    -- We're looking for the cluster on a non-default port to support running
    -- this test in parallel witht the regular non-cluster tests. To quickly
    -- spin up a cluster on this port using docker you can run:
    --
    --     docker run -e "IP=0.0.0.0" -p 7000-7010:7000-7010 grokzen/redis-cluster:5.0.6
    conn <- connectCluster defaultConnectInfo { connectAddr = ConnectAddrHostPort redisHost redisPort }
    Test.defaultMain (tests redisHost redisPort conn)

tests :: String -> PortNumber -> Connection -> [Test.Test]
tests host port conn = map ($ conn) $ concat @[]
    [ testsMisc, testsKeys, testsStrings, [testHashes], testsLists, testsSets, [testHyperLogLog]
    , testsZSets, [testTransaction], [testScripting]
    , testsConnection host port, testsClient, testsServer, [testSScan, testHScan, testZScan], [testZrangelex]
    , [testXAddRead, testXReadGroup, testXRange, testXpending7, testXClaim, testXInfo, testXDel, testXTrim, testClusterSlotStats8]
      -- should always be run last as connection gets closed after it
    , testPubSubThreaded
    , [testQuit]
    ]

testsClient :: [Test]
testsClient = [testClientId, testClientName]

testsServer :: [Test]
testsServer =
    [testBgrewriteaof, testFlushall, testSlowlog, testDebugObject]

testsConnection :: String -> PortNumber -> [Test]
testsConnection host port = [ testConnectAuthUnexpected host port, testEcho, testPing ]

testsKeys :: [Test]
testsKeys = [ testKeys, testExpireAt, testSortCluster, testGetType, testObject ]

testSortCluster :: Test
testSortCluster = testCase "sort" $ do
    lpush "{same}ids"     ["1"::ByteString,"2","3"]          >>=? 3
    sort "{same}ids" defaultSortOpts                         >>=? ["1","2","3"]
    sortStore "{same}ids" "{same}anotherKey" defaultSortOpts >>=? 3
    let opts = defaultSortOpts { sortOrder = Desc, sortAlpha = True
                               , sortLimit = (1,2)
                               , sortBy    = Nothing
                               , sortGet   = [] }
    sort "{same}ids" opts >>=? ["2", "1"]
