{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
module Database.Redis.Cluster
  ( Connection(..)
  , NodeRole(..)
  , NodeConnection(..)
  , Node(..)
  , ShardMap(..)
  , HashSlot
  , Shard(..)
  , connect
  , disconnect
  --, request
  , requestPipelined
  , nodes
) where

import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as Char8
import qualified Data.IORef as IOR
import Data.Maybe(listToMaybe)
import Data.List(nub, sortBy)
import Data.Map(fromListWith, assocs)
import Data.Function(on)
import Control.Exception(Exception, throwIO, BlockedIndefinitelyOnMVar(..), catches, Handler(..))
import Control.Concurrent.MVar(MVar, newMVar, readMVar, modifyMVar, modifyMVar_)
import Control.Monad(zipWithM, when)
import Database.Redis.Cluster.HashSlot(HashSlot, keyToSlot)
import qualified Database.Redis.ConnectionContext as CC
import qualified Data.HashMap.Strict as HM
import qualified Data.IntMap.Strict as IntMap
import           Data.Typeable
import qualified Scanner
import System.IO.Unsafe(unsafeInterleaveIO)
import Say(sayString)

import Database.Redis.Protocol(Reply(Error), renderRequest, reply)


data NodeConnection = NodeConnection CC.ConnectionContext (IOR.IORef (Maybe B.ByteString)) NodeID

instance Eq NodeConnection where
    (NodeConnection _ _ id1) == (NodeConnection _ _ id2) = id1 == id2

instance Ord NodeConnection where
    compare (NodeConnection _ _ id1) (NodeConnection _ _ id2) = compare id1 id2

data PipelineState = Pending [[B.ByteString]] | Evaluated [Reply]
newtype Pipeline = Pipeline (MVar PipelineState)
data Connection = Connection (HM.HashMap NodeID NodeConnection) (MVar Pipeline)

data NodeRole = Master | Slave deriving (Show, Eq, Ord)

type Host = String
type Port = Int
type NodeID = B.ByteString
data Node = Node NodeID NodeRole Host Port deriving (Show, Eq, Ord)

type MasterNode = Node
type SlaveNode = Node
data Shard = Shard MasterNode [SlaveNode] deriving Show

newtype ShardMap = ShardMap (IntMap.IntMap Shard) deriving (Show)

newtype MissingNodeException = MissingNodeException [B.ByteString] deriving (Show, Typeable)

instance Exception MissingNodeException


connect :: ShardMap -> Maybe Int -> IO Connection
connect shardMap timeoutOpt = do
        stateVar <- newMVar $ Pending []
        pipelineVar <- newMVar $ Pipeline stateVar
        nodeConns <- nodeConnections
        return $ Connection nodeConns pipelineVar where
    nodeConnections :: IO (HM.HashMap NodeID NodeConnection)
    nodeConnections = HM.fromList <$> mapM connectNode (nub $ nodes shardMap)
    connectNode :: Node -> IO (NodeID, NodeConnection)
    connectNode (Node n _ host port) = do
        ctx <- CC.connect host (CC.PortNumber $ toEnum port) timeoutOpt
        ref <- IOR.newIORef Nothing
        return (n, NodeConnection ctx ref n)

disconnect :: Connection -> IO ()
disconnect (Connection nodeConnMap _) = mapM_ disconnectNode (HM.elems nodeConnMap) where
    disconnectNode (NodeConnection nodeCtx _ _) = CC.disconnect nodeCtx


requestPipelined :: MVar ShardMap -> IO ShardMap -> Connection -> [B.ByteString] -> IO Reply
requestPipelined shardMapVar refreshAction conn@(Connection _ pipelineVar) nextRequest = modifyMVar pipelineVar $ \(Pipeline stateVar) -> do
    (newStateVar, repliesIndex) <- hasLocked "locked adding to pipeline" $ modifyMVar stateVar $ \case
        Pending requests -> return (Pending (nextRequest:requests), (stateVar, length requests))
        e@(Evaluated _) -> do
            s' <- newMVar $ Pending [nextRequest]
            return (e, (s', 0))
    evaluateAction <- unsafeInterleaveIO $ do
        replies <- hasLocked "locked evaluating replies" $ modifyMVar newStateVar $ \case
            Evaluated replies -> return (Evaluated replies, replies)
            Pending requests-> do
                replies <- evaluatePipeline shardMapVar refreshAction conn requests
                return (Evaluated replies, replies)
        return $ replies !! repliesIndex
    return (Pipeline newStateVar, evaluateAction)



data PendingRequest = PendingRequest Int [B.ByteString]
data CompletedRequest = CompletedRequest Int [B.ByteString] Reply

rawRequest :: PendingRequest -> [B.ByteString]
rawRequest (PendingRequest _ r) =  r

responseIndex :: CompletedRequest -> Int
responseIndex (CompletedRequest i _ _) = i

rawResponse :: CompletedRequest -> Reply
rawResponse (CompletedRequest _ _ r) = r

requestForResponse :: CompletedRequest -> [B.ByteString]
requestForResponse (CompletedRequest _ r _) = r

evaluatePipeline :: MVar ShardMap -> IO ShardMap -> Connection -> [[B.ByteString]] -> IO [Reply]
evaluatePipeline shardMapVar refreshShardmapAction conn requests = do
        shardMap <- hasLocked "reading shardmap in evaluatePipeline" $ readMVar shardMapVar
        requestsByNode <- getRequestsByNode shardMap
        resps <- concat <$> mapM (uncurry executeRequests) requestsByNode
        _ <- when (any (moved . rawResponse) resps) (refreshShardMapVar "locked refreshing due to moved responses")
        retriedResps <- mapM (retry 0) resps
        return $ map rawResponse $ sortBy (on compare responseIndex) retriedResps where
    getRequestsByNode :: ShardMap -> IO [(NodeConnection, [PendingRequest])]
    getRequestsByNode shardMap = do
        commandsWithNodes <- zipWithM (requestWithNode shardMap) [0..] (reverse requests)
        return $ assocs $ fromListWith (++) commandsWithNodes
    requestWithNode :: ShardMap -> Int -> [B.ByteString] -> IO (NodeConnection, [PendingRequest])
    requestWithNode shardMap index request = do
        nodeConn <- nodeConnectionForCommandOrThrow shardMap conn request
        return (nodeConn, [PendingRequest index request])
    executeRequests :: NodeConnection -> [PendingRequest] -> IO [CompletedRequest]
    executeRequests nodeConn nodeRequests = do
        replies <- requestNode nodeConn $ map rawRequest nodeRequests
        return $ map (\(PendingRequest i r, rep) -> CompletedRequest i r rep) (zip nodeRequests replies)
    retry :: Int -> CompletedRequest -> IO CompletedRequest
    retry retryCount resp@(CompletedRequest index request thisReply) = do
        retryReply <- case thisReply of
            (Error errString) | B.isPrefixOf "MOVED" errString -> do
                shardMap <- hasLocked "reading shard map in retry MOVED" $ readMVar shardMapVar
                nodeConn <- nodeConnectionForCommandOrThrow shardMap conn (requestForResponse resp)
                head <$> requestNode nodeConn [request]
            (askingRedirection -> Just (host, port)) -> do
                shardMap <- hasLocked "reading shardmap in retry ASK" $ readMVar shardMapVar
                let maybeAskNode = nodeConnWithHostAndPort shardMap conn host port
                case maybeAskNode of
                    Just askNode -> last <$> requestNode askNode [["ASKING"], requestForResponse resp]
                    Nothing -> case retryCount of
                        0 -> do
                            _ <- refreshShardMapVar "missing node in first retry of ASK"
                            rawResponse <$> retry (retryCount + 1) resp
                        _ -> throwIO $ MissingNodeException (requestForResponse resp)
            _ -> return thisReply
        return (CompletedRequest index request retryReply)
    refreshShardMapVar :: String -> IO ()
    refreshShardMapVar msg = hasLocked msg $ modifyMVar_ shardMapVar (const refreshShardmapAction)


askingRedirection :: Reply -> Maybe (Host, Port)
askingRedirection (Error errString) = case Char8.words errString of
    ["ASK", _, hostport] -> case Char8.split ':' hostport of
       [host, portString] -> case Char8.readInt portString of
         Just (port,"") -> Just (Char8.unpack host, port)
         _ -> Nothing
       _ -> Nothing
    _ -> Nothing
askingRedirection _ = Nothing

moved :: Reply -> Bool
moved (Error errString) = case Char8.words errString of
    "MOVED":_ -> True
    _ -> False
moved _ = False


nodeConnWithHostAndPort :: ShardMap -> Connection -> Host -> Port -> Maybe NodeConnection
nodeConnWithHostAndPort shardMap (Connection nodeConns _) host port = do
    node <- nodeWithHostAndPort shardMap host port
    HM.lookup (nodeId node) nodeConns

nodeConnectionForCommandOrThrow :: ShardMap -> Connection -> [B.ByteString] -> IO NodeConnection
nodeConnectionForCommandOrThrow shardMap (Connection nodeConns _) command = maybe (throwIO $ MissingNodeException command) return maybeNode where
    maybeNode = do
        node <- nodeForCommand shardMap command
        HM.lookup (nodeId node) nodeConns

nodeForCommand :: ShardMap -> [B.ByteString] -> Maybe Node
nodeForCommand (ShardMap shards) (_:key:_) = do
    (Shard master _) <- IntMap.lookup (fromEnum $ keyToSlot key) shards
    Just master
nodeForCommand _ _ = Nothing


requestNode :: NodeConnection -> [[B.ByteString]] -> IO [Reply]
requestNode (NodeConnection ctx lastRecvRef _) requests = do
    _ <- mapM_ (sendNode . renderRequest) requests
    _ <- CC.flush ctx
    sequence $ take (length requests) (repeat recvNode)

    where

    sendNode :: B.ByteString -> IO ()
    sendNode = CC.send ctx
    recvNode :: IO Reply
    recvNode = do
        maybeLastRecv <- IOR.readIORef lastRecvRef
        scanResult <- case maybeLastRecv of
            Just lastRecv -> Scanner.scanWith (CC.recv ctx) reply lastRecv
            Nothing -> Scanner.scanWith (CC.recv ctx) reply B.empty

        case scanResult of
          Scanner.Fail{}       -> CC.errConnClosed
          Scanner.More{}    -> error "Hedis: parseWith returned Partial"
          Scanner.Done rest' r -> do
            IOR.writeIORef lastRecvRef (Just rest')
            return r

nodes :: ShardMap -> [Node]
nodes (ShardMap shardMap) = concatMap snd $ IntMap.toList $ fmap shardNodes shardMap where
    shardNodes :: Shard -> [Node]
    shardNodes (Shard master slaves) = master:slaves


nodeWithHostAndPort :: ShardMap -> Host -> Port -> Maybe Node
nodeWithHostAndPort shardMap host port = listToMaybe $ filter (\(Node _ _ nodeHost nodePort) -> port == nodePort && host == nodeHost) $ nodes shardMap

nodeId :: Node -> NodeID
nodeId (Node theId _ _ _) = theId

hasLocked :: String -> IO a -> IO a
hasLocked msg action =
  action `catches`
  [ Handler $ \exc@BlockedIndefinitelyOnMVar -> sayString ("[MVar]: " ++ msg) >> throwIO exc
  ]
