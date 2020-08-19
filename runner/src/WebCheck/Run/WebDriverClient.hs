{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE OverloadedStrings #-}

module WebCheck.Run.WebDriverClient where

import Control.Monad (Monad (fail))
import Protolude
import qualified Test.WebDriver as WebDriver
import WebCheck.Element
import WebCheck.LogLevel
import WebCheck.Run

newtype WebDriverClient a = WebDriverClient {unWebDriverClient :: WebDriver.WD a}
  deriving (Functor, Applicative, Monad, MonadIO)

instance WebDriver WebDriverClient where
  getActiveElement = fromRef <$> WebDriverClient WebDriver.activeElem
  isElementEnabled = WebDriverClient . WebDriver.isEnabled . toRef
  getElementTagName = map toS . WebDriverClient . WebDriver.tagName . toRef
  elementClick = WebDriverClient . WebDriver.click . toRef
  elementSendKeys keys = WebDriverClient . WebDriver.sendKeys (toS keys) . toRef
  findAll (Selector s) = map fromRef <$> WebDriverClient (WebDriver.findElems (WebDriver.ByCSS s))
  navigateTo = WebDriverClient . WebDriver.openPage . toS
  runScript script args = do
    r <- WebDriverClient (WebDriver.asyncJS (map WebDriver.JSArg args) script)
    case r of
      Just (Right a) -> pure a
      Just (Left e) -> liftIO (fail e)
      Nothing -> liftIO (fail "Script timed out")
  inNewPrivateWindow CheckOptions {checkWebDriverLogLevel} (WebDriverClient action) =
    WebDriverClient $ do
      caps <- WebDriver.getActualCaps
      WebDriver.finallyClose (WebDriver.createSession (reconfigure caps) >> action)
    where
      reconfigure c =
        c
          { WebDriver.webStorageEnabled = Just False,
            WebDriver.browser =
              WebDriver.Firefox
                { WebDriver.ffProfile = Nothing,
                  WebDriver.ffLogPref = webdriverLogLevel checkWebDriverLogLevel,
                  WebDriver.ffBinary = Nothing,
                  WebDriver.ffAcceptInsecureCerts = Just False
                }
          }
      webdriverLogLevel = \case
        LogDebug -> WebDriver.LogDebug
        LogInfo -> WebDriver.LogInfo
        LogWarn -> WebDriver.LogWarning
        LogError -> WebDriver.LogSevere

runWebDriver :: MonadIO m => WebDriverClient b -> m b
runWebDriver (WebDriverClient ma) =
  liftIO (WebDriver.runSession (reconfigure WebDriver.defaultConfig) ma)
  where
    reconfigure = WebDriver.useBrowser WebDriver.firefox

toRef :: Element -> WebDriver.Element
toRef (Element ref) = WebDriver.Element ref

fromRef :: WebDriver.Element -> Element
fromRef (WebDriver.Element ref) = Element ref
