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
  , requestPipelined
  , nodes
) where

import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as Char8
import qualified Data.IORef as IOR
import Data.Maybe(mapMaybe, fromMaybe)
import Data.List(nub, sortBy, find)
import Data.Map(fromListWith, assocs)
import Data.Function(on)
import Control.Exception(Exception, throwIO, BlockedIndefinitelyOnMVar(..), catches, Handler(..))
import Control.Concurrent.MVar(MVar, newMVar, readMVar, modifyMVar, modifyMVar_)
import Control.Monad(zipWithM, when, replicateM)
import Database.Redis.Cluster.HashSlot(HashSlot, keyToSlot)
import qualified Database.Redis.ConnectionContext as CC
import qualified Data.HashMap.Strict as HM
import qualified Data.IntMap.Strict as IntMap
import           Data.Typeable
import qualified Scanner
import System.IO.Unsafe(unsafeInterleaveIO)
import Say(sayString)

import Database.Redis.Protocol(Reply(Error), renderRequest, reply)
import qualified Database.Redis.Cluster.Command as CMD

-- This module implements a clustered connection whilst maintaining
-- compatibility with the original Hedis codebase. In particular it still
-- performs implicit pipelining using `unsafeInterleaveIO` as the single node
-- codebase does. To achieve this each connection carries around with it a
-- pipeline of commands. Every time `sendRequest` is called the command is
-- added to the pipeline and an IO action is returned which will, upon being
-- evaluated, execute the entire pipeline. If the pipeline is already executed
-- then it just looks up it's response in the executed pipeline.

-- | A connection to a redis cluster, it is compoesed of a map from Node IDs to
-- | 'NodeConnection's, a 'Pipeline', and a 'ShardMap'
data Connection = Connection (HM.HashMap NodeID NodeConnection) (MVar Pipeline) (MVar ShardMap) CMD.InfoMap

-- | A connection to a single node in the cluster, similar to 'ProtocolPipelining.Connection'
data NodeConnection = NodeConnection CC.ConnectionContext (IOR.IORef (Maybe B.ByteString)) NodeID

instance Eq NodeConnection where
    (NodeConnection _ _ id1) == (NodeConnection _ _ id2) = id1 == id2

instance Ord NodeConnection where
    compare (NodeConnection _ _ id1) (NodeConnection _ _ id2) = compare id1 id2

data PipelineState =
      -- Nothing in the pipeline has been evaluated yet so nothing has been
      -- sent
      Pending [[B.ByteString]]
      -- This pipeline has been executed, the replies are contained within it
    | Executed [Reply]
-- A pipeline has an MVar for the current state, this state is actually always
-- `Pending` because the first thing the implementation does when executing a
-- pipeline is to take the current pipeline state out of the MVar and replace
-- it with a new `Pending` state. The executed state is held on to by the
-- replies within it.

newtype Pipeline = Pipeline (MVar PipelineState)

data NodeRole = Master | Slave deriving (Show, Eq, Ord)

type Host = String
type Port = Int
type NodeID = B.ByteString
data Node = Node NodeID NodeRole Host Port deriving (Show, Eq, Ord)

type MasterNode = Node
type SlaveNode = Node
data Shard = Shard MasterNode [SlaveNode] deriving (Show, Eq, Ord)

newtype ShardMap = ShardMap (IntMap.IntMap Shard) deriving (Show)

newtype MissingNodeException = MissingNodeException [B.ByteString] deriving (Show, Typeable)
instance Exception MissingNodeException

newtype UnsupportedClusterCommandException = UnsupportedClusterCommandException [B.ByteString] deriving (Show, Typeable)
instance Exception UnsupportedClusterCommandException

newtype CrossSlotException = CrossSlotException [B.ByteString] deriving (Show, Typeable)
instance Exception CrossSlotException


connect :: [CMD.CommandInfo] -> MVar ShardMap -> Maybe Int -> IO Connection
connect commandInfos shardMapVar timeoutOpt = do
        shardMap <- readMVar shardMapVar
        stateVar <- newMVar $ Pending []
        pipelineVar <- newMVar $ Pipeline stateVar
        nodeConns <- nodeConnections shardMap
        return $ Connection nodeConns pipelineVar shardMapVar (CMD.newInfoMap commandInfos) where
    nodeConnections :: ShardMap -> IO (HM.HashMap NodeID NodeConnection)
    nodeConnections shardMap = HM.fromList <$> mapM connectNode (nub $ nodes shardMap)
    connectNode :: Node -> IO (NodeID, NodeConnection)
    connectNode (Node n _ host port) = do
        ctx <- CC.connect host (CC.PortNumber $ toEnum port) timeoutOpt
        ref <- IOR.newIORef Nothing
        return (n, NodeConnection ctx ref n)

disconnect :: Connection -> IO ()
disconnect (Connection nodeConnMap _ _ _) = mapM_ disconnectNode (HM.elems nodeConnMap) where
    disconnectNode (NodeConnection nodeCtx _ _) = CC.disconnect nodeCtx

-- Add a request to the current pipeline for this connection. The pipeline will
-- be executed implicitly as soon as any result returned from this function is
-- evaluated.
requestPipelined :: IO ShardMap -> Connection -> [B.ByteString] -> IO Reply
requestPipelined refreshAction conn@(Connection _ pipelineVar shardMapVar _) nextRequest = modifyMVar pipelineVar $ \(Pipeline stateVar) -> do
    (newStateVar, repliesIndex) <- hasLocked "locked adding to pipeline" $ modifyMVar stateVar $ \case
        Pending requests | length requests > 1000 -> do
            replies <- evaluatePipeline shardMapVar refreshAction conn (nextRequest:requests)
            return (Executed replies, (stateVar, length requests))
        Pending requests ->
            return (Pending (nextRequest:requests), (stateVar, length requests))
        e@(Executed _) -> do
            s' <- newMVar $ Pending [nextRequest]
            return (e, (s', 0))
    evaluateAction <- unsafeInterleaveIO $ do
        replies <- hasLocked "locked evaluating replies" $ modifyMVar newStateVar $ \case
            Executed replies ->
                return (Executed replies, replies)
            Pending requests-> do
                replies <- evaluatePipeline shardMapVar refreshAction conn requests
                return (Executed replies, replies)
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

-- The approach we take here is similar to that taken by the redis-py-cluster
-- library, which is described at https://redis-py-cluster.readthedocs.io/en/master/pipelines.html
--
-- Essentially we group all the commands by node (based on the current shardmap)
-- and then execute a pipeline for each node (maintaining the order of commands
-- on a per node basis but not between nodes). Once we've done this, if any of
-- the commands have resulted in a MOVED error we refresh the shard map, then
-- we run through all the responses and retry any MOVED or ASK errors. This retry
-- step is not pipelined, there is a request per error. This is probably
-- acceptable in most cases as these errors should only occur in the case of
-- cluster reconfiguration events, which should be rare.
evaluatePipeline :: MVar ShardMap -> IO ShardMap -> Connection -> [[B.ByteString]] -> IO [Reply]
evaluatePipeline shardMapVar refreshShardmapAction conn requests = do
        shardMap <- hasLocked "reading shardmap in evaluatePipeline" $ readMVar shardMapVar
        requestsByNode <- getRequestsByNode shardMap
        resps <- concat <$> mapM (uncurry executeRequests) requestsByNode
        when (any (moved . rawResponse) resps) (refreshShardMapVar "locked refreshing due to moved responses")
        retriedResps <- mapM (retry 0) resps
        return $ map rawResponse $ sortBy (on compare responseIndex) retriedResps
  where
    getRequestsByNode :: ShardMap -> IO [(NodeConnection, [PendingRequest])]
    getRequestsByNode shardMap = do
        commandsWithNodes <- zipWithM (requestWithNode shardMap) (reverse [0..(length requests - 1)]) requests
        return $ assocs $ fromListWith (++) commandsWithNodes
    requestWithNode :: ShardMap -> Int -> [B.ByteString] -> IO (NodeConnection, [PendingRequest])
    requestWithNode shardMap index request = do
        nodeConn <- nodeConnectionForCommand conn shardMap request
        return (nodeConn, [PendingRequest index request])
    executeRequests :: NodeConnection -> [PendingRequest] -> IO [CompletedRequest]
    executeRequests nodeConn nodeRequests = do
        replies <- requestNode nodeConn $ map rawRequest nodeRequests
        return $ zipWith (curry (\(PendingRequest i r, rep) -> CompletedRequest i r rep)) nodeRequests replies
    retry :: Int -> CompletedRequest -> IO CompletedRequest
    retry retryCount resp@(CompletedRequest index request thisReply) = do
        retryReply <- case thisReply of
            (Error errString) | B.isPrefixOf "MOVED" errString -> do
                shardMap <- hasLocked "reading shard map in retry MOVED" $ readMVar shardMapVar
                nodeConn <- nodeConnectionForCommand conn shardMap (requestForResponse resp)
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
nodeConnWithHostAndPort shardMap (Connection nodeConns _ _ _) host port = do
    node <- nodeWithHostAndPort shardMap host port
    HM.lookup (nodeId node) nodeConns

nodeConnectionForCommand :: Connection -> ShardMap -> [B.ByteString] -> IO NodeConnection
nodeConnectionForCommand (Connection nodeConns _ _ infoMap) (ShardMap shardMap) request = do
    let mek = case request of
          ("MULTI" : key : _) -> Just [key]
          ("EXEC" : key : _) -> Just [key]
          _ -> Nothing
    keys <- case CMD.keysForRequest infoMap request of
        Nothing -> throwIO $ UnsupportedClusterCommandException request
        Just k -> return k
    let shards = nub $ mapMaybe (flip IntMap.lookup shardMap . fromEnum . keyToSlot) (fromMaybe keys mek)
    node <- case shards of
        [] -> throwIO $ MissingNodeException request
        [Shard master _] -> return master
        _ -> throwIO $ CrossSlotException request
    maybe (throwIO $ MissingNodeException request) return (HM.lookup (nodeId node) nodeConns)

cleanRequest :: [B.ByteString] -> [B.ByteString]
cleanRequest ("MULTI" : _) = ["MULTI"]
cleanRequest ("EXEC" : _) = ["EXEC"]
cleanRequest req = req


requestNode :: NodeConnection -> [[B.ByteString]] -> IO [Reply]
requestNode (NodeConnection ctx lastRecvRef _) requests = do
    let reqs = map cleanRequest requests
    mapM_ (sendNode . renderRequest) reqs
    _ <- CC.flush ctx
    replicateM (length requests) recvNode

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
nodeWithHostAndPort shardMap host port = find (\(Node _ _ nodeHost nodePort) -> port == nodePort && host == nodeHost) (nodes shardMap)

nodeId :: Node -> NodeID
nodeId (Node theId _ _ _) = theId

hasLocked :: String -> IO a -> IO a
hasLocked msg action =
  action `catches`
  [ Handler $ \exc@BlockedIndefinitelyOnMVar -> sayString ("[MVar]: " ++ msg) >> throwIO exc
  ]
