module FreeVars.FreeTypevars (
  class FreeTypevars,
  freeTypevars,
  freshTypevar,
  generalize) 
where 

import Common (Typevar(..), freshVarN)
import Syntax.Typed.Types (Ty(..))
import Syntax.Typed.Terms (Term(..), Pattern(..), Command(..))

import Prelude ((<$>),(<>),($))
import Data.Set (Set,singleton,unions, difference, fromFoldable,toUnfoldable, union, empty)
import Data.List (List(..),null)

class FreeTypevars a where 
  freeTypevars :: a -> Set Typevar

freshTypevar :: forall a.FreeTypevars a => a -> Typevar 
freshTypevar a = let frV = freeTypevars a in freshVarN 0 "X" Typevar frV

instance FreeTypevars Ty where 
  freeTypevars (TyVar v) = singleton v 
  freeTypevars (TyDecl _ args) = unions (freeTypevars <$> args)
  freeTypevars (TyShift ty) = freeTypevars ty
  freeTypevars (TyCo ty) = freeTypevars ty
  freeTypevars (TyForall args ty) = difference (freeTypevars ty) (fromFoldable args)

instance FreeTypevars Term where 
  freeTypevars (Var _ _ ty) = freeTypevars ty
  freeTypevars (Mu _ _ c ty) = union (freeTypevars c) (freeTypevars ty)
  freeTypevars (Xtor _ _ args ty) = unions (Cons (freeTypevars ty) (freeTypevars <$> args))
  freeTypevars (XCase _ pts ty) = unions (Cons (freeTypevars ty) (freeTypevars <$> pts))
  freeTypevars (ShiftCBV _ t ty) = union (freeTypevars t) (freeTypevars ty)
  freeTypevars (ShiftCBN _ t ty) = union (freeTypevars t) (freeTypevars ty)

instance FreeTypevars Pattern where 
  freeTypevars (Pattern pt) = freeTypevars (pt.ptcmd)

instance FreeTypevars Command where 
  freeTypevars (Cut _ t _ u) = union (freeTypevars t) (freeTypevars u)
  freeTypevars (Done _) = empty
  freeTypevars (Err _ _) = empty
  freeTypevars (Print _ t) = freeTypevars t

generalize :: Ty -> Ty 
generalize (TyForall args ty) = let args' = freeTypevars ty in TyForall (args<>toUnfoldable args') ty
generalize ty = let args = toUnfoldable $ freeTypevars ty in if null args then ty else TyForall args ty
