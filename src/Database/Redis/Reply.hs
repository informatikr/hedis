{-# LANGUAGE OverloadedStrings #-}
module Database.Redis.Reply (Reply(..), parseReply) where

import Prelude hiding (error, take)
import Control.Applicative
import Data.Attoparsec.Char8
import qualified Data.Attoparsec.Lazy as P
import qualified Data.ByteString.Char8 as S
import qualified Data.ByteString.Lazy.Char8 as L

-- |Low-level representation of replies from the Redis server.
data Reply = SingleLine S.ByteString
           | Error S.ByteString
           | Integer Integer
           | Bulk (Maybe S.ByteString)
           | MultiBulk (Maybe [Reply])
         deriving (Eq, Show)

-- |Parse a lazy 'L.ByteString' into a (possibly infinite) list of 'Reply's.
parseReply :: L.ByteString -> [Reply]
parseReply input =
    case P.parse reply input of
        P.Fail _ _ _  -> []
        P.Done rest r -> r : parseReply rest

------------------------------------------------------------------------------
-- Reply parsers
--
reply :: Parser Reply
reply = choice [singleLine, error, integer, bulk, multiBulk]

singleLine :: Parser Reply
singleLine = SingleLine <$> '+' `prefixing` line

error :: Parser Reply
error = Error <$> '-' `prefixing` line

integer :: Parser Reply
integer = Integer <$> ':' `prefixing` signed decimal

bulk :: Parser Reply
bulk = Bulk <$> do    
    len <- '$' `prefixing` signed decimal
    if len < 0
        then return Nothing
        else Just <$> P.take len <* crlf

multiBulk :: Parser Reply
multiBulk = MultiBulk <$> do
        len <- '*' `prefixing` signed decimal
        if len < 0
            then return Nothing
            else Just <$> count len reply


------------------------------------------------------------------------------
-- Helpers & Combinators
--
prefixing :: Char -> Parser a -> Parser a
c `prefixing` a = char c *> a <* crlf

crlf :: Parser S.ByteString
crlf = string "\r\n"

line :: Parser S.ByteString
line = takeTill (=='\r')
