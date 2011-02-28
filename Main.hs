{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Main where

import Control.Concurrent
import Control.Monad.Reader
import Control.Monad.State
import Control.Monad.Trans
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy.Char8 as LB
import System.IO (Handle, hClose, hFlush)

import Request
import Reply
import Internal
import PubSub



main :: IO ()
main = withSocketsDo $ do
    
    h <- connectTo "127.0.0.1" (PortNumber 6379)

    pong1 <- runRedis h $ do
        
        pubSub (subscribe "myChan") $ \msg -> do
            liftIO $ print msg
            case msg of
                (Message c "logout") -> unsubscribe "myChan"
                _                    -> return ()
        
        sendRequest ["PING"]
        
    print pong1
    
    hClose h
