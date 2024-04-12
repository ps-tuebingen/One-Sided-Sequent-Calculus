module StringFormat where 

import Environment 
import Common
import Syntax.Kinded.Terms
import Pretty.Kinded () 

import Data.List (intercalate)

envToStr :: Environment -> String 
envToStr env = do 
  let tys = getTypes (Modulename "") env
  let tyStrs = (\(nm,ty) -> replStr (show nm) <> "::" <> replStr (show ty)) <$> tys
  intercalate "\n" tyStrs

traceToStr :: [Command] -> String
traceToStr cmds = intercalate "\n" (replStr . show  <$> cmds)

repl :: Char -> String
repl '<' = "&lt;"
repl '+' = "&plus;"
repl '|' = "&vert;"
repl c =  [c]

replStr :: String -> String 
replStr = concatMap repl