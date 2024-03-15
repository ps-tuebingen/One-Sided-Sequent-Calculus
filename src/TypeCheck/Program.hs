module TypeCheck.Program where 

import TypeCheck.Definition
import TypeCheck.Terms
import TypeCheck.Types
import Syntax.Desugared.Program qualified as D 
import Syntax.Typed.Program     qualified as T 
import Syntax.Typed.Terms       qualified as T
import Errors
import Pretty.Common ()

import Control.Monad.Except

checkVarDecl :: D.VarDecl -> CheckM T.VarDecl
checkVarDecl (D.MkVar nm (Just polty) t) =  do
  ty <- checkPolTy polty
  t' <- checkTerm t ty
  return $ T.MkVar nm (T.getType t') t'
checkVarDecl (D.MkVar nm Nothing _) = throwError (ErrMissingType ("Cannot typecheck variable " <> show nm <> " without a type annotation"))

checkRecDecl :: D.RecDecl -> CheckM T.RecDecl 
checkRecDecl (D.MkRec nm (Just polty) t) = do 
  ty <- checkPolTy polty
  addVarPol nm ty
  t' <- checkTerm t ty 
  return $ T.MkRec nm (T.getType t') t'
checkRecDecl (D.MkRec nm Nothing _) = throwError (ErrMissingType ("Cannot typecheck recursive variable " <> show nm <> "without a tpye annotation"))
