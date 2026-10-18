-- ABOUTME: Inspect transitive axiom dependencies in the compiled project environment.
-- ABOUTME: Reject unproved assumptions including sorryAx and native decision axioms.
import LeanForStandardization
import LeanForStandardization.HappyEyeballs.Tests
import LeanForStandardization.ERC8004.Tests
import Lean

open Lean Elab Command

run_cmd do
  let env ← getEnv
  let requiredTheorems := #[
      `LeanForStandardization.HappyEyeballs.all_traces_spaced,
      `LeanForStandardization.HappyEyeballs.all_traces_tls_safe,
      `LeanForStandardization.HappyEyeballs.run_winner_stable,
      `LeanForStandardization.HappyEyeballs.run_no_start_after_winner,
      `LeanForStandardization.ERC8004.transfer_clears_wallet_and_approval,
      `LeanForStandardization.ERC8004.transfer_revokes_unapproved_authority,
      `LeanForStandardization.ERC8004.accepted_feedback_excludes_authority,
      `LeanForStandardization.ERC8004.request_requires_authority,
      `LeanForStandardization.ERC8004.response_requires_designated_validator,
      `LeanForStandardization.ERC8004.rejection_preserves_state]
  for required in requiredTheorems do
    match env.find? required with
    | some (.thmInfo _) => pure ()
    | _ => throwError "Required theorem is missing: {required}"
  let mut checked : Nat := 0
  let mut theorems : Nat := 0
  for (name, info) in env.constants.toList do
    if (`LeanForStandardization).isPrefixOf (privateToUserName name) then
      checked := checked + 1
      let axioms ← collectAxioms name
      for axiomName in axioms do
        unless #[`propext, `Classical.choice, `Quot.sound].contains axiomName do
          throwError "Unapproved axiom {axiomName} in transitive dependencies of {name}"
      if let .thmInfo _ := info then
        theorems := theorems + 1
        if requiredTheorems.contains name then
          logInfo m!"{name}: {axioms}"
  if theorems < 4 then
    throwError "Expected at least four project theorems; found {theorems}"
  logInfo m!"Audited {checked} declarations and {theorems} theorem declarations (including generated lemmas)."
