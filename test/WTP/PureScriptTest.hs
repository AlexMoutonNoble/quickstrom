{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedLists #-}
module WTP.PureScriptTest where

import Protolude
import Control.Lens
import Test.Tasty.Hspec hiding (Selector)
import WTP.PureScript
import WTP.PureScript.Value
import Language.PureScript (Ident, Qualified, nullSourceSpan)
import Language.PureScript.CoreFn
import Data.Vector (Vector)
import Data.Text.Prettyprint.Doc (defaultLayoutOptions, layoutPretty, Pretty(pretty))
import Data.Text.Prettyprint.Doc.Render.Text (renderStrict)

eval' :: Expr EvalAnn -> Either EvalError (Value EvalAnn)
eval' = runEval . eval initialEnv

envLookupExpr :: Qualified Ident -> Eval (Expr EvalAnn)
envLookupExpr qn =
   case envLookup qn initialEnv of
       Just (Left expr) -> pure expr
       _ -> throwError (NotInScope nullSourceSpan qn)


spec_purescript = do
  it "adds integers" $ do
    let r = runEval $ do
        intAdd <- envLookupExpr (qualifiedName ["Data", "Semiring"] "intAdd")
        eval initialEnv (app (app intAdd (intLit 1)) (intLit 2))
    r `shouldSatisfy` \case
       Right (VInt 3) -> True
       _ -> False
  it "maps over array" $ do
    let r :: Either EvalError (Value EvalAnn)
        r = runEval $ do
                arrayMap <- envLookupExpr (qualifiedName ["Data", "Functor"] "arrayMap")
                intAdd <- envLookupExpr (qualifiedName ["Data", "Semiring"] "intAdd")
                let incr = app intAdd (intLit 1)
                let incrAll = (app arrayMap incr)
                -- traceShowM (const () <$> incrAll)
                eval initialEnv (app incrAll (arrayLit [intLit 1, intLit 2, intLit 3]))
    prettyText (either pretty pretty r) `shouldBe` "[2, 3, 4]"


nullAnn = (EvalAnn nullSourceSpan Nothing)

app = App nullAnn

intLit n = Literal nullAnn (NumericLiteral (Left n))

arrayLit xs = Literal nullAnn (ArrayLiteral xs)

prettyText x = renderStrict (layoutPretty defaultLayoutOptions x)