{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
module Database.Redis.Cluster
  ( Connection(..)
  , NodeRole(..)
  , Node(..)
  , ShardMap(..)
  , HashSlot
  , Shard(..)
  , connect
  , request
  , nodes
) where

import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as Char8
import qualified Data.IORef as IOR
import Data.Maybe(listToMaybe)
import Control.Exception(Exception, throwIO)
import Database.Redis.Cluster.HashSlot(HashSlot, keyToSlot)
import qualified Database.Redis.ConnectionContext as CC
import qualified Data.IntMap.Strict as IntMap
import           Data.Typeable
import qualified Network.Socket as NS
import qualified Scanner

import Database.Redis.Protocol(Reply(Error), renderRequest, reply)


data Connection = Connection
    { ctx :: CC.ConnectionContext
    , lastRecvRef :: IOR.IORef (Maybe B.ByteString) }

instance Show Connection where
    show Connection{..} = "Connection{ ctx = " <> show ctx <> ", lastRecvRef = IORef}"

data NodeRole = Master | Slave deriving (Show)

type Host = String
type Port = Int
type NodeID = B.ByteString
data Node = Node NodeID NodeRole Connection Host Port deriving (Show)

type MasterNode = Node
type SlaveNode = Node
data Shard = Shard MasterNode [SlaveNode] deriving Show

newtype ShardMap = ShardMap (IntMap.IntMap Shard) deriving (Show)

newtype MissingNodeException = MissingNodeException [B.ByteString] deriving (Show, Typeable)

instance Exception MissingNodeException

connect :: NS.HostName -> NS.PortNumber -> Maybe Int -> IO Connection
connect hostName portNumber timeoutOpt = do
    ctx <- CC.connect hostName (CC.PortNumber portNumber) timeoutOpt
    lastRecvRef <- IOR.newIORef Nothing
    return Connection{..}


request :: IOR.IORef ShardMap -> (() -> IO ShardMap) -> [B.ByteString] -> IO Reply
request shardMapRef refreshShardMap requestData = do
    shardMap <- IOR.readIORef shardMapRef
    let maybeNode = nodeForCommand shardMap requestData
    case maybeNode of
        Nothing -> throwIO $ MissingNodeException requestData
        Just node -> do
            resp <- requestNode node (renderRequest requestData)
            case resp of
                (Error errString) | B.isPrefixOf "MOVED" errString -> do
                    newShardMap <- refreshShardMap ()
                    IOR.writeIORef shardMapRef newShardMap
                    request shardMapRef refreshShardMap requestData
                (askingRedirection -> Just (host, port)) -> do
                    let maybeAskNode = nodeWithHostAndPort shardMap host port
                    case maybeAskNode of
                        Just askNode -> do
                            _ <- requestNode askNode (renderRequest ["ASKING"])
                            requestNode askNode (renderRequest requestData)
                        Nothing -> do
                            newShardMap <- refreshShardMap ()
                            IOR.writeIORef shardMapRef newShardMap
                            request shardMapRef refreshShardMap requestData
                _ -> return resp

askingRedirection :: Reply -> Maybe (Host, Port)
askingRedirection (Error errString) = case Char8.words errString of
    ["ASK", _, hostport] -> case Char8.split ':' hostport of
       [host, portString] -> case Char8.readInt portString of
         Just (port,"") -> Just (Char8.unpack host, port)
         _ -> Nothing
       _ -> Nothing
    _ -> Nothing
askingRedirection _ = Nothing


nodeForCommand :: ShardMap -> [B.ByteString] -> Maybe Node
nodeForCommand (ShardMap shards) (_:key:_) = do
    (Shard master _) <- IntMap.lookup (fromEnum $ keyToSlot key) shards
    Just master
nodeForCommand _ _ = Nothing

requestNode :: Node -> B.ByteString -> IO Reply
requestNode (Node _ _ Connection{..} _ _) requestData = do
    _ <- CC.send ctx requestData >> CC.flush ctx
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
nodeWithHostAndPort shardMap host port = listToMaybe $ filter (\(Node _ _ _ nodeHost nodePort) -> port == nodePort && host == nodeHost) $ nodes shardMap
