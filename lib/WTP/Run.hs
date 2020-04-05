{-# LANGUAGE OverloadedStrings #-}
module WTP.Run (run) where

import Control.Monad (void)
import qualified Data.Text as Text
import qualified Data.HashMap.Strict       as HashMap
import qualified Data.Aeson as JSON
import Web.Api.WebDriver
import WTP.Property
import WTP.Verify
import WTP.Core

run :: Property Formula -> WebDriverT IO [Step]
run property = traverse go (actions property)
  where
    find' (Selector s) = findElement CssSelector (Text.unpack s)
    go action = do
      case action of
        Focus s ->
          find' s >>= elementSendKeys ""
        KeyPress c ->
          getActiveElement >>= elementSendKeys [c]
        Click s ->
          find' s >>= elementClick
        Navigate (Path path) -> navigateTo (Text.unpack path)
      pure (Step {queriedElements = HashMap.empty})

myWait :: Int -> WebDriverT IO ()
myWait ms =
  void
    ( executeAsyncScript
        " var ms = arguments[0]; \
        \ var done = arguments[1]; \
        \ setTimeout(done, ms) \
        \"
        [JSON.toJSON ms]
    )
