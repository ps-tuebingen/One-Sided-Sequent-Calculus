module Parser.Lexer (
  sc,
  sc1,
  parseSymbol,
  parseKeyword,
  parseCommaSep,
  parseIdentifier,
  parseParens,
  parseAngO,
  parseAngC,
  getCurrPos,
  getCurrLoc
) where 

import Loc (Loc,SourcePosition)
import Parser.Definition (SrcParser)
import Parser.Keywords (Keyword, allKws)
import Parser.Symbols (Sym(..))

import Prelude (show, bind, pure,($), Unit, unit, (<$>), (<>), (<<<))
import Data.List (List(..),elem)
import Data.String.CodeUnits (singleton)
import Data.List.NonEmpty (toList)
import Control.Monad ((*>))
import Parsing (fail, position, Position(..))
import Parsing.String (string, anyChar, char)
import Parsing.String.Basic (space, alphaNum)
import Parsing.Combinators (many, many1, manyTill, try, (<|>))

parseSymbol :: Sym -> SrcParser Unit
parseSymbol sym = do 
  _ <- string (show sym)
  pure $ unit

parseComment :: SrcParser Unit
parseComment = try $ do
  _ <- parseSymbol SymMinus
  _ <- parseSymbol SymMinus
  _ <- manyTill anyChar (char '\n') 
  pure unit


sc :: SrcParser Unit 
sc = many (space *> pure unit <|> parseComment)  *> pure unit

sc1 :: SrcParser Unit 
sc1 = space *> sc

parseParens :: forall a.SrcParser a -> SrcParser a
parseParens p = do 
  _<-parseSymbol SymParensO 
  _<- sc
  a <- p
  _<- sc
  _ <- parseSymbol SymParensC 
  pure a

parseAngO :: SrcParser Unit 
parseAngO = parseSymbol SymAngO <|> parseSymbol SymAngOUnicode 

parseAngC :: SrcParser Unit 
parseAngC = parseSymbol SymAngC <|> parseSymbol SymAngCUnicode

parseKeyword :: Keyword -> SrcParser Unit 
parseKeyword kw = do
 _ <- string (show kw)
 pure unit

parseCommaSep :: SrcParser Unit
parseCommaSep = do 
  _ <- parseSymbol SymComma
  sc


parseIdentifier :: SrcParser String
parseIdentifier = do
  ident <- (lsToStr <<< toList) <$> many1 alphaNum
  if ident `elem` (show <$> allKws) then fail ("identifier cannot be a keyword, got " <> show ident) else pure ident
  where 
    lsToStr :: List Char -> String
    lsToStr Nil = ""
    lsToStr (Cons c1 cs) = 
      let rst :: String 
          rst = lsToStr cs 
      in (singleton c1) <> rst 

getCurrPos :: SrcParser SourcePosition
getCurrPos = do 
  Position { column:col, index:_, line:ln } <- position 
  pure {srcCol:col,srcLine:ln}

getCurrLoc :: SourcePosition -> SrcParser Loc 
getCurrLoc startPos = do 
    currPos <- getCurrPos
    pure {locStart:startPos, locEnd:currPos }
