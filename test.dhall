let Language = ./lib/WTP/Language.dhall

in  { actions = [ Language.Action.Click { selector = ".my-app form submit" } ]
    , formula =
        Language.withOperators
          (   λ(Formula : Type)
            → λ(op : Language.Operators Formula)
            → op.until
                (op.`if` op.false op.true)
                (op.or op.true op.false)
          )
    }
