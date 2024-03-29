module Syntax.Desugared.Terms (
  Command (..),
  Term (..),
  Pattern (..),
  TypedVar,
  MTypedVar
) where 

import Common 
import Loc
import Syntax.Desugared.Types

type TypedVar = (Variable,PolTy)
type MTypedVar = (Variable, Maybe PolTy) 

data Command where 
  Cut      :: Loc  -> Term -> Pol -> Term -> Command 
  CutAnnot :: Loc  -> Term -> PolTy -> Pol -> Term -> Command 
  Done     :: Loc  -> Command 
  Err      :: Loc  -> String -> Command 

instance HasLoc Command where 
  getLoc (Cut loc _ _ _) = loc 
  getLoc (CutAnnot loc _ _ _ _) = loc 
  getLoc (Done loc) = loc 
  getLoc (Err loc _) = loc

  setLoc loc (Cut _ t pol u) =  Cut loc t pol u
  setLoc loc (CutAnnot _ t ty pol u) = CutAnnot loc t ty pol u
  setLoc loc (Done _) = Done loc 
  setLoc loc (Err _ str) = Err loc str

data Pattern = MkPattern{ptxt :: !XtorName, ptv :: ![Variable], ptcmd :: !Command}

data Term where 
  Var      :: Loc -> Variable -> Term 
  Mu       :: Loc -> Variable -> Command -> Term 
  Xtor     :: Loc -> XtorName -> [Term] -> Term
  XCase    :: Loc -> [Pattern] -> Term
  ShiftPos :: Loc -> Term -> Term
  ShiftNeg :: Loc -> Variable -> Command -> Term

instance HasLoc Term where 
  getLoc (Var loc _) = loc 
  getLoc (Mu loc _ _) = loc
  getLoc (Xtor loc _ _) = loc
  getLoc (XCase loc _) = loc
  getLoc (ShiftPos loc _) = loc
  getLoc (ShiftNeg loc _ _) = loc

  setLoc loc (Var _ v) = Var loc v 
  setLoc loc (Mu _ v c) = Mu loc v c
  setLoc loc (Xtor _ nm args) = Xtor loc nm args
  setLoc loc (XCase _ pts) = XCase loc pts
  setLoc loc (ShiftPos _ t) = ShiftPos loc t 
  setLoc loc (ShiftNeg _ v c) = ShiftNeg loc v c
