module Syntax.Desugared.Types where 

import Common 


data Ty = 
  TyVar !TypeVar
  | TyDecl !TypeName ![Ty] 
  | TyForall ![TypeVar] !Ty
  deriving (Eq)
