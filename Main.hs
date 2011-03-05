{-# LANGUAGE OverloadedStrings, FlexibleInstances,
    UndecidableInstances, OverlappingInstances #-}
module Main where

import Control.Applicative
import Control.Concurrent
import Control.Monad.Reader
import Control.Monad.State
import Control.Monad.Trans
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy.Char8 as LB
import qualified Data.Map as Map
import qualified Data.Set as Set
import System.IO (Handle, hClose, hFlush)

import Database.Redis


main :: IO ()
main = withSocketsDo $ do

    h <- connectTo "127.0.0.1" (PortNumber 6379)

    pong1 <- runRedis h $ do
        
        -- h <- hgetall "myHash"
        -- return (h :: Maybe (Map.Map B.ByteString B.ByteString))
        -- l <- lrange "mylist" "0" "10"
        -- return (l :: Maybe [B.ByteString])
        s <- sunion ["mySet1", "mySet2"]
        return (s :: Maybe [B.ByteString])
        
        
    print pong1
    
    hClose h
