module Parser.Types (
  parseKindedTy,
  parseTy,
  parseTyArgs,
  parsePrdCnsArg
) where 

import Common (VariantVar,PrdCns(..))
import Syntax.Parsed.Types (Ty(..), KindedTy(..))
import Parser.Definition (SrcParser)
import Parser.Lexer (parseSymbol, parseKeyword, sc, parseCommaSep)
import Parser.Symbols (Sym(..))
import Parser.Keywords (Keyword(..))
import Parser.Common (parseTypevar, parseTypename, parseVariantVar, parseEvaluationOrder)

import Prelude (bind, pure, ($))
import Data.List (List(..))
import Data.Unit (unit)
import Data.Tuple (Tuple(..))
import Data.Maybe (Maybe(..))
import Parsing.String.Basic (space)
import Parsing.Combinators (try, sepBy, many1,optionMaybe)
import Control.Alt ((<|>))

parseTy :: SrcParser Ty 
parseTy = do 
  ty <- (\_ -> parseTyParens) unit   <|> 
        (\_ -> parseTyForall) unit   <|> 
        (\_ -> parseTyShift)  unit   <|> 
        (\_ -> parseTyCo) unit       <|> 
        (\_ -> try parseTyDecl) unit <|> 
        (\_ -> parseTyVar) unit
  try (parseFunTy ty) <|> pure ty

parseFunTy :: Ty -> SrcParser Ty 
parseFunTy ty1 = do
  _ <- sc 
  _ <- parseSymbol SymMinus
  _ <- parseSymbol SymAngC
  _ <- sc
  ty2 <- parseTy 
  pure $ TyFun ty1 ty2


parseTyParens :: SrcParser Ty 
parseTyParens = do 
  _ <- parseSymbol SymParensO
  _ <- sc
  ty <- parseTy
  _ <- sc
  _ <- parseSymbol SymParensC
  pure ty

parseTyForall :: SrcParser Ty 
parseTyForall = do 
  _ <- parseKeyword KwForall <|> parseKeyword Kwforall 
  _ <- sc
  args <- parseTypevar `sepBy` (many1 space)
  _ <- sc
  _ <- parseSymbol SymDot
  _ <- sc
  ty <- parseTy 
  pure $ TyForall args ty


parseTyDecl :: SrcParser Ty 
parseTyDecl = do
  tyn <- parseTypename 
  _ <- parseSymbol SymParensO 
  args <- parseTy `sepBy` parseCommaSep 
  _ <- parseSymbol SymParensC
  pure (TyDecl tyn args)

parseTyVar :: SrcParser Ty 
parseTyVar = do 
    var <- parseTypevar
    pure $ TyVar var 

parseTyShift :: SrcParser Ty 
parseTyShift = do
  _ <- parseSymbol SymBrackO
  _ <- sc
  ty <- parseTy
  _ <- sc
  _ <- parseSymbol SymBrackC 
  pure (TyShift ty)

parseTyCo :: SrcParser Ty 
parseTyCo = do 
  _ <- parseKeyword KwCo <|> parseKeyword Kwco
  _ <- sc
  ty <- parseTy 
  pure $ TyCo ty 
  
parseTyArgs :: SrcParser (List VariantVar)
parseTyArgs = (do 
  _ <- parseSymbol SymParensO
  vars <- parseVariantVar `sepBy` parseCommaSep 
  _ <- parseSymbol SymParensC
  pure vars)
  <|>
  pure Nil

parseKindedTy :: SrcParser KindedTy 
parseKindedTy = do 
  ty <- parseTy
  _ <- sc
  _ <- parseSymbol SymColon
  _ <- sc
  knd <- parseEvaluationOrder
  pure $ KindedTy {kindedTy:ty,kindedKind:knd}


parsePrdCnsArg :: SrcParser (Tuple PrdCns Ty)
parsePrdCnsArg = do 
  isCns <- optionMaybe (parseKeyword KwReturn <|> parseKeyword Kwreturn)
  _ <- sc
  ty <- parseTy 
  case isCns of 
      Nothing -> pure (Tuple Prd ty)
      Just _ -> pure (Tuple Cns ty)
