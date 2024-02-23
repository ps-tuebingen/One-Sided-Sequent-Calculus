module Pretty.Types where 

import Syntax.Parsed.Program qualified as P
import Syntax.Desugared.Types qualified as D
import Syntax.Typed.Types qualified as T
import Embed.Definition
import Embed.EmbedDesugared ()
import Pretty.Common ()

import Data.List (intercalate)

instance Show P.Ty where 
  show (P.TyVar v) = v 
  show (P.TyDecl nm []) = nm
  show (P.TyDecl nm args) = nm <> "(" <> intercalate ", " (show <$> args) <> ")"
instance Show D.Ty where 
  show = show . (embed :: D.Ty -> P.Ty)

instance Show T.Ty where 
  show (T.TyVar v ) = v 
  show (T.TyDecl nm []) = nm
  show (T.TyDecl nm args) = nm <> "(" <> intercalate ", " (show <$> args) <> ")"
  show (T.TyShift ty) = "{" <> show ty <> "}" 
  show (T.TyCo ty) = "co " <> show ty

instance Show T.TypeScheme where 
  show (T.MkTypeScheme [] ty) = show ty
  show (T.MkTypeScheme vars ty) = "forall " <> intercalate "," vars <> ". " <> show ty
