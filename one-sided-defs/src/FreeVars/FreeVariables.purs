module FreeVars.FreeVariables (
  class FreeVariables,
  freeVars,
  freshVar
  ) where

import Common (Variable(..),freshVarN) 
import Syntax.Kinded.Terms (Term(..),Pattern(..),Command(..))     as K
import Syntax.Desugared.Terms (Term(..),Pattern(..),Command(..))  as D
import Syntax.Parsed.Terms (Term(..),Pattern(..),Command(..))     as P

import Prelude ((<$>))
import Data.List (List,foldr)
import Data.Set (Set,unions,singleton,delete,union,empty)

class FreeVariables a where 
  freeVars :: a -> Set Variable 

instance FreeVariables a => FreeVariables (List a) where 
  freeVars ls = unions (freeVars <$> ls)

freshVar :: forall a.FreeVariables a => a -> Variable
freshVar a = let frV = freeVars a in freshVarN 0 "x" Variable frV

instance FreeVariables K.Term where 
  freeVars (K.Var _ _ v _)          = singleton v
  freeVars (K.Mu _ _ v c _)         = delete v (freeVars c)
  freeVars (K.Xtor _ _ _ args _)    = unions (freeVars <$> args)
  freeVars (K.XCase _ _ pts _)      = unions (freeVars <$> pts)
  freeVars (K.ShiftCBV _ _ t _)     = freeVars t 
  freeVars (K.ShiftCBN _ _ t _)     = freeVars t 

instance FreeVariables K.Pattern where 
  freeVars (K.Pattern pt) = foldr delete (freeVars pt.ptcmd) pt.ptv

instance FreeVariables K.Command where 
  freeVars (K.Cut _ t1 _ t2) = union (freeVars t1) (freeVars t2) 
  freeVars (K.Done _) = empty
  freeVars (K.Err _ _)  = empty
  freeVars (K.Print _ t) = freeVars t

instance FreeVariables P.Term where
  freeVars (P.Var _ v)              = singleton v
  freeVars (P.Mu _ v c)             = delete v (freeVars c)
  freeVars (P.Xtor _ _ args)        = unions (freeVars <$> args)
  freeVars (P.XCase _ pts)          = unions (freeVars <$> pts)
  freeVars (P.ShiftCBV _ t)         = freeVars t 
  freeVars (P.ShiftCBN _ t)         = freeVars t 
  freeVars (P.Lam _ v t)            = delete v (freeVars t) 
  freeVars (P.App _ t1 t2)          = union (freeVars t1) (freeVars t2)
  freeVars (P.Seq _ t1 t2)          = union (freeVars t1) (freeVars t2)
  freeVars (P.Tup _ ts)             = unions (freeVars <$> ts)
  freeVars (P.Lst _ ts)             = unions (freeVars <$> ts)
  freeVars (P.NotBool _ t)          = freeVars t 
  freeVars (P.AndBool _ t1 t2)      = union (freeVars t1) (freeVars t2)
  freeVars (P.OrBool _ t1 t2)       = union (freeVars t1) (freeVars t2)
  freeVars (P.IfThenElse _ b t1 t2) = union (freeVars b) (union (freeVars t1) (freeVars t2))

instance FreeVariables P.Command where
  freeVars (P.Cut _ t1 _ t2) = union (freeVars t1) (freeVars t2) 
  freeVars (P.CutAnnot _ t1 _ _ t2) = union (freeVars t1) (freeVars t2) 
  freeVars (P.Done _) = empty
  freeVars (P.Err _ _)  = empty
  freeVars (P.Print _ t) = freeVars t
  freeVars (P.PrintAnnot _ t _) = freeVars t
  freeVars (P.CaseOf _ t pts) = union (freeVars t) (unions (freeVars <$> pts))

instance FreeVariables P.Pattern where 
  freeVars (P.Pattern pt) = foldr delete (freeVars pt.ptcmd) pt.ptv

instance FreeVariables D.Term where
  freeVars (D.Var _ v)              = singleton v
  freeVars (D.Mu _ v c)             = delete v (freeVars c)
  freeVars (D.Xtor _ _ args)        = unions (freeVars <$> args)
  freeVars (D.XCase _ pts)          = unions (freeVars <$> pts)
  freeVars (D.ShiftCBV _ t)         = freeVars t 
  freeVars (D.ShiftCBN _ t)         = freeVars t 

instance FreeVariables D.Command where
  freeVars (D.Cut _ t1 _ t2) = union (freeVars t1) (freeVars t2) 
  freeVars (D.CutAnnot _ t1 _ _ t2) = union (freeVars t1) (freeVars t2) 
  freeVars (D.Done _) = empty
  freeVars (D.Err _ _)  = empty
  freeVars (D.Print _ t) = freeVars t
  freeVars (D.PrintAnnot _ t _) = freeVars t

instance FreeVariables D.Pattern where 
  freeVars (D.Pattern pt) = foldr delete (freeVars pt.ptcmd) pt.ptv
