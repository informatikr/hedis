module Database.Redis.CommandTemplates (
    cmd,
    bool
) where


import Data.Char
import Language.Haskell.TH
import Language.Haskell.TH.Syntax


------------------------------------------------------------------------------
-- Redis type names
--
bool :: String
bool = "Bool"

------------------------------------------------------------------------------
-- Command templates
--
cmd :: String -> String -> String -> Q [Dec]
cmd name arg returnType = sequenceQ
    [ funD (mkName name)
        [ clause
            [varP $ mkName arg]
            (normalB $ infixApp decode (varE . mkName $ "<$>") sendReq)
            []
        ]
    ]
  where
    decode  = varE . mkName $ "decode" ++ returnType
    sendReq = appE (varE . mkName $ "sendRequest") argList
    argList = listE [ litE . stringL . map toUpper $ name
                    , varE $ mkName arg
                    ]
