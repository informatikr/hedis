{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Applicative
import Control.Concurrent
import Control.Monad
import Control.Monad.Trans
import Data.ByteString (ByteString)
import Data.Time
import Database.Redis.Redis
import Text.Printf

nRequests, nClients :: Int
nRequests = 100000
nClients  = 50


main :: IO ()
main = do
    ----------------------------------------------------------------------
    -- Preparation
    --
    conn <- connect localhost defaultPort
    ROk <- mSet conn [ ("k1","v1"), ("k2","v2"), ("k3","v3")
         , ("k4","v4"), ("k5" :: ByteString,"v5"::ByteString) ]
    return ()
    disconnect conn
   ----------------------------------------------------------------------
   -- Spawn clients
   --
    start <- newEmptyMVar
    done  <- newEmptyMVar
    
    replicateM_ nClients $ forkIO $ do
        
        redis <- connect localhost defaultPort
        forever $ do
            action <- liftIO $ takeMVar start
            replicateM_ (nRequests `div` nClients) $ action redis
            liftIO $ putMVar done ()

    let timeAction name action = do
        startT <- getCurrentTime
        replicateM_ nClients $ putMVar start action
        replicateM_ nClients $ takeMVar done
        stopT <- getCurrentTime
        let deltaT    = realToFrac $ diffUTCTime stopT startT
            rqsPerSec = fromIntegral nRequests / deltaT :: Double
        putStrLn $ printf "%-10s %.2f Req/s" (name :: String) rqsPerSec


    timeAction "ping" $ \redis -> do
        RPong <- ping redis
        return ()
        
    timeAction "get" $ \redis -> do
        RBulk Nothing <- (get redis ("key" :: ByteString)) :: IO (Reply ByteString)
        return ()
        
    timeAction "mget" $ \redis -> do
        reply <- mGet redis ["k1","k2","k3","k4","k5" :: ByteString]
        vs <- fromRMultiBulk' (reply :: Reply ByteString)
        let expected = ["v1","v2","v3","v4","v5"]
        True <- return $ vs == expected
        return ()
