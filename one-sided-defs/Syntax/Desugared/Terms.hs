module Syntax.Desugared.Terms (
  Command (..),
  Term (..),
  Pattern (..),
  TypedVar,
  MTypedVar
) where 

import Common 
import Syntax.Desugared.Types

type TypedVar = (Variable,PolTy)
type MTypedVar = (Variable, Maybe PolTy) 

data Command = 
  Cut !Term !Pol !Term
  | CutAnnot !Term !PolTy !Pol !Term
  | Done
  | Err !String

data Pattern = MkPattern{ptxt :: !XtorName, ptv :: ![Variable], ptcmd :: !Command}

data Term = 
  Var !Variable
  | Mu !Variable !Command 
  | Xtor !XtorName ![Term]
  | XCase ![Pattern]
  | ShiftPos !Term
  | ShiftNeg !Variable !Command