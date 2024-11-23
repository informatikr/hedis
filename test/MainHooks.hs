{-# LANGUAGE OverloadedStrings #-}

import qualified Test.Framework.Providers.HUnit as Test (testCase)
import qualified Test.Framework as Test
import Database.Redis
import Data.IORef
import qualified Test.HUnit as HUnit
import Control.Monad.IO.Class (MonadIO(liftIO))

main :: IO ()
main = Test.defaultMain [testSetGet]

data Counts =
    Counts 
        { sendRequestCount :: Word
        , sendPubSubCount :: Word
        , callbackCount :: Word
        , sendCount :: Word
        , receiveCount :: Word
        }
    deriving (Show, Eq)

testCase :: String -> Counts -> Redis () -> Test.Test
testCase name expected r = Test.testCase name $ do
    ref <- newIORef $ Counts 0 0 0 0 0
    conn <- connect defaultConnectInfo {connectHooks = hooks ref}
    t <- runRedis conn $ flushdb >>=? Ok >> r
    actual <- readIORef ref
    HUnit.assertEqual "count" expected actual
    return t

hooks :: IORef Counts -> Hooks
hooks ref =
    defaultHooks
        { sendRequestHook = \f message -> do
            modifyIORef ref $ \c -> c {sendRequestCount = succ $ sendRequestCount c}
            f message
        , sendPubSubHook = \f message -> do
            modifyIORef ref $ \c -> c {sendPubSubCount = succ $ sendPubSubCount c}
            f message
        , callbackHook = \f message -> do
            modifyIORef ref $ \c -> c {callbackCount = succ $ callbackCount c}
            f message
        , sendHook = \f message -> do
            modifyIORef ref $ \c -> c {sendCount = succ $ sendCount c}
            f message
        , receiveHook = \m -> do
            modifyIORef ref $ \c -> c {receiveCount = succ $ receiveCount c}
            m
        }

(>>=?) :: (Eq a, Show a) => Redis (Either Reply a) -> a -> Redis ()
redis >>=? expected = redis >>@? (expected HUnit.@=?)

(>>@?) :: (Eq a, Show a) => Redis (Either Reply a) -> (a -> HUnit.Assertion) -> Redis ()
redis >>@? predicate = do
    a <- redis
    liftIO $ case a of
        Left reply -> HUnit.assertFailure $ "Redis error: " ++ show reply
        Right actual -> predicate actual

testSetGet :: Test.Test
testSetGet =
    testCase
        "set/get"
        (Counts 3 0 0 3 3) $ do
    set "{same}key" "value"     >>=? Ok
    get "{same}key"             >>=? Just "value"
