module Untyped.Program where 

import Common 

data XtorSig = MkXtorSig{sigName :: !XtorName, sigArgs :: ![TypeVar]} 

data DataDecl = MkDataDecl{declNm :: !TypeName, declArgs :: ![(Variable,Pol)], declPol :: !Pol, declSig :: ![XtorSig]} 
--data VarDecl  = MkValDecl{valVar  :: !Variable, valTy :: !Ty, valBd :: !Term}
--data RecDecl  = MkRecDecl{recVar  :: !Variable, recTy :: !Ty, recBd :: !Term}
data Eps = MkEps 
newtype Codecl = MkCo DataDecl 
