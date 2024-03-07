module Pretty.Terms where 

import Syntax.Parsed.Terms qualified as P 
import Syntax.Desugared.Terms qualified as D
import Syntax.Typed.Terms qualified as T 
import Embed.Definition
import Embed.EmbedDesugared () 
import Embed.EmbedTyped () 
import Pretty.Common ()
import Pretty.Types ()

import Data.List (intercalate)

instance Show P.Term where 
  show (P.Var v) = show v
  show (P.Mu v Nothing cmd) = "mu " <> show v <> ". " <> show cmd
  show (P.Mu v (Just pol) cmd) = "mu " <> show v <> " : " <> show pol <> ", " <> show cmd
  show (P.Xtor xt []) = show xt
  show (P.Xtor xt args) = show xt <> "(" <> intercalate ", " (show <$> args) <> ")"
  show (P.XCase pts) = "case {" <>  intercalate ", " (show <$> pts) <> "}"
  show (P.Shift t) = "{" <> show t <> "}"
  show (P.Lam v cmd) = "Lambda {" <> show v <> "}." <> show cmd
instance Show D.Term where 
  show = show . (embed :: D.Term -> P.Term)
instance Show T.Term where 
  show = show . (embed :: T.Term -> P.Term)

instance Show P.Pattern where 
  show (P.MkPattern xt [] cmd) = show xt <> " => " <> show cmd
  show (P.MkPattern xt vars cmd) = show xt <> "(" <> intercalate ", " (show <$> vars) <> ") => " <> show cmd
instance Show D.Pattern where
  show = show . (embed :: D.Pattern -> P.Pattern)
instance Show T.Pattern where 
  show = show . (embed :: T.Pattern -> P.Pattern)
  
instance Show P.Command where 
  show (P.Cut t pol u) = "<" <> show t <> " | " <> show pol <> " | " <> show u <> ">"
  show (P.CutAnnot t ty pol u) = "<" <> show t <> " | " <> show ty <> " | " <> show pol <> " | " <> show u <> ">"
  show P.Done = "Done"
instance Show D.Command where 
  show = show . (embed :: D.Command -> P.Command)
instance Show T.Command where 
  show = show . (embed :: T.Command -> P.Command)
