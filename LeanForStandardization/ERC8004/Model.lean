-- ABOUTME: Executes ERC-8004 identity, feedback, and validation operations without an EVM.
-- ABOUTME: Separates specification guards from documented choices about wallet and hash policies.
import LeanForStandardization.ERC8004.Basic

namespace LeanForStandardization.ERC8004

def putAgent (s : State) (id : AgentId) (a : Agent) : State :=
  { s with agents := fun key => if key = id then some a else s.agents key }

def putValidation (s : State) (hash : RequestHash) (v : Validation) : State :=
  { s with validations := fun key => if key = hash then some v else s.validations key }

def authorized (s : State) (a : Agent) (caller : Address) : Prop :=
  caller = a.owner ∨ a.approved = some caller ∨ s.operators a.owner caller = true

instance (s : State) (a : Agent) (caller : Address) : Decidable (authorized s a caller) :=
  inferInstanceAs (Decidable (caller = a.owner ∨ a.approved = some caller ∨
    s.operators a.owner caller = true))

def int128Valid (value : Int) : Prop := -(2 ^ 127 : Int) ≤ value ∧ value < (2 ^ 127 : Int)

instance (value : Int) : Decidable (int128Valid value) :=
  inferInstanceAs (Decidable (-(2 ^ 127 : Int) ≤ value ∧ value < (2 ^ 127 : Int)))

def transferAgent (s : State) (caller : Address) (id : AgentId) (newOwner : Address) : Execution :=
  match s.agents id with
  | none => .error .unknownAgent
  | some a =>
    if authorized s a caller then
      if newOwner = 0 then .error .zeroAddress
      else .ok (putAgent s id { owner := newOwner, wallet := none, approved := none },
        [.transferred id a.owner newOwner, .walletSet id none])
    else .error .unauthorized

def giveFeedback (s : State) (caller : Address) (id : AgentId) (value : Int)
    (decimals : Nat) : Execution :=
  match s.agents id with
  | none => .error .unknownAgent
  | some a =>
    if authorized s a caller then .error .selfFeedback
    else if decimals ≤ 18 then
      if int128Valid value then
        let index := (s.feedback.filter fun f => f.agentId == id && f.client == caller).length + 1
        let f : Feedback := ⟨id, caller, index, value, decimals⟩
        .ok ({ s with feedback := s.feedback ++ [f] }, [.feedbackGiven f])
      else .error .valueOutOfRange
    else .error .decimalsOutOfRange

def requestValidation (s : State) (caller : Address) (id : AgentId)
    (validator : Address) (hash : RequestHash) : Execution :=
  match s.agents id with
  | none => .error .unknownAgent
  | some a =>
    if authorized s a caller then
      if validator = 0 then .error .zeroAddress
      else if (s.validations hash).isSome then .error .duplicateRequest
      else .ok (putValidation { s with requestHashes := s.requestHashes ++ [hash] }
        hash { agentId := id, validator := validator }, [.validationRequested hash id validator])
    else .error .unauthorized

def respondValidation (s : State) (caller : Address) (hash : RequestHash)
    (response : Nat) : Execution :=
  match s.validations hash with
  | none => .error .unknownRequest
  | some v =>
    if caller = v.validator then
      if response ≤ 100 then
        .ok (putValidation s hash { v with response := some response }, [.validationResponded hash response])
      else .error .responseOutOfRange
    else .error .wrongValidator

def execute (s : State) (op : Operation) : Execution :=
  match op with
  | .register caller =>
    if caller = 0 then .error .zeroAddress
    else .ok (putAgent { s with nextAgent := s.nextAgent + 1 } s.nextAgent
      { owner := caller, wallet := some caller }, [.registered s.nextAgent caller])
  | .approve caller id operator =>
    match s.agents id with
    | none => .error .unknownAgent
    | some a =>
      if caller = a.owner ∨ s.operators a.owner caller = true then
        if operator = some 0 then .error .zeroAddress
        else .ok (putAgent s id { a with approved := operator }, [.approved id operator])
      else .error .unauthorized
  | .setOperator caller operator enabled =>
    if caller = 0 ∨ operator = 0 then .error .zeroAddress
    else .ok ({ s with operators := fun owner key =>
      if owner = caller ∧ key = operator then enabled else s.operators owner key },
      [.operatorSet caller operator enabled])
  | .transfer caller id newOwner => transferAgent s caller id newOwner
  | .setWallet caller id wallet proofValid =>
    match s.agents id with
    | none => .error .unknownAgent
    | some a =>
      if authorized s a caller then
        if wallet = 0 then .error .zeroAddress
        else if proofValid then
          .ok (putAgent s id { a with wallet := some wallet }, [.walletSet id (some wallet)])
        else .error .invalidWalletProof
      else .error .unauthorized
  | .unsetWallet caller id =>
    match s.agents id with
    | none => .error .unknownAgent
    | some a =>
      if authorized s a caller then
        .ok (putAgent s id { a with wallet := none }, [.walletSet id none])
      else .error .unauthorized
  | .feedback caller id value decimals => giveFeedback s caller id value decimals
  | .request caller id validator hash => requestValidation s caller id validator hash
  | .respond caller hash response => respondValidation s caller hash response

def step (s : State) (op : Operation) : Transition :=
  match execute s op with
  | .error reason => ⟨s, .rejected reason, []⟩
  | .ok (next, events) => ⟨next, .accepted, events⟩

def run (s : State) : List Operation → State
  | [] => s
  | op :: rest => run (step s op).state rest

def trace (s : State) : List Operation → List Transition
  | [] => []
  | op :: rest =>
    let t := step s op
    t :: trace t.state rest

end LeanForStandardization.ERC8004
