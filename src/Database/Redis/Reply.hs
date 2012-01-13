{-# LANGUAGE OverloadedStrings #-}
module Database.Redis.Reply (Reply(..), reply) where

import Prelude hiding (error, take)
import Control.Applicative
import Data.Attoparsec.Char8
import qualified Data.Attoparsec as P
import Data.ByteString.Char8

-- |Low-level representation of replies from the Redis server.
data Reply = SingleLine ByteString
           | Error ByteString
           | Integer Integer
           | Bulk (Maybe ByteString)
           | MultiBulk (Maybe [Reply])
         deriving (Eq, Show)

------------------------------------------------------------------------------
-- Reply parsers
--
reply :: Parser Reply
reply = choice [singleLine, integer, bulk, multiBulk, error]

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
            else Just <$> P.count len reply


------------------------------------------------------------------------------
-- Helpers & Combinators
--
prefixing :: Char -> Parser a -> Parser a
c `prefixing` a = char c *> a <* crlf

crlf :: Parser ByteString
crlf = string "\r\n"

line :: Parser ByteString
line = takeTill (=='\r')
