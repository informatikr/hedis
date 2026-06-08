{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ViewPatterns #-}
module Database.Redis.URL
    ( parseConnectInfo
    ) where

#if __GLASGOW_HASKELL__ < 710
import Control.Applicative ((<$>))
#endif
import qualified Data.ByteString.Char8 as C8
import Control.Error.Util (note)
#if __GLASGOW_HASKELL__ < 808
import Data.Monoid ((<>))
#endif
import Data.String (fromString)
import Database.Redis.Connection (ConnectInfo(..), defaultConnectInfo)
import qualified Database.Redis.ConnectionContext as CC
import Network.HTTP.Base
import Network.URI (parseURI, uriPath, uriScheme, uriQuery, URI)
import Network.TLS (defaultParamsClient)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Network.HTTP.Types (parseSimpleQuery)
import Text.Read (readMaybe)


-- | Parse a @'ConnectInfo'@ from a URL according to the Rules in Redis client
--
-- Standalone Redis:
--
-- @
-- redis :// [[username :] password@] host [:port][/database]
-- @
--
-- >>> parseConnectInfo "redis://username:password@host:42/2"
-- Right (ConnInfo {connectAddr = ConnectAddrHostPort "host" 42, connectAuth = Just "password", connectUsername = Just "username", connectDatabase = 2, connectMaxConnections = 50, connectNumStripes = Just 1, connectMaxIdleTime = 30s, connectTimeout = Nothing, connectTLSParams = Nothing, connectHooks = Hooks {...}, connectPoolLabel = ""})
--
-- >>> parseConnectInfo "redis://password@host:42/2"
-- Right (ConnInfo {connectAddr = ConnectAddrHostPort "host" 42, connectAuth = Just "password", connectUsername = Nothing, connectDatabase = 2, connectMaxConnections = 50, connectNumStripes = Just 1, connectMaxIdleTime = 30s, connectTimeout = Nothing, connectTLSParams = Nothing, connectHooks = Hooks {...}, connectPoolLabel = ""})
--
-- TLS-enabled Redis:
--
-- @
-- rediss :// [[username :] password@] host [: port][/database]
-- @
--
-- Unix socket Redis:
--
-- @
-- redis-socket :// [[username :] password@]path [? [&database=database]
-- @
--
-- >>> parseConnectInfo "redis-socket://password@/tmp/redis.sock?database=2"
-- Right (ConnInfo {connectAddr = ConnectAddrUnixSocket "/tmp/redis.sock", connectAuth = Just "password", connectUsername = Nothing, connectDatabase = 2, connectMaxConnections = 50, connectNumStripes = Just 1, connectMaxIdleTime = 30s, connectTimeout = Nothing, connectTLSParams = Nothing, connectHooks = Hooks {...}, connectPoolLabel = ""})
--
-- >>> parseConnectInfo "redis://username:password@host:42/db"
-- Left "Invalid port: db"
--
-- The scheme is validated, to prevent mixing up configurations:
--
-- >>> parseConnectInfo "postgres://"
-- Left "Wrong scheme postgres:"
--
-- Beyond that, all values are optional. Omitted values are taken from
-- @'defaultConnectInfo'@:
--
-- >>> parseConnectInfo "rediss://"
-- Right (ConnInfo {connectAddr = ConnectAddrHostPort "localhost" 6379, connectAuth = Nothing, connectUsername = Nothing, connectDatabase = 0, connectMaxConnections = 50, connectNumStripes = Just 1, connectMaxIdleTime = 30s, connectTimeout = Nothing, connectTLSParams = Just (ClientParams ...), connectHooks = Hooks {...}, connectPoolLabel = ""})
--
parseConnectInfo :: String -> Either String ConnectInfo
parseConnectInfo url = do
    uri <- note "Invalid URI" $ parseURI url
    let userScheme = uriScheme uri
    case userScheme of
        "redis:" -> parseSocket False uri
        "rediss:" -> parseSocket True uri
        "redis-socket:" -> parseUnix uri
        x -> Left ("Wrong scheme " ++ x)
    where
        parseSocket :: Bool -> URI -> Either String ConnectInfo
        parseSocket isSecure uri = do
            uriAuth <- note "Missing or invalid Authority"
                $ parseURIAuthority
                $ uriToAuthorityString uri

            let h = host uriAuth
                dbNumPart = dropWhile (== '/') (uriPath uri)

            db <- if null dbNumPart
              then return $ connectDatabase defaultConnectInfo
              else note ("Invalid port: " <> dbNumPart) $ readMaybe dbNumPart

            let finalHost = if null h
                    then case connectAddr defaultConnectInfo of
                      CC.ConnectAddrHostPort defaultHost _ -> defaultHost
                      CC.ConnectAddrUnixSocket _ -> "localhost"
                    else h

            let (finalUser, finalAuth) = case (T.pack <$> user uriAuth, T.pack <$> password uriAuth) of
                    (p, Nothing) -> (Nothing, p)
                    (p, fmap T.strip -> Just "") -> (Nothing, p)
                    (u, p) -> (u, p)

            return defaultConnectInfo
                { connectAddr =
                    CC.ConnectAddrHostPort
                      finalHost
                      (maybe defaultPort fromIntegral (port uriAuth))
                , connectAuth = T.encodeUtf8 <$> finalAuth
                , connectUsername = T.encodeUtf8 <$> finalUser
                , connectDatabase = db
                , connectTLSParams = case isSecure of
                     False -> Nothing
                     True -> Just $ defaultParamsClient finalHost ""
                }
          where
            defaultPort = case connectAddr defaultConnectInfo of
              CC.ConnectAddrHostPort _ portNum -> portNum
              CC.ConnectAddrUnixSocket _ -> 6379

        parseUnix :: URI -> Either String ConnectInfo
        parseUnix uri = do
            auth <- note "Missing or invalid Authority"
                $ parseURIAuthority
                $ uriToAuthorityString uri
            db <- case lookup "database" query of
                    Nothing -> return $ connectDatabase defaultConnectInfo
                    Just dbNumPart ->
                        note "Invalid database" $ readMaybe @Integer . T.unpack $ T.decodeUtf8 dbNumPart
            return defaultConnectInfo
                { connectAddr = CC.ConnectAddrUnixSocket (mkPath auth)
                , connectAuth = C8.pack <$> (user auth)
                , connectDatabase = (db :: Integer)
                }
            where
                mkPath auth =
                    case host auth <> uriPath uri of
                        ('/':_) -> host auth <> uriPath uri
                        _ -> '/' : host auth <> uriPath uri
                query = parseSimpleQuery (T.encodeUtf8 $ fromString $ uriQuery uri)
