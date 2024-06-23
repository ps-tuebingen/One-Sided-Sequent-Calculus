module Layout (render) where 

import Definitions (RunResult(..),Input, State)
import Events (runSrc, selectExample, createEditor)
import StandardLib (libMap)

import Prelude (($),(<>),(<$>),(+),show)
import Data.Map (toUnfoldable)
import Data.Tuple (Tuple(..))
import Data.Array (length)
import Data.String (split,Pattern(..))
import Web.HTML.Common (ClassName(..))
import Halogen.HTML (HTML,text)
import Halogen.HTML.Elements (body,div,div_,textarea,button,h1_, h2_,br_, select,option_)
import Halogen.HTML.Properties (class_,id, readOnly,value,style)
import Halogen.HTML.Events (onClick,onValueChange)


getHTMLHeight :: String -> String 
getHTMLHeight str = let nlines = length (split (Pattern "\n") str)  in 
  "height: " <> show (nlines +3) <> "em;"

render :: forall w. State -> HTML w Input
render {runRes:res} = layout res

progDiv :: forall w. HTML w Input
progDiv = div 
  [ id "container", class_ $ ClassName "prog"]
  []


getArea :: forall w. String -> ClassName -> String -> HTML w Input 
getArea contents cl htmlId = 
  textarea [class_ cl,id htmlId, readOnly true, value contents, style $ getHTMLHeight contents]

resDiv :: forall w.RunResult -> HTML w Input 
resDiv (ResErr {errMsg:err, errDebug:debug, errTypes:tys}) = div [ class_ $ ClassName "results"]
  [
    h1_ [text "Results"],
    h2_ [text "Output"],
    getArea ("Error: " <> err) (ClassName "evalError") "evalRes",
    br_,
    h2_ [text "Inferred Types"],
    getArea tys (ClassName "results") "typesStr",
    h2_ [text "Debug Trace"],
    getArea debug (ClassName "results") "debugStr"
  ]
resDiv (ResSucc{succCmd:cmd,succTrace:tr,succDebug:debug, succTypes:tys}) = div 
  [ class_ $ ClassName "results" ]
  [ 
    h1_ [text "Results"],
    h2_ [text "Output"],
    getArea cmd (ClassName "evalSucc") "evalRes",
    br_,
    h2_ [text "Inferred Types"],
    getArea tys (ClassName "results") "typesStr",
    h2_ [text "Evaluation Trace"],
    br_,
    textarea [id "traceStr", readOnly true, value tr, style $ getHTMLHeight tr],
    h2_ [text "Debug Trace"],
    getArea debug (ClassName "results") "debugStr"
  ]

exSelect :: forall w. HTML w Input
exSelect = div_ [
  text "Choose Example ",
  select [id "exampleSelect", onValueChange selectExample] 
    ((\(Tuple mn _) -> option_ [text (show mn)]) <$>  toUnfoldable libMap),
  br_
  ]

layout :: forall w. RunResult -> HTML w Input
layout res = body  []
  [
    h1_ [text "One Sided Sequent Calculus"],
    -- temporary Button to create Editor until i find a way to create the editor after loading
    button [id "createEditor", onClick createEditor] [text "Create Editor"],
    exSelect,
    progDiv ,
    button [id "runButton", onClick runSrc] [text "Run"],
    resDiv res
  ]

