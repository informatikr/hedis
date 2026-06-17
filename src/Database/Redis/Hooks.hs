-- |Hooks for observing or wrapping Redis I/O.
--
-- Hooks are installed through @connect defaultConnectInfo { connectHooks = ... }@
-- and wrap the low-level actions used by hedis:
--
-- * 'sendRequestHook' wraps regular command execution.
-- * 'sendPubSubHook' wraps pub/sub command sending.
-- * 'callbackHook' wraps invocation of pub/sub callbacks.
-- * 'sendHook' wraps raw bytes sent to the server.
-- * 'receiveHook' wraps reply reception.
--
-- The common pattern is to start from 'defaultHooks' and override only the
-- hook(s) you need. Each hook receives the original action and is expected to
-- call it after performing any extra work such as logging, tracing, metrics,
-- or timing.
--
-- Hooks can be used to alter existing behavior, or used to add metrics or telemetry
-- to the redis application.
--
-- Example:
--
-- @
-- import Data.IORef
-- import Database.Redis
--
-- data Counts = Counts
--   { sendRequestCount :: Word
--   , sendCount :: Word
--   , receiveCount :: Word
--   }
--
-- hooks :: IORef Counts -> Hooks
-- hooks ref =
--   defaultHooks
--     { sendRequestHook = \\run argv -> do
--         modifyIORef ref $ \\c -> c { sendRequestCount = sendRequestCount c + 1 }
--         run argv
--     , sendHook = \\sendBytes bytes -> do
--         modifyIORef ref $ \\c -> c { sendCount = sendCount c + 1 }
--         sendBytes bytes
--     , receiveHook = \\recvReply -> do
--         modifyIORef ref $ \\c -> c { receiveCount = receiveCount c + 1 }
--         recvReply
--     }
--
-- main :: IO ()
-- main = do
--   ref <- newIORef (Counts 0 0 0)
--   conn <- connect defaultConnectInfo { connectHooks = hooks ref }
--   _ <- runRedis conn $ set "key" "value"
--   readIORef ref >>= print
-- @
module Database.Redis.Hooks where

import Data.ByteString (ByteString)
import Database.Redis.Protocol (Reply)
import {-# SOURCE #-} Database.Redis.PubSub (Message, PubSub)

-- |A collection of hook functions used by a connection.
data Hooks =
  Hooks
    { sendRequestHook :: SendRequestHook
    , sendPubSubHook :: SendPubSubHook
    , callbackHook :: CallbackHook
    , sendHook :: SendHook
    , receiveHook :: ReceiveHook
    }

-- |A hook for sending commands to the server and receiving replies from the server.
--
-- This wraps the command-level request path used by most Redis commands.
type SendRequestHook = ([ByteString] -> IO Reply) -> [ByteString] -> IO Reply

-- |A hook for sending pub/sub messages to the server.
type SendPubSubHook = ([ByteString] -> IO ()) -> [ByteString] -> IO ()

-- |A hook for invoking callbacks with pub/sub messages.
type CallbackHook = (Message -> IO PubSub) -> Message -> IO PubSub

-- |A hook for sending raw bytes to the server.
--
-- This sits below request rendering and can be used to observe the exact wire
-- payload sent on the socket.
type SendHook = (ByteString -> IO ()) -> ByteString -> IO ()

-- |A hook for receiving replies from the server.
type ReceiveHook = IO Reply -> IO Reply

-- |The default hooks.
--
-- Every hook is the identity function, so installing 'defaultHooks' has no
-- effect on behavior.
defaultHooks :: Hooks
defaultHooks =
  Hooks
    { sendRequestHook = id
    , sendPubSubHook = id
    , callbackHook = id
    , sendHook = id
    , receiveHook = id
    }

instance Show Hooks where
  show _ = "Hooks {sendRequestHook = _, sendPubSubHook = _, callbackHook = _, sendHook = _, receiveHook = _}"
