{-# LANGUAGE OverloadedStrings #-}
module Database.Redis.Reply (Reply(..), reply) where

import Prelude hiding (error, take)
import Control.Applicative
import Data.Attoparsec (takeTill)
import Data.Attoparsec.Char8 hiding (takeTill)
import Data.ByteString.Char8 (ByteString)

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
singleLine = SingleLine <$> (char '+' *> takeTill isEndOfLine <* endOfLine)

error :: Parser Reply
error = Error <$> (char '-' *> takeTill isEndOfLine <* endOfLine)

integer :: Parser Reply
integer = Integer <$> (char ':' *> signed decimal <* endOfLine)

bulk :: Parser Reply
bulk = Bulk <$> do
    len <- char '$' *> signed decimal <* endOfLine
    if len < 0
        then return Nothing
        else Just <$> take len <* endOfLine

multiBulk :: Parser Reply
multiBulk = MultiBulk <$> do
        len <- char '*' *> signed decimal <* endOfLine
        if len < 0
            then return Nothing
            else Just <$> count len reply
