module Syntax.Parsed.Program (
  XtorSig (..),
  AnnotDecl (..),
  VarDecl (..),
  DataDecl (..),
  Import (..),
  Program (..),
  addMainProgram,
  addImportProgram,
  addAnnotProgram,
  addVarProgram,
  addDeclProgram,
  setSrcProgram,
  emptyProg
) where 

import Loc (Loc, class HasLoc)
import Common (Xtorname, Typename, VariantVar,DeclTy,Variable, Modulename,PrdCns)

import Prelude (class Eq, class Ord, class Show, show, (<>), (<$>), (==))
import Data.List (List(..), null, intercalate)
import Data.Tuple (Tuple)
import Syntax.Parsed.Terms (Term,Command)
import Syntax.Parsed.Types (Ty)


data XtorSig = XtorSig{sigPos :: Loc, sigName :: Xtorname, sigArgs :: List (Tuple PrdCns Ty) } 
derive instance eqXtorSig :: Eq XtorSig 
derive instance ordXtorSig :: Ord XtorSig
instance Show XtorSig where 
  show (XtorSig sig) | null sig.sigArgs = show sig.sigName
  show (XtorSig sig) = show sig.sigName <> "(" <> intercalate ", " (show <$> sig.sigArgs) <> ")"
instance HasLoc XtorSig where 
  getLoc (XtorSig sig) = sig.sigPos
  setLoc loc (XtorSig sig) = XtorSig (sig {sigPos=loc})

data DataDecl  = DataDecl 
  {declPos   :: Loc, 
   declName  :: Typename, 
   declArgs  :: List VariantVar, 
   declType  :: DeclTy, 
   declXtors :: List XtorSig} 
derive instance eqDataDecl :: Eq DataDecl
derive instance ordDataDecl:: Ord DataDecl
instance Show DataDecl where 
  show (DataDecl decl) | null decl.declArgs = 
    show decl.declType <> " " <> show decl.declName <> "{" <> intercalate ", " (show <$> decl.declXtors) <> "}"
  show (DataDecl decl) =  
    show decl.declType <> " " <> show decl.declName <> "(" <> intercalate ", " (show <$> decl.declArgs) <> ")  {" <> intercalate ",  " (show <$> decl.declXtors) <> "}"
instance HasLoc DataDecl where 
  getLoc (DataDecl decl) = decl.declPos
  setLoc loc (DataDecl decl) = DataDecl (decl {declPos=loc})

data VarDecl   = VarDecl {varPos::Loc, varName::Variable, varIsRec::Boolean, varBody::Term}
derive instance eqVarDecl :: Eq VarDecl 
derive instance ordVarDecl :: Ord VarDecl
instance Show VarDecl where
  show (VarDecl decl) | decl.varIsRec = "rec " <> show decl.varName <> " := " <> show decl.varBody <> ";"
  show (VarDecl decl) = show decl.varName <> ":=" <> show decl.varBody <> ";"

instance HasLoc VarDecl where 
  getLoc (VarDecl decl) = decl.varPos
  setLoc loc (VarDecl decl) = VarDecl (decl {varPos=loc})

data AnnotDecl = AnnotDecl {annotPos  :: Loc, annotName :: Variable, annotType :: Ty} 
derive instance eqAnnotDecl :: Eq AnnotDecl
derive instance ordAnnotDecl :: Ord AnnotDecl
instance Show AnnotDecl where 
  show (AnnotDecl decl) = show decl.annotName <> " :: " <> show decl.annotType
instance HasLoc AnnotDecl where 
  getLoc (AnnotDecl decl) = decl.annotPos 
  setLoc loc (AnnotDecl decl) = AnnotDecl (decl {annotPos=loc}) 

data Import = Import    {importPos :: Loc, importName :: Modulename }
derive instance eqImport :: Eq Import 
derive instance ordImport :: Ord Import 
instance Show Import where 
  show (Import imp) = show imp.importName
instance HasLoc Import where 
  getLoc (Import imp) = imp.importPos
  setLoc loc (Import imp) = Import (imp {importPos=loc}) 

data Program = Program { 
  progName    :: Modulename, 
  progDecls   :: List DataDecl, 
  progVars    :: List VarDecl, 
  progAnnots  :: List AnnotDecl,
  progImports :: List Import,
  progMain    :: List Command,
  progSrc     :: String}
derive instance eqProgram :: Eq Program
derive instance ordProgram :: Ord Program

instance Show Program where 
  show (Program prog) | Nil == prog.progMain = 
    "\tmodule " <> show prog.progName  <>
    "\n\tImports:\n\t\t" <> showList prog.progImports <> 
    "\n\tDeclarations:\n\t\t" <> showList prog.progDecls <> 
    "\n\tVariables:\n\t\t" <> showList prog.progVars <> 
    "\n\tAnnotations:\n\t\t" <> showList prog.progVars
  show (Program prog) = 
    "\tmodule " <> show prog.progName  <>
    "\n\tImports:\n\t\t" <> showList prog.progImports <> 
    "\n\tDeclarations:\n\t\t" <> showList prog.progDecls <> 
    "\n\tVariables:\n\t\t" <> showList prog.progVars <> 
    "\n\tAnnotations:\n\t\t" <> showList prog.progAnnots <> 
    "\n\tMain: "<> show prog.progMain

showList :: forall a. Show a => List a -> String
showList ls = intercalate "\n\t\t" (show<$>ls)

emptyProg :: Modulename -> String -> Program 
emptyProg mn src = Program {
  progName   : mn,
  progDecls  : Nil,
  progVars   : Nil,
  progAnnots : Nil,
  progImports: Nil,
  progMain   : Nil,
  progSrc    : src
}

addDeclProgram :: DataDecl -> Program -> Program 
addDeclProgram decl (Program prog) = 
  Program (prog { progDecls = Cons decl prog.progDecls })

addVarProgram :: VarDecl -> Program -> Program 
addVarProgram var (Program prog) = 
  Program (prog { progVars = Cons var prog.progVars })

addAnnotProgram :: AnnotDecl -> Program -> Program 
addAnnotProgram annot (Program prog) = 
  Program (prog { progAnnots = Cons annot prog.progAnnots})

addImportProgram :: Import -> Program -> Program
addImportProgram imp (Program prog) = 
  Program (prog { progImports = (Cons imp prog.progImports)})

addMainProgram :: Command -> Program -> Program
addMainProgram c (Program prog) = 
  Program (prog { progMain = Cons c prog.progMain })

setSrcProgram :: String -> Program -> Program 
setSrcProgram src (Program prog) = 
  Program (prog { progSrc = src })
