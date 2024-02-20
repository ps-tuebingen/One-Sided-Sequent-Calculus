module TypeInference.Definition where 

import Typed.Types
import Typed.Syntax
import Typed.Program
import Common

import Data.Map qualified as M
import Control.Monad.Except
import Control.Monad.State

---
--- Constraint Monad
--- 
data Constraint = 
  MkTyEq !Ty !Ty
  | MkKindEq !Kind !Kind
  | MkFlipEq !Kind !Kind
  | MkProdEq !Pol !Kind !Kind


data GenerateState = MkGenState{
  varEnv :: !(M.Map Variable Ty),
  tyVarEnv :: !(M.Map TypeVar Kind),
  tyVarCnt :: !Int,
  kndVarCnt :: !Int,
  declEnv :: ![DataDecl],
  constrSet :: ![Constraint]
}

initialGenState :: [DataDecl] -> GenerateState 
initialGenState decls = MkGenState M.empty M.empty 0 0 decls []


newtype GenM a = GenM { getGenM :: StateT GenerateState (Except String) a }
  deriving newtype (Functor, Applicative, Monad, MonadState GenerateState, MonadError String)

runGenM :: [DataDecl] -> GenM a -> Either String (a, [Constraint])
runGenM decls m = case runExcept (runStateT (getGenM m) (initialGenState decls)) of
  Left err -> Left err 
  Right (x, st) ->  Right (x,constrSet st)

-- Fresh Variables 
freshTyVar :: GenM TypeVar
freshTyVar = do 
  cnt <- gets tyVarCnt
  let newVar = "X" <> show cnt
  modify (\s -> MkGenState (varEnv s) (tyVarEnv s) (cnt+1) (kndVarCnt s) (declEnv s) (constrSet s))
  return newVar

freshKndVar :: GenM KindVar
freshKndVar = do 
  cnt <- gets kndVarCnt 
  let newVar = "K" <> show cnt
  modify (\s -> MkGenState (varEnv s) (tyVarEnv s) (tyVarCnt s) (cnt+1) (declEnv s) (constrSet s))
  return newVar


-- modify environment
addConstraint :: Constraint -> GenM () 
addConstraint ctr = modify (\s -> MkGenState (varEnv s) (tyVarEnv s) (tyVarCnt s) (kndVarCnt s) (declEnv s) (ctr:constrSet s))

addVar :: Variable -> Ty -> GenM ()
addVar v ty = do 
  vars <- gets varEnv
  modify (\s -> MkGenState (M.insert v ty vars) (tyVarEnv s) (tyVarCnt s) (kndVarCnt s) (declEnv s) (constrSet s))

addTyVar :: TypeVar -> Kind -> GenM ()
addTyVar tyv knd = do
  tyVars <- gets tyVarEnv 
  modify (\s -> MkGenState (varEnv s) (M.insert tyv knd tyVars) (tyVarCnt s) (kndVarCnt s) (declEnv s) (constrSet s))

findDataDecl :: XtorName -> GenM (Maybe (DataDecl,XtorSig))
findDataDecl nm = do
  decls <- gets declEnv 
  return $ checkDecl nm decls 
  where
    checkDecl :: XtorName -> [DataDecl] -> Maybe (DataDecl,XtorSig)
    checkDecl _ [] = Nothing
    checkDecl n (d@(MkDataDecl _ _ _ xtors):dcs) = 
      case checkXtor n xtors of 
        Nothing -> checkDecl n dcs
        Just sig -> Just (d,sig)

    checkXtor :: XtorName -> [XtorSig] -> Maybe XtorSig
    checkXtor _ [] = Nothing
    checkXtor xtn (xt:xts) = if sigName xt == xtn then Just xt else checkXtor nm xts


addConstraintsXtor :: XtorName -> [Ty] -> [Ty] -> GenM () 
addConstraintsXtor _ [] [] = return () 
addConstraintsXtor xt _ [] = throwError ("Wrong number of arguments for " <> xt)
addConstraintsXtor xt [] _ = throwError ("Wrong number of arguments for " <> xt)
addConstraintsXtor xt (ty1:tys1) (ty2:tys2) = do 
  addConstraint (MkTyEq ty1 ty2)
  addConstraint (MkKindEq (getKind ty1) (getKind ty2))
  addConstraintsXtor xt tys1 tys2
