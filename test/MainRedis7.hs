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
    [ testSet7
    , testZAdd7
    , testExpireTime7
    , testHashExpire7
    , testSintercard7
    , testLMPop7
    , testZMPop7
    , testFunction7
    , testCommandList7
    , testXCreateGroup7
    , testXpending7
    , testXAutoClaim7
    , testQuit
    ]
