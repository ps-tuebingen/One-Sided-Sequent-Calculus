module Parser.Terms (
  parseTerm,
  parseCommand
) where

import Parser.Definition (SrcParser)
import Parser.Lexer (sc, getCurrPos,getCurrLoc, parseParens,parseKeyword, parseSymbol, parseCommaSep, parseAngC, parseAngO)
import Parser.Common (parseVariable, parseXtorname, parseEvaluationOrder)
import Parser.Keywords (Keyword(..))
import Parser.Symbols (Sym(..))
import Parser.Types (parseTy)
import Common (EvaluationOrder(..))
import Syntax.Parsed.Terms (Term(..),Command(..),Pattern(..))
import Syntax.Parsed.Types (Ty)

import Prelude (bind, ($), pure, (<>))
import Data.List (List(..))
import Data.Tuple (Tuple(..))
import Data.Maybe (Maybe(..))
import Data.Unit (unit)
import Data.String.CodeUnits (singleton)
import Parsing.Combinators (try, sepBy, manyTill, optionMaybe)
import Parsing.String (anyChar, char)
import Control.Alt ((<|>))


parseTerm :: SrcParser Term 
parseTerm = parseParens ((\_ -> parseT) unit) <|> (\_ -> parseT) unit

parseT :: SrcParser Term
parseT =
  (\_ -> parseMu) unit    <|> 
  (\_ -> parseXCase) unit <|>
  (\_ -> parseShift) unit <|>
  (\_ -> try parseXtor) unit <|> 
  (\_ -> parseVar) unit 

parseMu :: SrcParser Term   
parseMu = do 
  startPos <- getCurrPos
  _ <- parseKeyword KwMu <|> parseKeyword Kwmu 
  _ <- sc
  v <- parseVariable 
  _ <- sc
  _ <- parseSymbol SymDot
  _ <- sc
  c <- parseCommand
  loc <- getCurrLoc startPos
  pure $ Mu loc v c

parseXCase :: SrcParser Term 
parseXCase = do
  startPos <- getCurrPos
  _ <- parseKeyword KwCase
  _ <- sc
  _ <- parseSymbol SymBrackO
  _ <- sc
  pts <- parsePattern `sepBy` parseCommaSep 
  _ <- sc
  _ <- parseSymbol SymBrackC
  loc <- getCurrLoc startPos
  pure (XCase loc pts)

parseShift :: SrcParser Term 
parseShift = do
  startPos <- getCurrPos
  _ <- parseSymbol SymBrackO
  _ <- sc
  t <- parseTerm
  _ <- sc
  _ <- parseSymbol SymColon
  _ <- sc
  eo <- parseEvaluationOrder
  _ <- parseSymbol SymBrackC
  loc <- getCurrLoc startPos
  case eo of 
    CBV -> pure (ShiftCBV loc t)
    CBN -> pure (ShiftCBN loc t)

parseXtor :: SrcParser Term
parseXtor = do
  startPos <- getCurrPos 
  nm <- parseXtorname 
  _ <- sc
  _ <- parseSymbol SymParensO
  _ <- sc
  args <- parseTerm `sepBy` parseCommaSep 
  _ <- sc
  _ <- parseSymbol SymParensC 
  loc <- getCurrLoc startPos
  pure $ Xtor loc nm args

parseVar :: SrcParser Term -- variable
parseVar = do
  startPos <- getCurrPos
  v <- parseVariable
  loc <- getCurrLoc startPos
  pure $ Var loc v

--  <|>
--  parseParens parseTerm


parsePattern :: SrcParser Pattern 
parsePattern = do 
  nm <- parseXtorname 
  _ <- sc
  args <- optionMaybe (parseParens (parseVariable `sepBy` parseCommaSep)) 
  _ <- sc
  _ <- parseSymbol SymEq 
  _ <- parseAngC
  _ <- sc
  c <- parseCommand
  case args of 
    Nothing -> pure $ Pattern {ptxt:nm,ptv:Nil,ptcmd:c}
    Just args' -> pure $ Pattern {ptxt:nm,ptv:args',ptcmd:c}

parseCommand :: SrcParser Command 
parseCommand = parseParens ((\_ -> parseC) unit) <|> (\_ -> parseC) unit

parseC :: SrcParser Command 
parseC = 
  (\_ -> parseErr) unit        <|> 
  (\_ -> parseDone) unit       <|>
  (\_ -> parseCut) unit        <|> 

  (\_ -> try parseCutCBV) unit     <|>
  (\_ -> try parseCutCBN) unit     <|>
  (\_ -> try parsePrint)  unit     <|> 
  (\_ -> try parsePrintAnnot) unit      

parseCut :: SrcParser Command 
parseCut = do
  startPos <- getCurrPos
  _ <- parseAngO
  _ <- sc
  t <- parseTerm
  _ <- sc
  _ <- parseSymbol SymBar
  _ <- sc
  Tuple pol mty <- parseCutAnnot 
  _ <- sc
  _ <- parseSymbol SymBar
  _ <- sc
  u <- parseTerm
  _ <- sc
  _ <- parseAngC
  loc <- getCurrLoc startPos 
  case mty of 
    Nothing -> pure (Cut loc t pol u)
    Just ty -> pure (CutAnnot loc t ty pol u)

parseDone :: SrcParser Command 
parseDone = do
  startPos <- getCurrPos
  _ <- parseKeyword KwDone  
  loc <- getCurrLoc startPos 
  pure (Done loc)

parseErr :: SrcParser Command 
parseErr = do
  startPos <- getCurrPos
  _ <- parseKeyword KwError
  _ <- sc 
  _ <- parseSymbol SymQuot
  msg <- manyTill anyChar (char '\n') 
  _ <- parseSymbol SymQuot
  loc <- getCurrLoc startPos
  pure (Err loc (charlsToStr msg))
  where 
    charlsToStr :: List Char -> String
    charlsToStr Nil = "" 
    charlsToStr (Cons c1 cs) = (singleton c1) <> charlsToStr cs


parsePrintAnnot :: SrcParser Command 
parsePrintAnnot = do 
  startPos <- getCurrPos
  _ <- parseKeyword KwPrint <|> parseKeyword Kwprint 
  _ <- sc 
  t <- parseTerm 
  _ <- sc 
  _ <- parseSymbol SymColon
  _ <- parseSymbol SymColon
  _ <- sc 
  ty <- parseTy
  loc <- getCurrLoc startPos
  pure (PrintAnnot loc t ty)

parsePrint :: SrcParser Command 
parsePrint = do
  startPos <- getCurrPos 
  _ <- parseKeyword KwPrint <|> parseKeyword Kwprint
  _ <- sc 
  t <- parseTerm
  _ <- sc 
  loc <- getCurrLoc startPos
  pure (Print loc t)

parseCutCBV :: SrcParser Command
parseCutCBV = do  
    startPos <- getCurrPos 
    t <- parseTerm
    _ <- sc
    _ <- parseAngC
    _ <- parseAngC
    _ <- sc
    mty <- optionMaybe $ try (do
      ty <- parseTy 
      _ <- sc 
      _ <- parseAngC
      _ <- parseAngC 
      _ <- sc 
      pure ty)
    u <- parseTerm
    loc <- getCurrLoc startPos 
    case mty of 
      Nothing -> pure (Cut loc t CBV u)
      Just ty -> pure (CutAnnot loc t ty CBV u)

parseCutCBN :: SrcParser Command
parseCutCBN = do  -- cut with <<
  startPos <- getCurrPos 
  t <- parseTerm 
  _ <- sc 
  _ <- parseAngO
  _ <- parseAngO
  _ <- sc
  mty <- optionMaybe $ try (do
    ty <- parseTy 
    _ <- sc
    _ <- parseAngO
    _ <- parseAngO 
    _ <- sc 
    pure ty)
  u <- parseTerm
  loc <- getCurrLoc startPos 
  case mty of 
    Nothing -> pure (Cut loc t CBN u)
    Just ty -> pure (CutAnnot loc t ty CBN u)

parseCutAnnot :: SrcParser (Tuple EvaluationOrder (Maybe Ty))
parseCutAnnot = try (do 
  ty <- parseTy 
  _ <- sc 
  _ <- parseSymbol SymColon
  _ <- sc 
  eo <- parseEvaluationOrder 
  pure (Tuple eo (Just ty))) 
  <|>
  (do
  eo <- parseEvaluationOrder 
  pure $ Tuple eo Nothing)
