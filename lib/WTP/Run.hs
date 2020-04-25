{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module WTP.Run
  ( testSpecifications,
  )
where

import Control.Lens
import Control.Monad ((>=>), replicateM, void)
import qualified Control.Monad.Freer as Eff
import Control.Monad.Freer (Eff)
import Control.Applicative ((<|>))
import Control.Monad.Freer.Writer (Writer, runWriter, tell)
import Control.Monad.Loops (unfoldM, takeWhileM)
import Control.Monad.State (StateT (runStateT))
import Control.Monad.Trans.Class (MonadTrans)
import Control.Monad.Trans.Class (MonadTrans (lift))
import Control.Monad.Trans.Identity (IdentityT)
import Control.Natural (type (~>))
import Data.Bifunctor (Bifunctor (bimap))
import Data.Either (partitionEithers)
import Data.Function ((&))
import Data.Generics.Product (field)
import qualified Data.HashMap.Strict as HashMap
import Data.HashMap.Strict (HashMap)
import Data.Hashable (Hashable)
import Data.List (subsequences, nub)
import Data.List.NonEmpty (nonEmpty, NonEmpty ((:|)))
import Data.Maybe (catMaybes, fromMaybe, listToMaybe)
import Data.String (IsString (..))
import qualified Data.Text as Text
import Data.Text (Text)
import Data.Text.Prettyprint.Doc
import Data.Text.Prettyprint.Doc.Render.Terminal
import qualified Debug.Trace as Debug
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr, stdout)
import System.Random (StdGen, getStdGen, mkStdGen)
import qualified Test.QuickCheck as QuickCheck
import qualified Test.QuickCheck.Gen as QuickCheck
import qualified Test.QuickCheck.Monadic as QuickCheck
import qualified Test.Tasty as Tasty
import Test.Tasty.HUnit (assertFailure, testCase)
import qualified WTP.Formula.NNF as NNF
import qualified WTP.Formula.Syntax as Syntax
import WTP.Query
import WTP.Result
import WTP.Specification
import WTP.Trace
import Web.Api.WebDriver hiding (Action, Selector, assertFailure, runIsolated, hPutStrLn)
import Control.Monad.IO.Class (MonadIO(liftIO))
import qualified Data.List.NonEmpty as NonEmpty
import Data.Maybe (mapMaybe)

type Generator = StateT StdGen (WebDriverTT IdentityT IO)

type Runner = WebDriverTT IdentityT IO

testSpecifications :: [(Text, Specification Syntax.Formula)] -> Tasty.TestTree
testSpecifications specs =
  Tasty.testGroup "WTP specifications" [testCase (Text.unpack name) (test spec) | (name, spec) <- specs]

test :: Specification Syntax.Formula -> IO ()
test spec = do
  stdGen <- getStdGen
  testResult <- runWD $ do
    (actions, _) <- runStateT (genActions spec' 10) stdGen
    original@(trace, result) <- runAndVerify spec' actions
    case result of
      Accepted -> pure original
      Rejected -> fromMaybe original <$> shrinkFailing spec' actions
  case testResult of
    (trace, Rejected) -> renderFailureAndExit trace
    _ -> hPutStrLn stderr "Tests passed."
  where
    renderFailureAndExit trace = do
      renderIO stderr (layoutPretty defaultLayoutOptions (prettyTrace (annotateStutteringSteps trace) <> line))
      assertFailure ("Tests failed with trace of length: " <> show (length (trace ^. traceElements)))
    runWD = runWebDriver . runIsolated headlessFirefoxCapabilities
    spec' = spec & field @"property" %~ Syntax.toNNF

shrinkFailing :: Specification NNF.Formula -> [Action Selected] -> Runner (Maybe (Trace (), Result))
shrinkFailing spec original = go (shrink original)
  where 
    go = \case
      [] -> pure Nothing
      ([] : rest) -> go rest
      (actions : rest) ->
        runAndVerify spec actions >>= \case
          (trace, Accepted) -> go rest
          (trace, Rejected) -> (<|> Just (trace, Rejected)) <$> shrinkFailing spec actions
    shrink = QuickCheck.shrinkList (const []) 

runAndVerify :: Specification NNF.Formula -> [Action Selected] -> Runner (Trace (), Result)
runAndVerify spec actions = do
  let verify trace = NNF.verifyWith assertQuery (property spec) (trace ^.. observedStates)
  trace <- runActions spec actions
  pure (trace, verify trace)

-- TODO?
shrinkAction :: Action sel -> [Action sel]
shrinkAction = const []

validActions :: [Action Selector] -> Generator (Maybe (QuickCheck.Gen (Action Selected)))
validActions actions = do
  gens <- catMaybes <$> traverse tryGenAction actions
  case gens of
    [] -> pure Nothing
    _ -> pure (Just (QuickCheck.oneof gens))
  where
    tryGenAction :: Action Selector -> Generator (Maybe (QuickCheck.Gen (Action Selected)))
    tryGenAction = \case
      KeyPress k -> pure (Just (pure (KeyPress k)))
      Navigate p -> pure (Just (pure (Navigate p)))
      Focus sel -> selectOne sel Focus
      Click sel -> selectOne sel Click
    selectOne :: Selector -> (Selected -> Action Selected) -> Generator (Maybe (QuickCheck.Gen (Action Selected)))
    selectOne sel ctor = lift (findAll sel) >>= \case
      [] -> pure Nothing
      els -> pure (Just (ctor . Selected sel <$> QuickCheck.elements [0..pred (length els)]))

genActions :: Specification NNF.Formula -> Int -> Generator [Action Selected]
genActions spec maxNum = do
  lift (navigateToOrigin spec)
  go []
  where
    go acc
      | length acc < maxNum = do
        validActions (actions spec) >>= \case
          Just genValidAction ->  do
            next <- lift (liftWebDriverTT (lift (QuickCheck.generate genValidAction)))
            lift (runAction next)
            go (acc <> [next])
          Nothing -> pure acc
      | otherwise = pure acc

navigateToOrigin :: (Monad eff, Monad (t eff), MonadTrans t) => Specification formula -> WebDriverTT t eff ()
navigateToOrigin spec = case origin spec of
  Path path -> navigateTo (Text.unpack path)

runActions :: Specification NNF.Formula -> [Action Selected] -> WebDriverT IO (Trace ())
runActions spec actions = do
  -- lift breakpointsOn
  navigateToOrigin spec
  initial <- observe
  rest <- concat <$> traverse runActionAndObserve actions
  pure (Trace (initial : rest))
  where
    queries = NNF.withQueries runQuery (property spec)
    runActionAndObserve action = do
      runAction action
      s <- observe
      pure [TraceAction () action, s]
    observe = do
      values <- Eff.runM queries
      let (queriedElements, elementStates) =
            bimap groupUniqueIntoMap groupUniqueIntoMap (partitionEithers (concat values))
      pure (TraceState () (ObservedState {queriedElements, elementStates}))

try :: WebDriverT IO () -> Runner ()
try action = (action `catchError` (const (pure ())))

click :: Selected -> Runner ()
click = findSelected >=> (\e -> try (void (elementClick e)))

sendKey :: Char -> Runner ()
sendKey c = try (getActiveElement >>= elementSendKeys [c])

focus :: Selected -> Runner ()
focus  = findSelected >=> (\e -> try (void (elementSendKeys "" e)))

runAction :: Action Selected -> Runner ()
runAction = \case
  Focus s -> focus s
  KeyPress c -> sendKey c
  Click s -> click s
  Navigate (Path path) -> try (navigateTo (Text.unpack path))

runWebDriver :: WebDriverT IO a -> IO a
runWebDriver ma =
  execWebDriverT (reconfigure defaultWebDriverConfig) ma >>= \case
    (Right x, _, _) -> pure x
    (Left err, _, _) -> fail (show err)
  where
    reconfigure c =
      c
        { _environment =
            (_environment c)
              { _logEntryPrinter = \_ _ -> Nothing
              }
        }

-- | Mostly the same as the non-exported definition in 'Web.Api.WebDriver.Endpoints'.
runIsolated ::
  (Monad eff, Monad (t eff), MonadTrans t) =>
  Capabilities ->
  WebDriverTT t eff a ->
  WebDriverTT t eff a
runIsolated caps theSession = cleanupOnError $ do
  sid <- newSession caps
  modifyState (setSessionId (Just sid))
  a <- theSession
  deleteSession
  modifyState (setSessionId Nothing)
  pure a

-- | Same as the non-exported definition in 'Web.Api.WebDriver.Endpoints'.
cleanupOnError ::
  (Monad eff, Monad (t eff), MonadTrans t) =>
  -- | `WebDriver` session that may throw errors
  WebDriverTT t eff a ->
  WebDriverTT t eff a
cleanupOnError x =
  catchAnyError
    x
    (\e -> deleteSession >> throwError e)
    (\e -> deleteSession >> throwHttpException e)
    (\e -> deleteSession >> throwIOException e)
    (\e -> deleteSession >> throwJsonError e)

-- | Same as the non-exported definition in 'Web.Api.WebDriver.Endpoints'.
setSessionId ::
  Maybe String ->
  S WDState ->
  S WDState
setSessionId x st = st {_userState = (_userState st) {_sessionId = x}}

findMaybe :: Selector -> Runner (Maybe ElementRef)
findMaybe = fmap listToMaybe . findAll

findSelected :: Selected -> Runner ElementRef
findSelected (Selected s i) = fmap (!! i) (findAll s)

findAll :: Selector -> Runner [ElementRef]
findAll (Selector s) = (findElements CssSelector (Text.unpack s))

toRef :: Element -> ElementRef
toRef (Element ref) = ElementRef (Text.unpack ref)

fromRef :: ElementRef -> Element
fromRef (ElementRef ref) = Element (Text.pack ref)

groupUniqueIntoMap :: (Eq a, Hashable a, Eq b) => [(a, b)] -> HashMap a [b]
groupUniqueIntoMap = HashMap.map nub . HashMap.fromListWith (++) . map (\(k, v) -> (k, [v]))

type QueriedElement = (Selector, Element)

type QueriedElementState = (Element, ElementStateValue)

runQuery :: Eff '[Query] a -> Eff '[Runner] [Either QueriedElement QueriedElementState]
runQuery query' =
  fmap snd
    $ runWriter
    $ Eff.reinterpret2 go query'
  where
    go :: Query ~> Eff '[Writer [Either (Selector, Element) (Element, ElementStateValue)], Runner]
    go =
      ( \case
          Query selector -> do
            el <- fmap fromRef <$> Eff.sendM (findMaybe selector)
            case el of
              Just el' -> tell [Left (selector, el') :: Either QueriedElement QueriedElementState]
              Nothing -> pure ()
            pure el
          QueryAll selector -> do
            els <- fmap fromRef <$> Eff.sendM (findAll selector)
            tell ((Left . (selector,) <$> els) :: [Either QueriedElement QueriedElementState])
            pure [Element "a"]
          Get state el -> do
            value <- Eff.sendM $ case state of
              Attribute name -> fmap Text.pack <$> (getElementAttribute (Text.unpack name) (toRef el))
              Property name -> (getElementProperty (Text.unpack name) (toRef el))
              CssValue name -> Text.pack <$> (getElementCssValue (Text.unpack name) (toRef el))
              Text -> Text.pack <$> (getElementText (toRef el))
              Enabled -> (isElementEnabled (toRef el))
            tell [Right (el, ElementStateValue state value) :: Either QueriedElement QueriedElementState]
            pure value
      )
{-
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

-}
