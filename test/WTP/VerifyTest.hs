{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module WTP.VerifyTest where

import Algebra.Lattice (bottom, top)
import qualified Data.Aeson as JSON
import qualified Data.HashMap.Strict as HashMap
import Data.Text (Text)
import Test.Tasty.Hspec
import WTP.Element
import WTP.Formula.Syntax
import WTP.Result
import qualified WTP.Trace as Trace
import WTP.Verify
import Prelude hiding (Bool (..), all, map, seq)
import Data.Maybe (fromMaybe)


spec_verify' :: Spec
spec_verify' = do
  let verify' = flip verify
  describe "verify'" $ do
    it "verifies with get and assertion" $ do
      let classList = JSON.toJSON ["foo", "bar" :: Text]
      verify'
        (_exists (query (qtraverse (property "classList") (all "#some-element"))) (\c -> c === json classList))
        [ Trace.ObservedState
            (HashMap.singleton "#some-element" [Element "a"])
            ( HashMap.singleton
                (Element "a")
                [Trace.ElementStateValue (Property "classList") classList]
            )
        ]
        `shouldBe` Accepted
    it "verifies with get and satisfy" $ do
      verify'
        ((length <$> query (all "p")) === num 2)
        [Trace.ObservedState (HashMap.singleton "p" [Element "a", Element "b"]) mempty]
        `shouldBe` Accepted
    it "is top with (top /\\ top)" $ do
      verify' (top /\ top) [Trace.ObservedState HashMap.empty mempty] `shouldBe` Accepted
    it "is top with (neg bottom)" $ do
      verify' (neg bottom) [Trace.ObservedState HashMap.empty mempty] `shouldBe` Accepted
    it "verifies button example" $ do
      let steps =
            [ Trace.ObservedState mempty mempty,
              Trace.ObservedState
                ( HashMap.fromList
                    [ (Selector ".message", [Element "f93eb8a0-3511-4a79-8cdf-eef9a8beb5b6"]),
                      (Selector "button", [Element "7485ccda-3534-4f9d-9e0e-7bfccdf70abd"])
                    ]
                )
                ( HashMap.fromList
                    [ (Element "7485ccda-3534-4f9d-9e0e-7bfccdf70abd", [Trace.ElementStateValue Enabled top]),
                      (Element "f93eb8a0-3511-4a79-8cdf-eef9a8beb5b6", [Trace.ElementStateValue Text ""])
                    ]
                ),
              Trace.ObservedState
                ( HashMap.fromList
                    [ (Selector ".message", [Element "f93eb8a0-3511-4a79-8cdf-eef9a8beb5b6"]),
                      (Selector "button", [Element "7485ccda-3534-4f9d-9e0e-7bfccdf70abd"])
                    ]
                )
                ( HashMap.fromList
                    [ (Element "7485ccda-3534-4f9d-9e0e-7bfccdf70abd", [Trace.ElementStateValue Enabled top]),
                      (Element "f93eb8a0-3511-4a79-8cdf-eef9a8beb5b6", [Trace.ElementStateValue Text "Boom!"])
                    ]
                )
            ]
      let buttonIsEnabled = fromMaybe bottom <$> query (qtraverse enabled (one "button"))
          messageIs message = query (qtraverse text (one ".message")) === (Just <$> message)
          prop =
            buttonIsEnabled
              \/ always (messageIs "Boom!" /\ buttonIsEnabled)
      verify' prop steps `shouldBe` Accepted
