module Desugar.Types (
  desugarPolTy,
  desugarTy
) where

import Desugar.Definition
import Environment qualified as Env
import Syntax.Parsed.Types    qualified as P
import Syntax.Desugared.Types qualified as D

import Control.Monad

desugarTy :: P.Ty -> DesugarM D.Ty
desugarTy (P.TyVar v) = do 
  let vty = tyvarToTyName v
  declTys <- Env.getTypeNames
  currNames <- getDesDefNames
  if vty `elem` declTys++currNames then return (D.TyDecl vty []) else return $ D.TyVar v 
desugarTy (P.TyDecl tyn args) = do 
  args' <- forM args desugarTy 
  return $ D.TyDecl tyn args' 
desugarTy (P.TyCo ty) = D.TyCo <$> desugarTy ty
desugarTy (P.TyShift ty) = D.TyShift <$> desugarTy ty
desugarTy (P.TyForall args ty) = D.TyForall args <$> desugarTy ty

desugarPolTy :: P.PolTy -> DesugarM D.PolTy
desugarPolTy (P.MkPolTy ty pol) = do
  ty' <- desugarTy ty 
  return (D.MkPolTy ty' pol)
