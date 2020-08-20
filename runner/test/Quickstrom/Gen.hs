{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module Quickstrom.Gen where

import qualified Data.List.NonEmpty as NonEmpty
import Data.Maybe (fromMaybe)
import qualified Data.Text as Text
import Data.Text (Text)
import Test.QuickCheck hiding ((===), (==>))
import Quickstrom.Element
import Quickstrom.Trace hiding (observedStates)
import Prelude hiding (Bool (..))

selector :: Gen Selector
selector = elements (map (Selector . Text.singleton) ['a' .. 'c'])

selected :: Gen Selected
selected = Selected <$> selector <*> choose (0, 3)

stringValues :: Gen Text
stringValues = elements ["s1", "s2", "s3"]

observedState :: Gen ObservedState
observedState = ObservedState <$> pure mempty

selectedAction :: Gen (Action Selected)
selectedAction =
  oneof
    [ Focus <$> selected,
      KeyPress <$> elements ['A' .. 'C'],
      Click <$> selected
    ]

actionResult :: Gen ActionResult
actionResult = oneof [pure ActionSuccess, pure (ActionFailed "failed"), pure ActionImpossible]

traceElement :: Gen (TraceElement ())
traceElement =
  oneof
    [ TraceAction () <$> selectedAction <*> actionResult,
      TraceState () <$> observedState
    ]

trace :: Gen (Trace ())
trace = Trace <$> listOf traceElement

nonEmpty :: Gen [a] -> Gen (NonEmpty.NonEmpty a)
nonEmpty g = fromMaybe discard . NonEmpty.nonEmpty <$> g
