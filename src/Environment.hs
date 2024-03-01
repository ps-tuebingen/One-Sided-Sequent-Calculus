module Environment where 

import Syntax.Typed.Program 
import Errors 
import Common 

import Control.Monad.Except
import Control.Monad.Reader
import Data.Map qualified as M
import Data.List (find)

newtype Environment = MkEnv { envDefs :: Program }

emptyEnv :: Environment
emptyEnv = MkEnv emptyProg 

addDeclEnv :: DataDecl -> Environment -> Environment 
addDeclEnv decl (MkEnv defs) = MkEnv (addDeclProgram decl defs)

addVarEnv :: VarDecl -> Environment -> Environment 
addVarEnv var (MkEnv defs) = MkEnv (addVarProgram var defs)

type EnvReader a m = (MonadError Error m, MonadReader Environment m)

lookupMDecl :: EnvReader a m => TypeName -> m (Maybe DataDecl)
lookupMDecl tyn = do 
  decls <- asks (progDecls . envDefs)
  return $ M.lookup tyn decls

lookupDecl :: EnvReader a m => TypeName -> m DataDecl 
lookupDecl tyn = do   
  mdecl <- lookupMDecl tyn
  case mdecl of 
    Nothing -> throwError (ErrMissingDecl tyn WhereEnv)
    Just decl -> return decl

lookupMVar :: EnvReader a m => Variable -> m (Maybe VarDecl)
lookupMVar v = do 
  vars <- asks (progVars . envDefs) 
  return $ M.lookup v vars 

lookupVar :: EnvReader a m => Variable -> m VarDecl
lookupVar v = do 
  mvar <- lookupMVar v 
  case mvar of 
    Nothing -> throwError (ErrMissingVar v WhereEnv)
    Just decl -> return decl

lookupMXtor :: EnvReader a m => XtorName -> m (Maybe XtorSig)
lookupMXtor xtn = do
  decls <- asks (progDecls . envDefs) 
  let sigs = concatMap (declXtors . snd) (M.toList decls)
  return $ find (\x -> sigName x == xtn) sigs 

lookupXtor :: EnvReader a m => XtorName -> m XtorSig
lookupXtor xtn = do
  mxt <- lookupMXtor xtn
  case mxt of 
    Nothing -> throwError (ErrMissingXtor xtn WhereEnv) 
    Just xt -> return xt

lookupXtorMDecl :: EnvReader a m => XtorName -> m (Maybe DataDecl)
lookupXtorMDecl xtn = do 
  decls <- asks (progDecls . envDefs)
  return $ find (\x -> xtn `elem` (sigName <$> declXtors x)) decls

lookupXtorDecl :: EnvReader a m => XtorName -> m DataDecl 
lookupXtorDecl xtn = do
  decl <- lookupXtorMDecl xtn
  case decl of 
    Nothing -> throwError (ErrMissingXtor xtn WhereEnv) 
    Just decl' -> return decl'

getTypeNames :: EnvReader a m => m [TypeName]
getTypeNames = do 
  decls <- asks (progDecls . envDefs)
  return $ fst <$> M.toList decls

getXtorNames :: EnvReader a m => m [XtorName]
getXtorNames = do 
  decls <- asks (progDecls . envDefs)
  return (sigName <$> concatMap declXtors decls)
