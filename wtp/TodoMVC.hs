{-# LANGUAGE OverloadedStrings #-}

module TodoMVC
  ( spec,
  )
where

import Control.Lens (lastOf, lengthOf)
import qualified Data.Text as Text
import Data.Text (Text)
import Helpers
import Text.Read (readMaybe)
import WTP.Specification
import WTP.Syntax
import Prelude hiding ((<), (<=), (>), (>=), all, init)

spec :: Text -> Specification Proposition
spec name =
  Specification
    { origin = Path ("http://todomvc.com/examples/" <> name <> "/"),
      readyWhen = ".todoapp",
      actions =
        [ -- (5, [Focus ".todoapp .new-todo", KeyPress 'a', KeyPress '\xe006']), -- full sequence of creating a new item
          (2, KeyPress 'a'),
          (2, KeyPress '\xe006'),
          (2, Focus ".todoapp .new-todo"),
          (2, Click ".todoapp .filters a"),
          (1, Click ".todoapp .destroy")
        ],
      proposition = init /\ (always (enterText \/ addNew \/ changeFilter))
    }
  where
    init = isEmpty
    enterText =
      neg (pendingText === next pendingText)
        /\ itemTexts === next itemTexts
    changeFilter =
      neg (currentFilter === next currentFilter)
        /\ filterIs (Just All) ==> (numItems >= next numItems)
        /\ pendingText === next pendingText
    addNew =
      pendingText === next lastItemText
        /\ next ((== Nothing) <$> pendingText)

data Filter = All | Active | Completed
  deriving (Eq, Read, Show)

-- * State helpers:

isEmpty :: Proposition
isEmpty = filterIs Nothing /\ (null <$> items) /\ ((== Just "") <$> pendingText)

currentFilter :: Formula (Maybe Filter)
currentFilter = query ((>>= (readMaybe . Text.unpack)) <$> (traverse text =<< one ".todoapp .filters .selected"))

filterIs :: Maybe Filter -> Proposition
filterIs f = (== f) <$> currentFilter

items :: Formula [Element]
items = query (all ".todo-list li")

itemTexts :: Formula [Text]
itemTexts = query (traverse text =<< all ".todo-list li label")

lastItemText :: Formula (Maybe Text)
lastItemText = lastOf traverse <$> itemTexts

numItems :: Formula Int
numItems = lengthOf traverse <$> items

pendingText :: Formula (Maybe Text)
pendingText = inputValue ".new-todo"
