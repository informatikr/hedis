{-# LANGUAGE OverloadedStrings #-}
module Database.Redis.CommandTemplates (
    ReturnType,
    status,
    bool,
    int,
    list,
    set,
    hash,
    cmd,
    cmdVar
) where

import Control.Monad
import Data.Char
import Data.Maybe
import Language.Haskell.TH
import Language.Haskell.TH.Lib


------------------------------------------------------------------------------
-- Public interface
--

newtype ReturnType = Typ String

status, bool, int, list, hash, set :: ReturnType
status = Typ "Status"
bool   = Typ "Bool"
int    = Typ "Int"
list   = Typ "List"
hash   = Typ "Hash"
set    = Typ "Set"

cmd :: ReturnType -> String -> String -> Q [Dec]
cmd typ name args = defCmd typ name args Nothing

cmdVar :: ReturnType -> String -> String -> String -> Q [Dec]
cmdVar typ name args varArgs = defCmd typ name args (Just varArgs)


------------------------------------------------------------------------------
-- Command template
--
defCmd :: ReturnType -> String -> String -> Maybe String -> Q [Dec]
defCmd (Typ typ) name args varArgs =
    forM [sig, fun] $ \dec -> dec typ name (words args) varArgs
    
sig :: String -> String -> [String] -> Maybe String -> DecQ
sig typ name args varArgs = sigD (mkName name) $
    forallT [plainTV (mkName "a")] (redisTypeClass typ) $
        appArrowsT (argsT ++ varArgT ++ returnT)
  where
    argsT   = replicate (length args) byteStringT
    varArgT = maybe [] (const [listT `appT` byteStringT]) varArgs
    returnT = [nameT "Redis" `appT` (nameT "Maybe" `appT` (nameT "a"))]


fun :: String -> String -> [String] -> Maybe String -> DecQ
fun typ name args varArgs =
    funD (mkName name) [clause funArgs (normalB funBody) []]
  where
    funArgs  = map nameP args ++ maybeToList (fmap nameP varArgs)
    funBody  = resultMapper typ (sendReq argList)
    sendReq  = appE (nameE "sendRequest")
    argList  = maybe argList'
                (infixApp argList' (nameE "++") . nameE)
                varArgs
    argList' = listE $ (cmdE name) : (map nameE args)    


------------------------------------------------------------------------------
-- Helpers
--
appArrowsT :: [TypeQ] -> TypeQ
appArrowsT = foldr1 $ appT . appT arrowT

resultMapper :: String -> ExpQ -> ExpQ
resultMapper typ = infixApp (nameE $ "decode" ++ typ) (nameE "<$>")

redisTypeClass :: String -> Q [Pred]
redisTypeClass typ = sequence [classP (mkName $ "Redis" ++ typ) [nameT "a"]]

nameP :: String -> PatQ
nameP = varP . mkName

nameE :: String -> ExpQ
nameE = varE . mkName

cmdE :: String -> ExpQ
cmdE = litE . stringL . map toUpper

nameT :: String -> TypeQ
nameT = f `ap` mkName
  where
    f "" = error "type-name must not be empty"
    f (c:_) | isUpper c = conT
            | otherwise = varT

byteStringT :: TypeQ
byteStringT = nameT "ByteString"
