-- ABOUTME: Defines the finite observations and abstract addresses of the ERC-8004 model.
-- ABOUTME: Keeps ERC-721 approvals explicit while abstracting cryptographic wallet proofs.
import Lean

namespace LeanForStandardization.ERC8004

abbrev Address := Nat
abbrev AgentId := Nat
abbrev RequestHash := Nat

structure Agent where
  owner : Address
  wallet : Option Address
  approved : Option Address := none
  deriving Repr, DecidableEq, BEq

structure Feedback where
  agentId : AgentId
  client : Address
  index : Nat
  value : Int
  decimals : Nat
  deriving Repr, DecidableEq, BEq

structure Validation where
  agentId : AgentId
  validator : Address
  response : Option Nat := none
  deriving Repr, DecidableEq, BEq

structure State where
  nextAgent : Nat := 0
  agents : AgentId → Option Agent := fun _ => none
  operators : Address → Address → Bool := fun _ _ => false
  feedback : List Feedback := []
  validations : RequestHash → Option Validation := fun _ => none
  requestHashes : List RequestHash := []

def initial : State := {}

inductive Reject where
  | unknownAgent | unauthorized | zeroAddress | invalidWalletProof
  | selfFeedback | decimalsOutOfRange | valueOutOfRange
  | duplicateRequest | unknownRequest | wrongValidator | responseOutOfRange
  deriving Repr, DecidableEq, BEq

inductive Operation where
  | register (caller : Address)
  | approve (caller : Address) (agentId : AgentId) (operator : Option Address)
  | setOperator (caller operator : Address) (enabled : Bool)
  | transfer (caller : Address) (agentId : AgentId) (newOwner : Address)
  | setWallet (caller : Address) (agentId : AgentId) (wallet : Address) (proofValid : Bool)
  | unsetWallet (caller : Address) (agentId : AgentId)
  | feedback (caller : Address) (agentId : AgentId) (value : Int) (decimals : Nat)
  | request (caller : Address) (agentId : AgentId) (validator : Address) (hash : RequestHash)
  | respond (caller : Address) (hash : RequestHash) (response : Nat)
  deriving Repr, DecidableEq, BEq

inductive Event where
  | registered (agentId : AgentId) (owner : Address)
  | approved (agentId : AgentId) (operator : Option Address)
  | operatorSet (owner operator : Address) (enabled : Bool)
  | transferred (agentId : AgentId) (oldOwner newOwner : Address)
  | walletSet (agentId : AgentId) (wallet : Option Address)
  | feedbackGiven (feedback : Feedback)
  | validationRequested (hash : RequestHash) (agentId : AgentId) (validator : Address)
  | validationResponded (hash : RequestHash) (response : Nat)
  deriving Repr, DecidableEq, BEq

inductive Outcome where
  | accepted
  | rejected (reason : Reject)
  deriving Repr, DecidableEq, BEq

structure Transition where
  state : State
  outcome : Outcome
  events : List Event

abbrev Execution := Except Reject (State × List Event)

end LeanForStandardization.ERC8004
