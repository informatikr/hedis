{-# LANGUAGE OverloadedStrings #-}
module Main where

import Control.Concurrent
import Control.Monad.Reader
import Control.Monad.State
import Control.Monad.Trans
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy.Char8 as LB
import System.IO (Handle, hClose, hFlush)

import Database.Redis



main :: IO ()
main = withSocketsDo $ do
    
    h <- connectTo "127.0.0.1" (PortNumber 6379)

    pong <- runRedis h $ do
        p1 <- sendRequest ["PING"]
        p2 <- sendRequest ["PING"]
        return (p1,p2)
        
    print pong
    
    hClose h
