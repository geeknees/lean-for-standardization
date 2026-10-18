-- ABOUTME: Exercises ownership changes, authorization, numeric boundaries, and validation races.
-- ABOUTME: Enumerates short operation sequences and checks observations independently of proof tactics.
import LeanForStandardization.ERC8004.Properties

namespace LeanForStandardization.ERC8004

private def check (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw (IO.userError s!"ERC-8004: {message}")

def transferScenario : List Operation := [
  .register 1, .approve 1 0 (some 2), .setWallet 2 0 7 true,
  .transfer 2 0 3, .setWallet 2 0 9 true, .feedback 2 0 100 0]

def validationScenario : List Operation := [
  .register 1, .request 2 0 3 5, .approve 1 0 (some 2), .request 2 0 3 5,
  .request 1 0 4 5, .respond 4 5 100, .respond 3 5 101,
  .respond 3 5 0, .transfer 1 0 4, .respond 3 5 100]

def valueCapWitness : List Operation := [
  .register 1, .feedback 2 0 (10 ^ 38 + 1) 0]

def formerOwnerScenario : List Operation := [
  .register 1, .transfer 1 0 2, .feedback 1 0 100 0]

private def hasFormerOwnerFeedback (pastOwners : List (AgentId × Address))
    (s : State) : List Operation → Bool
  | [] => false
  | op :: rest =>
    let t := step s op
    match op, t.outcome with
    | .transfer _ id _, .accepted =>
      let past := match s.agents id with
        | none => pastOwners
        | some a => (id, a.owner) :: pastOwners
      hasFormerOwnerFeedback past t.state rest
    | .feedback caller id _ _, .accepted =>
      pastOwners.contains (id, caller) || hasFormerOwnerFeedback pastOwners t.state rest
    | _, _ => hasFormerOwnerFeedback pastOwners t.state rest

private def sequences (alphabet : List Operation) : Nat → List (List Operation)
  | 0 => [[]]
  | n + 1 => alphabet.flatMap fun op => (sequences alphabet n).map (op :: ·)

private def checkTransition (s : State) (op : Operation) : IO Unit := do
  let t := step s op
  match t.outcome with
  | .rejected _ =>
    check (t.events == []) "rejection emitted events"
    check (t.state.nextAgent == s.nextAgent && t.state.feedback == s.feedback &&
      t.state.requestHashes == s.requestHashes) "rejection changed counters or histories"
    for id in List.range (s.nextAgent + 1) do
      check (t.state.agents id == s.agents id) "rejection changed an agent"
    for hash in [0, 1, 2, 3, 5] do
      check (t.state.validations hash == s.validations hash) "rejection changed a validation"
  | .accepted =>
    match op with
    | .transfer _ id newOwner =>
      check (t.state.agents id == some { owner := newOwner, wallet := none, approved := none })
        "transfer retained wallet or token approval"
    | .feedback caller id _ _ =>
      match s.agents id with
      | none => check false "feedback accepted for unknown agent"
      | some a => check (decide (¬ authorized s a caller)) "self-feedback accepted"
    | .respond caller hash response =>
      match s.validations hash with
      | none => check false "response accepted for unknown request"
      | some v => check (caller == v.validator && response ≤ 100) "invalid response accepted"
    | _ => pure ()

private def enumerate (alphabet : List Operation) (remaining : Nat) (s : State) : IO Nat := do
  match remaining with
  | 0 => return 0
  | n + 1 =>
    let mut count := 0
    for op in alphabet do
      checkTransition s op
      count := count + 1 + (← enumerate alphabet n (step s op).state)
    return count

def runTests : IO Unit := do
  let afterTransfer := run initial transferScenario
  check (afterTransfer.agents 0 == some { owner := 3, wallet := none }) "transfer cleanup"
  check (afterTransfer.feedback.length == 1) "former operator should be eligible for feedback"
  let transferOutcomes := (trace initial transferScenario).map (·.outcome)
  check (transferOutcomes[4]? == some (.rejected .unauthorized)) "stale token approval"
  let s := run initial [.register 1, .setOperator 1 2 true]
  check ((step s (.feedback 1 0 3 0)).outcome == .rejected .selfFeedback) "owner feedback"
  check ((step s (.feedback 2 0 3 0)).outcome == .rejected .selfFeedback) "global operator feedback"
  check ((step s (.feedback 3 0 3 18)).outcome == .accepted) "decimal boundary 18"
  check ((step s (.feedback 3 0 3 19)).outcome == .rejected .decimalsOutOfRange) "decimal boundary 19"
  check ((step s (.feedback 3 0 (2 ^ 127 - 1) 0)).outcome == .accepted) "int128 maximum"
  check ((step s (.feedback 3 0 (2 ^ 127) 0)).outcome == .rejected .valueOutOfRange) "int128 overflow"
  check ((step s (.feedback 3 0 (-(2 ^ 127)) 0)).outcome == .accepted) "int128 minimum"
  check ((step s (.setWallet 1 0 7 false)).outcome == .rejected .invalidWalletProof) "wallet proof"
  let newOwnerApproved := run initial [.register 1, .setOperator 3 2 true, .transfer 1 0 3]
  check ((step newOwnerApproved (.setWallet 2 0 7 true)).outcome == .accepted)
    "new owner global approval must survive a transfer"
  let vs := run initial validationScenario
  check (vs.validations 5 == some { agentId := 0, validator := 3, response := some 100 })
    "repeated response or binding after ownership transfer"
  let vos := (trace initial validationScenario).map (·.outcome)
  check (vos[1]? == some (.rejected .unauthorized)) "unauthorized request"
  check (vos[4]? == some (.rejected .duplicateRequest)) "duplicate hash"
  check (vos[5]? == some (.rejected .wrongValidator)) "wrong validator"
  check (vos[6]? == some (.rejected .responseOutOfRange)) "response boundary 101"
  check ((run initial valueCapWitness).feedback.length == 1) "spec int128 witness"
  let witnessAlphabet : List Operation := [.register 1, .transfer 1 0 2, .feedback 1 0 100 0]
  let candidates := (List.range 4).flatMap (sequences witnessAlphabet)
  check (candidates.find? (hasFormerOwnerFeedback [] initial) == some formerOwnerScenario)
    "shortest former-owner witness should have three operations"
  let alphabet : List Operation := [
    .register 1, .approve 1 0 (some 2), .setOperator 1 2 true, .transfer 2 0 3,
    .setWallet 2 0 7 false, .unsetWallet 2 0, .feedback 1 0 99 0, .feedback 2 0 99 19,
    .request 2 0 3 5, .respond 3 5 100, .respond 2 5 101]
  let count ← enumerate alphabet 4 initial
  IO.println s!"ERC-8004: scenarios passed; {count} bounded transitions checked"

end LeanForStandardization.ERC8004
