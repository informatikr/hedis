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
    start <- newEmptyMVar
    done  <- newEmptyMVar
    
    replicateM_ nClients $ forkIO $ do
        c <- connect "localhost" (PortNumber 6379)
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


    timeAction "ping" $ do
        Right Pong <- ping
        return ()
        
    timeAction "get" $ do
        Right Nothing <- get "key"
        return ()
    