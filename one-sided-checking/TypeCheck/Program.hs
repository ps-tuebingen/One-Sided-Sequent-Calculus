module TypeCheck.Program (
  checkVarDecl,
  checkRecDecl
) where 

import TypeCheck.Definition
import TypeCheck.Terms
import TypeCheck.Types
import Syntax.Desugared.Program qualified as D 
import Syntax.Typed.Program     qualified as T 
import Syntax.Typed.Terms       qualified as T
import Pretty.Common ()

import Control.Monad.Except

checkVarDecl :: D.VarDecl -> CheckM T.VarDecl
checkVarDecl (D.MkVar loc nm (Just ty) t) =  do
  tys <- inferType loc ty
  t' <- checkTermMultiple t tys
  return $ T.MkVar loc nm (T.getType t') t'
checkVarDecl (D.MkVar loc nm Nothing _) = throwError (ErrNoAnnot loc nm)

checkRecDecl :: D.RecDecl -> CheckM T.RecDecl 
checkRecDecl (D.MkRec loc nm (Just ty) t) = do 
  tys <- inferType loc ty 
  t' <- checkTermMultipleRec t nm tys
  return $ T.MkRec loc nm (T.getType t') t'
checkRecDecl (D.MkRec loc nm Nothing _) = throwError (ErrNoAnnot loc nm)
