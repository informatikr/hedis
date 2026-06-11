{-# LANGUAGE LambdaCase #-}
module Main (main) where

import qualified Test.Framework as Test
import Database.Redis
import System.Environment (lookupEnv)
import Tests

main :: IO ()
main = do
    host <- lookupEnv "REDIS_HOST" >>= \case
        Just host -> return host
        Nothing -> return "localhost"
    conn <- connect defaultConnectInfo{ connectAddr = ConnectAddrHostPort host 6379 }
    Test.defaultMain (tests conn)

tests :: Connection -> [Test.Test]
tests conn = map ($ conn)
    [ testStringCommands84
    , testHashes8
    , testRedis86Commands
    , testVectorSet8
    , testVRange84
    , testXAckDel8
    , testXDelEx8
    , testQuit
    ]
