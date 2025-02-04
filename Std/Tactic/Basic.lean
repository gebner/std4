/-
Copyright (c) 2021 Mario Carneiro. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Mario Carneiro
-/
import Std.Tactic.NoMatch
import Std.Tactic.GuardExpr
import Lean.Elab.Tactic.ElabTerm

open Lean Parser.Tactic Elab Command Elab.Tactic Meta

/-- `exfalso` converts a goal `⊢ tgt` into `⊢ False` by applying `False.elim`. -/
macro "exfalso" : tactic => `(apply False.elim)

/--
`_` in tactic position acts like the `done` tactic: it fails and gives the list
of goals if there are any. It is useful as a placeholder after starting a tactic block
such as `by _` to make it syntactically correct and show the current goal.
-/
macro "_" : tactic => `({})

/-- We allow the `rfl` tactic to also use `Iff.rfl`. -/
-- `rfl` was defined earlier in Lean4, at src/Lean/Init/Tactics.lean
-- Later we want to allow `rfl` to use all relations marked with an attribute.
macro_rules | `(tactic| rfl) => `(tactic| exact Iff.rfl)

/-- `rwa` calls `rw`, then closes any remaining goals using `assumption`. -/
macro "rwa " rws:rwRuleSeq loc:(location)? : tactic =>
  `(tactic| rw $rws:rwRuleSeq $[$loc:location]?; assumption)

/--
`by_cases h : p` makes a case distinction on `p`,
resulting in two subgoals `h : p ⊢` and `h : ¬ p ⊢`.
-/
macro "by_cases " h:ident ":" e:term : tactic =>
  `(cases Decidable.em $e with | inl $h => ?pos | inr $h => ?neg)

/--
Like `exact`, but takes a list of terms and checks that all goals are discharged after the tactic.
-/
elab (name := exacts) "exacts" "[" hs:term,* "]" : tactic => do
  for stx in hs.getElems do
    evalTactic (← `(tactic| exact $stx))
  evalTactic (← `(tactic| done))

/--
`by_contra h` proves `⊢ p` by contradiction,
introducing a hypothesis `h : ¬p` and proving `False`.
* If `p` is a negation `¬q`, `h : q` will be introduced instead of `¬¬q`.
* If `p` is decidable, it uses `Decidable.byContradiction` instead of `Classical.byContradiction`.
* If `h` is omitted, the introduced variable `_: ¬p` will be anonymous.
-/
syntax (name := byContra) "by_contra" (ppSpace colGt ident)? : tactic
macro_rules
  | `(tactic| by_contra) => `(tactic| (guard_target = Not _; intro))
  | `(tactic| by_contra $e) => `(tactic| (guard_target = Not _; intro $e:ident))
macro_rules
  | `(tactic| by_contra) => `(tactic| (apply Decidable.byContradiction; intro))
  | `(tactic| by_contra $e) => `(tactic| (apply Decidable.byContradiction; intro $e:ident))
macro_rules
  | `(tactic| by_contra) => `(tactic| (apply Classical.byContradiction; intro))
  | `(tactic| by_contra $e) => `(tactic| (apply Classical.byContradiction; intro $e:ident))

/--
`iterate n tac` runs `tac` exactly `n` times.
`iterate tac` runs `tac` repeatedly until failure.

To run multiple tactics, one can do `iterate (tac₁; tac₂; ⋯)` or
```lean
iterate
  tac₁
  tac₂
  ⋯
```
-/
syntax "iterate" (ppSpace num)? ppSpace tacticSeq : tactic
macro_rules
  | `(tactic|iterate $seq:tacticSeq) =>
    `(tactic|try ($seq:tacticSeq); iterate $seq:tacticSeq)
  | `(tactic|iterate $n $seq:tacticSeq) =>
    match n.1.toNat with
    | 0 => `(tactic| skip)
    | n+1 => `(tactic|($seq:tacticSeq); iterate $(quote n) $seq:tacticSeq)

private partial def repeat'Aux (seq : Syntax) : List MVarId → TacticM Unit
| []    => pure ()
| g::gs =>
  try
    let subgs ← evalTacticAt seq g
    appendGoals subgs
    repeat'Aux seq (subgs ++ gs)
  catch _ =>
    repeat'Aux seq gs

/--
`repeat' seq` runs `seq` on all of the goals to produce a new list of goals,
then runs `seq` again on all of those goals, and repeats until all goals are closed.
-/
elab "repeat' " seq:tacticSeq : tactic => do repeat'Aux seq (← getGoals)

/--
`fapply e` is like `apply e` but it adds goals in the order they appear,
rather than putting the dependent goals first.
-/
elab "fapply " e:term : tactic =>
  evalApplyLikeTactic (·.apply (cfg := {newGoals := .all})) e

/--
`eapply e` is like `apply e` but it does not add subgoals for variables that appear
in the types of other goals. Note that this can lead to a failure where there are
no goals remaining but there are still metavariables in the term:
```
example (h : ∀ x : Nat, x = x → True) : True := by
  eapply h
  rfl
  -- no goals
-- (kernel) declaration has metavariables '_example'
```
-/
elab "eapply " e:term : tactic =>
  evalApplyLikeTactic (·.apply (cfg := {newGoals := .nonDependentOnly})) e

/--
Tries to solve the goal using a canonical proof of `True`, or the `rfl` tactic.
Unlike `trivial` or `trivial'`, does not use the `contradiction` tactic.
-/
macro (name := triv) "triv" : tactic =>
  `(tactic| first | exact trivial | rfl | fail "triv tactic failed")
