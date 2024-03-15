module Syntax.Parsed.Types where 

import Common


data Ty = 
  TyVar !TypeVar 
  | TyDecl !TypeName ![Ty]
  | TyCo !Ty
  | TyShift !Ty
  | TyForall ![TypeVar] !Ty

data PolTy = MkPolTy !Ty !Pol
