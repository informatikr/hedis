{-# LANGUAGE OverloadedStrings, RecordWildCards #-}
module Database.Redis.Cluster.Command where

import Data.Char(toLower)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as Char8
import qualified Data.HashMap.Strict as HM
import Database.Redis.Types(RedisResult(decode))
import Database.Redis.Protocol(Reply(..))

data Flag
    = Write
    | ReadOnly
    | DenyOOM
    | Admin
    | PubSub
    | NoScript
    | Random
    | SortForScript
    | Loading
    | Stale
    | SkipMonitor
    | Asking
    | Fast
    | MovableKeys
    | Other BS.ByteString deriving (Show, Eq)


data AritySpec = Required Integer | MinimumRequired Integer deriving (Show)

data LastKeyPositionSpec = LastKeyPosition Integer | UnlimitedKeys deriving (Show)

newtype InfoMap = InfoMap (HM.HashMap String CommandInfo)

-- Represents the result of the COMMAND command, which returns information
-- about the position of keys in a request
data CommandInfo = CommandInfo
    { name :: BS.ByteString
    , arity :: AritySpec
    , flags :: [Flag]
    , firstKeyPosition :: Integer
    , lastKeyPosition :: LastKeyPositionSpec
    , stepCount :: Integer
    } deriving (Show)

instance RedisResult CommandInfo where
    decode (MultiBulk (Just
        [ Bulk (Just commandName)
        , Integer aritySpec
        , MultiBulk (Just replyFlags)
        , Integer firstKeyPos
        , Integer lastKeyPos
        , Integer replyStepCount])) = do
            parsedFlags <- mapM parseFlag replyFlags
            lastKey <- parseLastKeyPos
            return $ CommandInfo
                { name = commandName
                , arity = parseArity aritySpec
                , flags = parsedFlags
                , firstKeyPosition = firstKeyPos
                , lastKeyPosition = lastKey
                , stepCount = replyStepCount
                } where
        parseArity int = case int of
            i | i >= 0 -> Required i
            i -> MinimumRequired $ abs i
        parseFlag :: Reply -> Either Reply Flag
        parseFlag (SingleLine flag) = return $ case flag of
            "write" -> Write
            "readonly" -> ReadOnly
            "denyoom" -> DenyOOM
            "admin" -> Admin
            "pubsub" -> PubSub
            "noscript" -> NoScript
            "random" -> Random
            "sort_for_script" -> SortForScript
            "loading" -> Loading
            "stale" -> Stale
            "skip_monitor" -> SkipMonitor
            "asking" -> Asking
            "fast" -> Fast
            "movablekeys" -> MovableKeys
            other -> Other other
        parseFlag bad = Left bad
        parseLastKeyPos :: Either Reply LastKeyPositionSpec
        parseLastKeyPos = return $ case lastKeyPos of
            i | i == -1 -> UnlimitedKeys
            i -> LastKeyPosition i

    decode e = Left e

newInfoMap :: [CommandInfo] -> InfoMap
newInfoMap = InfoMap . HM.fromList . map (\c -> (Char8.unpack $ name c, c))

keysForRequest :: InfoMap -> [BS.ByteString] -> Maybe [BS.ByteString]
keysForRequest (InfoMap infoMap) request@(command:_) = do
    info <- HM.lookup (map toLower $ Char8.unpack command) infoMap
    if isMovable info then parseMovable request else do
        let possibleKeys = case lastKeyPosition info of
                LastKeyPosition end -> take (fromEnum $ 1 + end - firstKeyPosition info) $ drop (fromEnum $ firstKeyPosition info) request
                UnlimitedKeys -> drop (fromEnum $ firstKeyPosition info) request
        return $ takeEvery (fromEnum $ stepCount info) possibleKeys
keysForRequest _ [] = Nothing

isMovable :: CommandInfo -> Bool
isMovable CommandInfo{..} = MovableKeys `elem` flags

parseMovable :: [BS.ByteString] -> Maybe [BS.ByteString]
parseMovable ("SORT":key:_) = Just [key]
parseMovable ("EVAL":_:rest) = readNumKeys rest
parseMovable ("EVALSH":_:rest) = readNumKeys rest
parseMovable ("ZUNIONSTORE":_:rest) = readNumKeys rest
parseMovable ("ZINTERSTORE":_:rest) = readNumKeys rest
parseMovable _ = Nothing


readNumKeys :: [BS.ByteString] -> Maybe [BS.ByteString]
readNumKeys (rawNumKeys:rest) = do
    numKeys <- readMaybe (Char8.unpack rawNumKeys)
    return $ take numKeys rest
readNumKeys _ = Nothing

takeEvery :: Int -> [a] -> [a]
takeEvery n xs = case drop (n-1) xs of
      (y:ys) -> y : takeEvery n ys
      [] -> []

readMaybe :: Read a => String -> Maybe a
readMaybe s = case reads s of
                  [(val, "")] -> Just val
                  _           -> Nothing
