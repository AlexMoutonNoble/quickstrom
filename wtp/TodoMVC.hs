{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedLists #-}

module TodoMVC
  ( spec,
  )
where

import Data.Text (Text)
import Helpers
import qualified Test.QuickCheck as QuickCheck
import WebCheck.Specification
import WebCheck.Syntax
import Prelude hiding ((<), (<=), (>), (>=), all, filter, head, init, last, length, null, not)

spec :: Text -> Specification Formula
spec name =
  Specification
    { origin = Path ("http://todomvc.com/examples/" <> name <> "/"),
      readyWhen = ".todoapp",
      actions =
        QuickCheck.frequency
          [ (5, pure (KeyPress 'a')),
            (5, specialKeyPress (pure KeyEnter)),
            (5, pure (Focus ".todoapp .new-todo")),
            (5, pure (Click ".todoapp .filters a:not(.selected)")),
            (1, pure (Click ".todoapp .filters a.selected")),
            (1, pure (Click ".todoapp label[for=toggle-all]")),
            (1, pure (Click ".todoapp .destroy"))
          ],
      proposition = initial /\ (always (enterText \/ addNew \/ changeFilter \/ toggleAll))
    }
  where
    initial =
      (currentFilter === null \/ currentFilter === "All")
        /\ (numItems === num 0)
        /\ (pendingText === "" \/ pendingText === null)
    enterText =
      pendingText /== next pendingText
        /\ itemTexts === next itemTexts
        /\ currentFilter === next currentFilter
    changeFilter =
      currentFilter /== next currentFilter
        /\ (currentFilter === "All") ==> (numItems >= next numItems)
        /\ ( next
               ( (currentFilter === "Active")
                   ==> ( numItemsLeft === numUnchecked
                           /\ numItems === numUnchecked
                       )
               )
           )
        -- NOTE: AngularJS and Mithril implementations are
        -- inconsistent with the other JS implementations, in that
        -- they clear the input field when the filter is changed.
        /\ neg (apply in' [string name, [string "angularjs", string "mithril"]]) ==> pendingText === next pendingText
    addNew =
      pendingText === next lastItemText
        /\ next (pendingText === "")
    toggleAll =
      pendingText === next lastItemText
        /\ currentFilter === next currentFilter
        /\ ( (currentFilter === "All")
               ==> numItems === next numItems /\ next (numItems === numChecked)
           )
        /\ ( (currentFilter === "Active")
               ==> ( numItems > num 0 ==> next numItems === num 0
                       \/ (numItems === num 0) ==> next numItems > num 0
                   )
           )

-- * State helpers:

currentFilter :: Formula
currentFilter = queryOne (text (byCss ".todoapp .filters .selected"))

items :: Formula
items = queryAll (byCss ".todo-list li")

itemTexts :: Formula
itemTexts = queryAll (text (byCss ".todo-list li label"))

lastItemText :: Formula
lastItemText = apply last [itemTexts]

numItems :: Formula
numItems = apply length [items]

checked :: Formula
checked = queryAll (property "checked" (byCss ".todo-list li input[type=checkbox]"))

numUnchecked :: Formula
numUnchecked = apply length [apply filter [not, checked]]

numChecked :: Formula
numChecked = apply length [apply filter [identity, checked]]

pendingText :: Formula
pendingText = inputValue ".new-todo"

numItemsLeft :: Formula
numItemsLeft =
  let strs = queryOne (text (byCss ".todoapp .todo-count strong"))
  in apply parseNumber [apply head [apply splitOn [" ", strs]]]
