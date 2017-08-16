{-# LANGUAGE RecordWildCards, DeriveDataTypeable, OverloadedStrings #-}

-- |A module for automatic, optimal protocol pipelining.
--
--  Protocol pipelining is a technique in which multiple requests are written
--  out to a single socket without waiting for the corresponding responses.
--  The pipelining of requests results in a dramatic improvement in protocol
--  performance.
--
--  [Optimal Pipelining] uses the least number of network packets possible
--
--  [Automatic Pipelining] means that requests are implicitly pipelined as much
--      as possible, i.e. as long as a request's response is not used before any
--      subsequent requests.
--
module Database.Redis.ProtocolPipelining (
  Connection,
  connect, disconnect, request, send, recv, flush,
  ConnectionLostException(..),
  HostName, PortID(..)
) where

import           Prelude
import           Control.Exception
import           Control.Monad
import qualified Scanner
import qualified Data.ByteString as S
import           Data.IORef
import           Data.Typeable
import           Network
import qualified Network.BSD as BSD
import qualified Network.Socket as NS
import           System.IO
import           System.IO.Error
import           System.IO.Unsafe

import           Database.Redis.Protocol


data Connection = Conn
  { connHandle     :: Handle        -- ^ Connection socket-handle.
  , connReplies    :: IORef [Reply] -- ^ Reply thunks for unsent requests.
  , connPending    :: IORef [Reply]
    -- ^ Reply thunks for requests "in the pipeline". Refers to the same list as
    --   'connReplies', but can have an offset.
  , connPendingCnt :: IORef Int
    -- ^ Number of pending replies and thus the difference length between
    --   'connReplies' and 'connPending'.
    --   length connPending  - pendingCount = length connReplies
  }

data ConnectionLostException = ConnectionLost
  deriving (Show, Typeable)

instance Exception ConnectionLostException

connect :: HostName -> PortID -> IO Connection
connect hostName (PortNumber port) =
  bracketOnError hConnect hClose $ \connHandle -> do
    hSetBinaryMode connHandle True
    connReplies <- newIORef []
    connPending <- newIORef []
    connPendingCnt <- newIORef 0
    let conn = Conn{..}
    rs <- connGetReplies conn
    writeIORef connReplies rs
    writeIORef connPending rs
    return conn
  where hConnect =
          bracketOnError mkSocket NS.close $ \sock -> do
          NS.setSocketOption sock NS.KeepAlive 1
          host <- BSD.getHostByName hostName
          NS.connect sock $ NS.SockAddrInet port (BSD.hostAddress host)
          NS.socketToHandle sock ReadWriteMode
        mkSocket = NS.socket NS.AF_INET NS.Stream 0
connect hostName portID =
  error $ "Connection to " ++ hostName ++ ":" ++ show portID ++ " not supported"

disconnect :: Connection -> IO ()
disconnect Conn{..} = do
  open <- hIsOpen connHandle
  when open (hClose connHandle)

-- |Write the request to the socket output buffer, without actually sending.
--  The 'Handle' is 'hFlush'ed when reading replies from the 'connHandle'.
send :: Connection -> S.ByteString -> IO ()
send Conn{..} s = do
  ioErrorToConnLost (S.hPut connHandle s)
  -- Signal that we expect one more reply from Redis.
  n <- atomicModifyIORef' connPendingCnt $ \n -> let n' = n+1 in (n', n')
  -- Limit the "pipeline length". This is necessary in long pipelines, to avoid
  -- thunk build-up, and thus space-leaks.
  -- TODO find smallest max pending with good-enough performance.
  when (n >= 1000) $ do
    -- Force oldest pending reply.
    r:_ <- readIORef connPending
    r `seq` return ()

-- |Take a reply-thunk from the list of future replies.
recv :: Connection -> IO Reply
recv Conn{..} = do
  (r:rs) <- readIORef connReplies
  writeIORef connReplies rs
  return r

-- | Flush the socket.  Normally, the socket is flushed in 'recv' (actually 'conGetReplies'), but
-- for the multithreaded pub/sub code, the sending thread needs to explicitly flush the subscription
-- change requests.
flush :: Connection -> IO ()
flush Conn{..} = hFlush connHandle

-- |Send a request and receive the corresponding reply
request :: Connection -> S.ByteString -> IO Reply
request conn req = send conn req >> recv conn

-- |A list of all future 'Reply's of the 'Connection'.
--
--  The spine of the list can be evaluated without forcing the replies.
--
--  Evaluating/forcing a 'Reply' from the list will 'unsafeInterleaveIO' the
--  reading and parsing from the 'connHandle'. To ensure correct ordering, each
--  Reply first evaluates (and thus reads from the network) the previous one.
--
--  'unsafeInterleaveIO' only evaluates it's result once, making this function
--  thread-safe. 'Handle' as implemented by GHC is also threadsafe, it is safe
--  to call 'hFlush' here. The list constructor '(:)' must be called from
--  /within/ unsafeInterleaveIO, to keep the replies in correct order.
connGetReplies :: Connection -> IO [Reply]
connGetReplies Conn{..} = go S.empty (SingleLine "previous of first")
  where
    go rest previous = do
      -- lazy pattern match to actually delay the receiving
      ~(r, rest') <- unsafeInterleaveIO $ do
        -- Force previous reply for correct order.
        previous `seq` return ()
        scanResult <- Scanner.scanWith readMore reply rest
        case scanResult of
          Scanner.Fail{}       -> errConnClosed
          Scanner.More{}    -> error "Hedis: parseWith returned Partial"
          Scanner.Done rest' r -> do
            -- r is the same as 'head' of 'connPending'. Since we just
            -- received r, we remove it from the pending list.
            atomicModifyIORef' connPending $ \(_:rs) -> (rs, ())
            -- We now expect one less reply from Redis. We don't count to
            -- negative, which would otherwise occur during pubsub.
            atomicModifyIORef' connPendingCnt $ \n -> (max 0 (n-1), ())
            return (r, rest')
      rs <- unsafeInterleaveIO (go rest' r)
      return (r:rs)

    readMore = ioErrorToConnLost $ do
      hFlush connHandle -- send any pending requests
      S.hGetSome connHandle 4096


ioErrorToConnLost :: IO a -> IO a
ioErrorToConnLost a = a `catchIOError` const errConnClosed

errConnClosed :: IO a
errConnClosed = throwIO ConnectionLost
