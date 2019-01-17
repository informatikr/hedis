{-# LANGUAGE RecordWildCards, DeriveDataTypeable, OverloadedStrings, LambdaCase #-}

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
  connect, enableTLS, beginReceiving, disconnect, request, send, recv, flush,
  ConnectionLostException(..),
  NS.HostName, NS.PortNumber
) where

import           Prelude
import           Control.Concurrent (threadDelay)
import           Control.Concurrent.Async (race)
import           Control.Concurrent.MVar
import           Control.Exception
import           Control.Monad
import qualified Scanner
import qualified Data.ByteString as S
import qualified Data.ByteString.Lazy as L
import           Data.IORef
import           Data.Typeable
import qualified Network.Socket as NS
import qualified Network.TLS as TLS
import           System.IO
import           System.IO.Error
import           System.IO.Unsafe

import           Database.Redis.Protocol

data ConnectionContext = NormalHandle Handle | TLSContext TLS.Context

data Connection = Conn
  { connCtx        :: ConnectionContext -- ^ Connection socket-handle.
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

data ConnectPhase
  = PhaseUnknown
  | PhaseResolve
  | PhaseOpenSocket
  deriving (Show)

data ConnectTimeout = ConnectTimeout ConnectPhase
  deriving (Show, Typeable)

instance Exception ConnectTimeout

data ConnectHostNotFound = ConnectHostNotFound NS.HostName
  deriving (Show, Typeable)

instance Exception ConnectHostNotFound

connect :: NS.HostName -> NS.PortNumber -> Maybe Int -> IO Connection
connect hostName portNum timeoutOpt =
  bracketOnError hConnect hClose $ \h -> do
    hSetBinaryMode h True
    connReplies <- newIORef []
    connPending <- newIORef []
    connPendingCnt <- newIORef 0
    let connCtx = NormalHandle h
    return Conn{..}
  where
        hConnect = do
          phaseMVar <- newMVar PhaseUnknown
          let doConnect = hConnect' portNum phaseMVar
          case timeoutOpt of
            Nothing -> doConnect
            Just micros -> do
              result <- race doConnect (threadDelay micros)
              case result of
                Left h -> return h
                Right () -> do
                  phase <- readMVar phaseMVar
                  errConnectTimeout phase
        hConnect' port mvar =
          bracketOnError mkSocket NS.close $ \sock -> do
            NS.setSocketOption sock NS.KeepAlive 1
            void $ swapMVar mvar PhaseResolve
            hostAddrInfos <- NS.getAddrInfo Nothing (Just hostName) Nothing
            let getAddr = \ case
                  [] -> throwIO $ ConnectHostNotFound hostName
                  x:xs -> case NS.addrAddress x of
                    NS.SockAddrInet _ addr -> pure addr
                    _ -> getAddr xs
            hostAddr <- getAddr hostAddrInfos
            void $ swapMVar mvar PhaseOpenSocket
            NS.connect sock $ NS.SockAddrInet port hostAddr
            NS.socketToHandle sock ReadWriteMode
        mkSocket   = NS.socket NS.AF_INET NS.Stream 0

enableTLS :: TLS.ClientParams -> Connection -> IO Connection
enableTLS tlsParams conn@Conn{..} = do
  case connCtx of
    NormalHandle h -> do
      ctx <- TLS.contextNew h tlsParams
      TLS.handshake ctx
      return $ conn { connCtx = TLSContext ctx }
    TLSContext _ -> return conn

beginReceiving :: Connection -> IO ()
beginReceiving conn = do
  rs <- connGetReplies conn
  writeIORef (connReplies conn) rs
  writeIORef (connPending conn) rs

disconnect :: Connection -> IO ()
disconnect Conn{..} = do
  case connCtx of
    NormalHandle h -> do
      open <- hIsOpen h
      when open $ hClose h
    TLSContext ctx -> do
      TLS.bye ctx
      TLS.contextClose ctx

-- |Write the request to the socket output buffer, without actually sending.
--  The 'Handle' is 'hFlush'ed when reading replies from the 'connCtx'.
send :: Connection -> S.ByteString -> IO ()
send Conn{..} s = do
  case connCtx of
    NormalHandle h ->
      ioErrorToConnLost $ S.hPut h s

    TLSContext ctx ->
      ioErrorToConnLost $ TLS.sendData ctx (L.fromStrict s)

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
flush Conn{..} =
  case connCtx of
    NormalHandle h -> hFlush h
    TLSContext ctx -> TLS.contextFlush ctx

-- |Send a request and receive the corresponding reply
request :: Connection -> S.ByteString -> IO Reply
request conn req = send conn req >> recv conn

-- |A list of all future 'Reply's of the 'Connection'.
--
--  The spine of the list can be evaluated without forcing the replies.
--
--  Evaluating/forcing a 'Reply' from the list will 'unsafeInterleaveIO' the
--  reading and parsing from the 'connCtx'. To ensure correct ordering, each
--  Reply first evaluates (and thus reads from the network) the previous one.
--
--  'unsafeInterleaveIO' only evaluates it's result once, making this function
--  thread-safe. 'Handle' as implemented by GHC is also threadsafe, it is safe
--  to call 'hFlush' here. The list constructor '(:)' must be called from
--  /within/ unsafeInterleaveIO, to keep the replies in correct order.
connGetReplies :: Connection -> IO [Reply]
connGetReplies conn@Conn{..} = go S.empty (SingleLine "previous of first")
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
      flush conn
      case connCtx of
        NormalHandle h -> S.hGetSome h 4096
        TLSContext ctx -> TLS.recvData ctx

ioErrorToConnLost :: IO a -> IO a
ioErrorToConnLost a = a `catchIOError` const errConnClosed

errConnClosed :: IO a
errConnClosed = throwIO ConnectionLost

errConnectTimeout :: ConnectPhase -> IO a
errConnectTimeout phase = throwIO $ ConnectTimeout phase
