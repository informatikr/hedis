{-# LANGUAGE RecordWildCards, DeriveDataTypeable #-}

module Database.Redis.ProtocolPipelining (
    Connection,
    connect, disconnect, request, send, recv,
    ConnectionLostException(..),
    HostName, PortID(..)
) where

import           Prelude hiding (catch)
import           Control.Concurrent
import           Control.Exception
import           Control.Monad
import           Data.Attoparsec
import qualified Data.ByteString as S
import           Data.IORef
import           Data.Typeable
import           Network
import           System.IO
import           System.IO.Unsafe


data Connection a = Conn
    { connHandle     :: Handle
    , connThunks     :: Thunks a
    }

data ConnectionLostException = ConnectionLost
    deriving (Show, Typeable)

instance Exception ConnectionLostException

connect
    :: HostName
    -> PortID
    -> Parser a
    -> IO (Connection a)
connect host port parser = do
    connHandle  <- connectTo host port
    hSetBinaryMode connHandle True
    connThunks  <- newThunks =<< hGetReplies connHandle parser
    return Conn{..}

disconnect :: Connection a -> IO ()
disconnect Conn{..} = do
    open <- hIsOpen connHandle
    when open (hClose connHandle)

-- |Write the request to the socket output buffer.
--
--  The 'Handle' is 'hFlush'ed when reading replies.
send :: Connection a -> S.ByteString -> IO ()
send Conn{..} = S.hPut connHandle

-- |Take a reply from the list of future replies.
--
--  'head' and 'tail' are used to get a thunk of the reply. Pattern matching (:)
--   would block until a reply could be read.
recv :: Connection a -> IO a
recv Conn{..} = nextThunk connThunks

request :: Connection a -> S.ByteString -> IO a
request conn req = send conn req >> recv conn

-- |Read all the replies from the Handle and return them as a lazy list.
--
--  The actual reading and parsing of each 'Reply' is deferred until the spine
--  of the list is evaluated up to that 'Reply'. Each 'Reply' is cons'd in front
--  of the (unevaluated) list of all remaining replies.
--
--  'unsafeInterleaveIO' only evaluates it's result once, making this function 
--  thread-safe. 'Handle' as implemented by GHC is also threadsafe, it is safe
--  to call 'hFlush' here. The list constructor '(:)' must be called from
--  /within/ unsafeInterleaveIO, to keep the replies in correct order.
hGetReplies :: Handle -> Parser a -> IO [a]
hGetReplies h parser = go S.empty
  where
    go rest = unsafeInterleaveIO $ do        
        parseResult <- parseWith readMore parser rest
        case parseResult of
            Fail _ _ _   -> errConnClosed
            Partial _    -> error "Hedis: parseWith returned Partial"
            Done rest' r -> do
                rs <- go rest'
                return (r:rs)

    readMore = do
        hFlush h -- send any pending requests
        S.hGetSome h maxRead `catchIOError` const errConnClosed

    maxRead       = 4*1024
    errConnClosed = throwIO ConnectionLost

    catchIOError :: IO a -> (IOError -> IO a) -> IO a
    catchIOError = catch


data Thunks a = Thunks
    { thunksThunks     :: IORef [a]
    , thunksCnt        :: IORef Int
    , thunksStartEval  :: MVar a
    , thunksEvaluating :: MVar ()
    , thunksEvalTId    :: ThreadId
    }

newThunks :: [a] -> IO (Thunks a)
newThunks xs = do
    thunksThunks     <- newIORef xs
    thunksCnt        <- newIORef 0
    thunksStartEval  <- newEmptyMVar
    thunksEvaluating <- newEmptyMVar
    thunksEvalTId    <- forkIO $ forever $ do
        -- We must wait for a reply to become available. Otherwise we will
        -- flush the output buffer (in hGetReplies) before a command is written
        -- by the user thread, creating a deadlock.
        t <- takeMVar thunksStartEval
        putMVar thunksEvaluating ()
        t `seq` return ()
    
    return Thunks{..}

nextThunk :: Thunks a -> IO a
nextThunk Thunks{..} = do    
    ts <- readIORef thunksThunks
    writeIORef thunksThunks (tail ts)
    let t = head ts
    
    cnt <- readIORef thunksCnt
    if cnt == 256
        then do
            putMVar thunksStartEval t
            takeMVar thunksEvaluating
            writeIORef thunksCnt 0
        else writeIORef thunksCnt (cnt+1)
    return t
    
