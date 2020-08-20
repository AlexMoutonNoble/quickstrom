{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

module Quickstrom.TraceTest where

import Control.Lens
import Test.QuickCheck ((===), Property, forAll)
import qualified Quickstrom.Gen as Gen
import Quickstrom.Prelude
import Quickstrom.Trace

prop_all_empty_are_stuttering :: Property
prop_all_empty_are_stuttering = forAll Gen.trace $ \t -> do
  let t' = t & observedStates .~ mempty
  (t' ^. observedStates) === (withoutStutterStates (annotateStutteringSteps t') ^. observedStates)
