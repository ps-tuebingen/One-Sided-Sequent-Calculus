module Desugar.Terms (
  desugarCommand,
  desugarTerm
) where 

import Common (Xtorname(..),EvaluationOrder(..),Variable(..))
import Desugar.Definition(DesugarM,varToXtor,xtorToVar,getDesMXtor,freshVar)
import Desugar.Errors (DesugarError(..))
import Desugar.Types (desugarTy)
import Syntax.Parsed.Terms (Term(..),Pattern(..),Command(..)) as P
import Syntax.Desugared.Terms (Term(..),Pattern(..),Command(..)) as D

import Prelude (bind,($),pure,(<$>))
import Data.Traversable (for)
import Data.List (List(..),uncons)
import Data.Maybe (Maybe(..))
import Control.Monad.Except (throwError)


desugarTerm :: P.Term -> DesugarM D.Term
desugarTerm (P.Var loc v) = do
  let vxt = varToXtor v
  mxt <- getDesMXtor vxt
  case mxt of 
    Nothing -> pure $ D.Var loc v
    Just _ -> pure $ D.Xtor loc vxt Nil 
desugarTerm (P.Mu loc v c) = do 
  c' <- desugarCommand c
  pure $ D.Mu loc v c'
desugarTerm (P.Xtor loc xtn args) = do 
  mxt <- getDesMXtor xtn
  case mxt of 
      Nothing -> do
         let varT = P.Var loc (xtorToVar xtn)
         desugarTerm (getAppT varT args)
      Just _ -> do
        args' <- for args desugarTerm
        pure $ D.Xtor loc xtn args'
  where 
    getAppT :: P.Term -> List P.Term -> P.Term
    getAppT t1 Nil = t1 
    getAppT t1 (Cons t2 ts) = getAppT (P.App loc t1 t2) ts
desugarTerm (P.XCase loc pts) = do
  pts' <- for pts desugarPattern
  pure $ D.XCase loc pts'
desugarTerm (P.ShiftCBV loc t) = do
  t' <- desugarTerm t
  pure $ D.ShiftCBV loc t'
desugarTerm (P.ShiftCBN loc t) = do 
  t' <- desugarTerm t
  pure $ D.ShiftCBN loc t'
desugarTerm t@(P.App loc t1 t2) = do
  t1' <- desugarTerm t1 
  t2' <- desugarTerm t2
  v <- freshVar t
  let args = Cons t2' (Cons (D.Var loc v) Nil)
  let cut = D.Cut loc t1' CBV (D.Xtor loc (Xtorname "Ap") args) 
  pure $ D.Mu loc v cut
desugarTerm t@(P.Lam loc v t') = do
  v' <- freshVar t
  let ptVars = Cons v (Cons v' Nil)
  t'' <- desugarTerm t'
  let cut = D.Cut loc t'' CBV (D.Var loc v')
  let pt = D.Pattern {ptxt:Xtorname "Ap", ptv:ptVars, ptcmd:cut }
  pure $ D.XCase loc (Cons pt Nil) 
desugarTerm t@(P.Seq loc t1 t2) = do 
  v <- freshVar t
  desugarTerm $ P.App loc (P.Lam loc v t2) t1
desugarTerm (P.Tup loc ts) = case uncons ts of 
  Nothing -> throwError (ErrEmptyPair loc)
  Just {head:_,tail:Nil} -> throwError (ErrEmptyPair loc)
  Just {head:t1,tail:Cons t2 Nil} -> do
    t1' <- desugarTerm t1 
    t2' <- desugarTerm t2
    pure $ D.Xtor loc (Xtorname "Tup") (Cons t1' (Cons t2' Nil))
  Just {head:t1,tail:ts'} -> do 
    t1' <- desugarTerm t1
    pairRest <- desugarTerm (P.Tup loc ts') 
    pure $ D.Xtor loc (Xtorname "Tup") (Cons t1' (Cons pairRest Nil))
desugarTerm (P.Lst loc ts) = case ts of 
  Nil -> pure $ D.Xtor loc (Xtorname "Nil") Nil
  Cons t1 ts' -> do
     t1' <- desugarTerm t1
     listRest <- desugarTerm (P.Lst loc ts')
     pure $ D.Xtor loc (Xtorname "Cons") (Cons t1' (Cons listRest Nil))
desugarTerm (P.NotBool loc t) = do
  let notFun = P.Var loc (Variable "not")
  desugarTerm $ P.App loc notFun t 
desugarTerm (P.AndBool loc t1 t2) = do
  let andFun = P.Var loc (Variable "and")
  desugarTerm $ P.App loc (P.App loc andFun t1) t2
desugarTerm (P.OrBool loc t1 t2) = do
  let orFun = P.Var loc (Variable "or")
  desugarTerm $ P.App loc (P.App loc orFun t1) t2
desugarTerm (P.IfThenElse loc b t1 t2) = do 
  let iteFun = P.Var loc (Variable "ifthenelse")
  desugarTerm $ P.App loc (P.App loc (P.App loc iteFun b) t1) t2

desugarPattern :: P.Pattern -> DesugarM D.Pattern
desugarPattern (P.Pattern pt) = do 
  c' <- desugarCommand pt.ptcmd
  pure $ D.Pattern {ptxt:pt.ptxt, ptv:pt.ptv, ptcmd:c'}

desugarCommand :: P.Command -> DesugarM D.Command 
desugarCommand (P.Cut loc t pol u) = do 
  t' <- desugarTerm t
  u' <- desugarTerm u 
  pure $ D.Cut loc t' pol u'
desugarCommand (P.CutAnnot loc t ty pol u) = do
  t' <- desugarTerm t
  u' <- desugarTerm u
  ty' <- desugarTy ty 
  pure $ D.CutAnnot loc t' ty' pol u'
desugarCommand (P.Done loc) = pure (D.Done loc)
desugarCommand (P.Err loc str) = pure $ D.Err loc str
desugarCommand (P.Print loc t) = D.Print loc <$> desugarTerm t
desugarCommand (P.PrintAnnot loc t ty) = do 
  t' <- desugarTerm t
  ty' <- desugarTy ty
  pure $ D.PrintAnnot loc t' ty' 
desugarCommand (P.CaseOf loc t pts) = do 
  pts' <- for pts desugarPattern
  let xcase = D.XCase loc pts'
  t' <- desugarTerm t
  pure $ D.Cut loc t' CBV xcase
