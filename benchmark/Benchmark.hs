{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent
import Control.Monad
import Control.Monad.Trans
import Data.Time
import Database.Redis
import Text.Printf

nRequests, nClients :: Int
nRequests = 100000
nClients  = 50


main :: IO ()
main = do
    ----------------------------------------------------------------------
    -- Preparation
    --
    conn <- connect defaultConnectInfo
    runRedis conn $ do
        Right _ <- mset [ ("k1","v1"), ("k2","v2"), ("k3","v3")
                        , ("k4","v4"), ("k5","v5") ]
    
        return ()
    
    ----------------------------------------------------------------------
    -- Spawn clients
    --
    start <- newEmptyMVar
    done  <- newEmptyMVar
    replicateM_ nClients $ forkIO $ do
        c <- connect defaultConnectInfo
        runRedis c $ forever $ do
            action <- liftIO $ takeMVar start
            replicateM_ (nRequests `div` nClients) $ action
            liftIO $ putMVar done ()

    let timeAction name action = do
        startT <- getCurrentTime
        replicateM_ nClients $ putMVar start action
        replicateM_ nClients $ takeMVar done
        stopT <- getCurrentTime
        let deltaT    = realToFrac $ diffUTCTime stopT startT
            rqsPerSec = fromIntegral nRequests / deltaT :: Double
        putStrLn $ printf "%-10s %.2f Req/s" (name :: String) rqsPerSec

    ----------------------------------------------------------------------
    -- Benchmarks
    --
    timeAction "ping" $ do
        Right Pong <- ping
        return ()
        
    timeAction "get" $ do
        Right Nothing <- get "key"
        return ()
    
    timeAction "mget" $ do
        Right vs <- mget ["k1","k2","k3","k4","k5"]
        let expected = map Just ["v1","v2","v3","v4","v5"]
        True <- return $ vs == expected
        return ()
