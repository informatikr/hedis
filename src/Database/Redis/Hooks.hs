module Database.Redis.Hooks where

import Data.ByteString (ByteString)
import Database.Redis.Protocol (Reply)
import {-# SOURCE #-} Database.Redis.PubSub (Message, PubSub)

data Hooks =
  Hooks
    { sendRequestHook :: SendRequestHook
    , sendPubSubHook :: SendPubSubHook
    , callbackHook :: CallbackHook
    , sendHook :: SendHook
    , receiveHook :: ReceiveHook
    }

-- | A hook for sending commands to the server and receiving replys from the server.
type SendRequestHook = ([ByteString] -> IO Reply) -> [ByteString] -> IO Reply

-- | A hook for sending pub/sub messages to the server.
type SendPubSubHook = ([ByteString] -> IO ()) -> [ByteString] -> IO ()

-- | A hook for invoking callbacks with pub/sub messages.
type CallbackHook = (Message -> IO PubSub) -> Message -> IO PubSub

-- | A hook for just sending raw data to the server.
type SendHook = (ByteString -> IO ()) -> ByteString -> IO ()

-- | A hook for receiving raw data from the server.
type ReceiveHook = IO Reply -> IO Reply

-- | The default hooks.
-- Every hook is the identity function.
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
