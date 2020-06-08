{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TupleSections #-}

module WebCheck.Specification where

import Data.HashMap.Strict (HashMap)
import Data.HashSet (HashSet)
import Data.Text.Prettyprint.Doc (Doc)
import Data.Text.Prettyprint.Doc.Render.Terminal (AnsiStyle)
import Test.QuickCheck (Gen)
import WebCheck.Element
import WebCheck.Path
import WebCheck.Result
import WebCheck.Trace

type ActionGenerator = Gen (Action Selector)

type Queries = HashMap Selector (HashSet ElementState)

class Specification s where
  origin :: s -> Path
  readyWhen :: s -> Selector
  actions :: s -> ActionGenerator
  queries :: s -> Queries
  verify :: s -> [ObservedState] -> Either (Doc ann) Result
