{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE TypeApplications #-}

module Main (main) where

import qualified Test.Framework as Test
import Data.ByteString (ByteString)
import Database.Redis
import Tests

main :: IO ()
main = do
    -- We're looking for the cluster on a non-default port to support running
    -- this test in parallel witht the regular non-cluster tests. To quickly
    -- spin up a cluster on this port using docker you can run:
    --
    --     docker run -e "IP=0.0.0.0" -p 7000-7010:7000-7010 grokzen/redis-cluster:5.0.6
    conn <- connectCluster defaultConnectInfo { connectPort = PortNumber 7000 }
    Test.defaultMain (tests conn)

tests :: Connection -> [Test.Test]
tests conn = map ($ conn) $ concat @[]
    [ testsMisc, testsKeys, testsStrings, [testHashes], testsLists, testsSets, [testHyperLogLog]
    , testsZSets, [testTransaction], [testScripting]
    , testsConnection, testsClient, testsServer, [testSScan, testHScan, testZScan], [testZrangelex]
    , [testXAddRead, testXReadGroup, testXRange, testXpending, testXClaim, testXInfo, testXDel, testXTrim]
      -- should always be run last as connection gets closed after it
    , [testQuit]
    ]

testsClient :: [Test]
testsClient = [testClientId, testClientName]

testsServer :: [Test]
testsServer =
    [testBgrewriteaof, testFlushall, testSlowlog, testDebugObject]

testsConnection :: [Test]
testsConnection = [ testConnectAuthUnexpected, testEcho, testPing
                  ]

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
