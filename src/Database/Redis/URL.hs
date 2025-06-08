{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
module Database.Redis.URL
    ( parseConnectInfo
    ) where

#if __GLASGOW_HASKELL__ < 710
import Control.Applicative ((<$>))
#endif
import Control.Error.Util (note)
import Control.Monad (guard)
#if __GLASGOW_HASKELL__ < 808
import Data.Monoid ((<>))
#endif
import Database.Redis.Connection (ConnectInfo(..), defaultConnectInfo)
import qualified Database.Redis.ConnectionContext as CC
import Network.HTTP.Base
import Network.URI (parseURI, uriPath, uriScheme)
import Network.TLS (defaultParamsClient)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Text.Read (readMaybe)

import qualified Data.ByteString.Char8 as C8

-- | Parse a @'ConnectInfo'@ from a URL
--
-- Username is ignored, path is used to specify the database:
--
-- >>> parseConnectInfo "redis://username:password@host:42/2"
-- Right (ConnInfo {connectHost = "host", connectPort = PortNumber 42, connectAuth = Just "password", connectUsername = Just "username", connectDatabase = 2, connectMaxConnections = 50, connectMaxIdleTime = 30s, connectTimeout = Nothing, connectTLSParams = Nothing})
--
-- >>> parseConnectInfo "redis://username:password@host:42/db"
-- Left "Invalid port: db"
--
-- The scheme is validated, to prevent mixing up configurations:
--
-- >>> parseConnectInfo "postgres://"
-- Left "Wrong scheme"
--
-- Beyond that, all values are optional. Omitted values are taken from
-- @'defaultConnectInfo'@:
--
-- >>> parseConnectInfo "redis://"
-- Right (ConnInfo {connectHost = "localhost", connectPort = PortNumber 6379, connectAuth = Nothing, connectUsername = Nothing, connectDatabase = 0, connectMaxConnections = 50, connectMaxIdleTime = 30s, connectTimeout = Nothing, connectTLSParams = Nothing})
--
parseConnectInfo :: String -> Either String ConnectInfo
parseConnectInfo url = do
    uri <- note "Invalid URI" $ parseURI url
    let userScheme = uriScheme uri
    note ("Wrong scheme " ++ userScheme) $ guard $ userScheme == "redis:" || userScheme == tlsScheme
    uriAuth <- note "Missing or invalid Authority"
        $ parseURIAuthority
        $ uriToAuthorityString uri

    let h = host uriAuth
        dbNumPart = dropWhile (== '/') (uriPath uri)

    db <- if null dbNumPart
      then return $ connectDatabase defaultConnectInfo
      else note ("Invalid port: " <> dbNumPart) $ readMaybe dbNumPart

    let finalHost = if null h
            then connectHost defaultConnectInfo
            else h

    return defaultConnectInfo
        { connectHost = finalHost
        , connectPort = maybe (connectPort defaultConnectInfo) (CC.PortNumber . fromIntegral) (port uriAuth)
        , connectAuth = C8.pack <$> password uriAuth
        , connectUsername = toNothingOnEmpty $ T.encodeUtf8 . T.pack <$> user uriAuth
        , connectDatabase = db
        , connectTLSParams = case userScheme == tlsScheme of
             False -> Nothing
             True -> Just $ defaultParamsClient finalHost ""
        }
    where toNothingOnEmpty :: Maybe C8.ByteString -> Maybe C8.ByteString
          toNothingOnEmpty (Just "") = Nothing
          toNothingOnEmpty a = a
          tlsScheme = "rediss:"
