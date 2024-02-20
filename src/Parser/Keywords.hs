module Parser.Keywords where 

data Keyword = 
  KwModule
  | KwData
  | KwVal
  | KwMu

instance Show Keyword where 
  show KwModule = "module"
  show KwData   = "data" 
  show KwVal    = "val"
  show KwMu     = "mu"
