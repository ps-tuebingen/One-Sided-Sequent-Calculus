module Parser.Keywords (
  Keyword (..),
  allKws
) where 

data Keyword = 
  KwModule
  | KwData
  | Kwmu
  | KwMu
  | KwCase
  | KwDone
  | KwForall
  | Kwforall 
  | KwCo
  | Kwco
  | KwImport
  | KwMain
  | Kwmain
  | KwError 
  | KwRec 

instance Show Keyword where 
  show KwModule = "module"
  show KwData   = "data" 
  show KwMu     = "Mu"
  show Kwmu     = "mu"
  show KwCase   = "case"
  show KwDone   = "Done"
  show KwForall = "Forall"
  show Kwforall = "forall"
  show KwCo     = "Co"
  show Kwco     = "co"
  show KwImport = "import"
  show KwMain   = "Main"
  show Kwmain   = "main"
  show KwError  = "error"
  show KwRec    = "rec"

allKws :: [Keyword]
allKws = [KwModule,KwData,Kwmu,KwMu,KwCase,KwDone,KwForall,Kwforall,KwCo,Kwco,KwImport,KwMain,KwMain,KwError,KwRec]
