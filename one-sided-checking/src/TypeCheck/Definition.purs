module TypeCheck.Definition (
  runCheckM,
  CheckM,
  getCheckerVars,
  getCheckerTyVars,
  addCheckerVar,
  addCheckerTyVar,
  withCheckerVars,
  getMTypeVar,
  getTypeVar,
  CheckerError (..)
) where 

import Environment
import Common
import Loc
import Embed.Definition
import Embed.EmbedKinded ()
import TypeCheck.Errors
import Syntax.Typed.Types    qualified as T 
import Syntax.Kinded.Program qualified as K
import Pretty.Typed () 
import Pretty.Desugared ()

import Control.Monad.Except 
import Control.Monad.Reader
import Control.Monad.State
import Data.Map qualified as M


data CheckerState = MkCheckState { checkVars :: !(M.Map Variable T.Ty), checkTyVars :: ![Typevar]}

initialCheckerState :: CheckerState 
initialCheckerState = MkCheckState M.empty []


newtype CheckM a = CheckM { getCheckM :: ReaderT Environment (StateT CheckerState (Except CheckerError)) a }
  deriving newtype (Functor, Applicative, Monad, MonadReader Environment, MonadError CheckerError, MonadState CheckerState)

runCheckM :: Environment -> CheckM a -> Either CheckerError a
runCheckM env m = case runExcept (runStateT (runReaderT (getCheckM m) env) initialCheckerState) of 
  Left err -> Left err
  Right (x,_) -> Right x

addCheckerVar :: Variable -> T.Ty -> CheckM () 
addCheckerVar v ty = modify (\s -> MkCheckState (M.insert v ty (checkVars s)) (checkTyVars s))

addCheckerTyVar :: Typevar -> CheckM ()
addCheckerTyVar tyv = modify (\s -> MkCheckState (checkVars s) (tyv:checkTyVars s))

getCheckerVars :: CheckM (M.Map Variable T.Ty)
getCheckerVars = gets checkVars

getCheckerTyVars :: CheckM [Typevar] 
getCheckerTyVars = gets checkTyVars

withCheckerVars :: M.Map Variable T.Ty -> CheckM a -> CheckM  a
withCheckerVars newVars fun = do
  currVars <- gets checkVars
  modify (MkCheckState newVars . checkTyVars) 
  res <- fun  
  modify (MkCheckState currVars . checkTyVars)
  return res

getMTypeVar :: Variable -> CheckM (Maybe T.Ty)
getMTypeVar v = do
  vars <- getCheckerVars 
  mvar <- lookupMVar v
  mrec <- lookupMRec v
  case (M.lookup v vars,mvar,mrec) of 
    (Nothing,Nothing,Nothing) -> return Nothing 
    (Just ty,_,_) -> return (Just ty)
    (_,Just vdecl,_) -> return (Just . embed . K.varTy $ vdecl)
    (_,_,Just rdecl) -> return (Just . embed . K.recTy $ rdecl) 

getTypeVar :: Loc -> Variable -> CheckM T.Ty 
getTypeVar loc v = do 
  mty <- getMTypeVar v 
  case mty of 
    Nothing -> throwError (ErrUndefinedVar loc v)
    Just ty -> return ty