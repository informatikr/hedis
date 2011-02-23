{-# LANGUAGE OverloadedStrings #-}
module Request where

import qualified Data.ByteString.Char8 as S



renderRequest :: [S.ByteString] -> S.ByteString
renderRequest req = S.concat (argCnt:args)
  where
    argCnt = S.concat ["*", showBS (length req), crlf]
    args   = map renderArg req


renderArg :: S.ByteString -> S.ByteString
renderArg arg = S.concat ["$",  argLen arg, crlf, arg, crlf]
  where
    argLen = showBS . S.length


showBS :: (Show a) => a -> S.ByteString
showBS = S.pack . show

crlf :: S.ByteString
crlf = "\r\n"
