-- ABOUTME: Converts portable JSON operation sequences to the ERC-8004 executable oracle.
-- ABOUTME: Reports accept/reject decisions and observable registry state without using Solidity code.
import LeanForStandardization.ERC8004.Model

namespace LeanForStandardization.ERC8004
open Lean

def parseValue (j : Json) : Except String Int :=
  match j with
  | .str value =>
    match value.toInt? with
    | some n => .ok n
    | none => .error "value must be an integer decimal string"
  | _ => j.getInt?

def parseOperation (j : Json) : Except String Operation := do
  let name ← j.getObjValAs? String "op"
  let caller ← j.getObjValAs? Nat "caller"
  match name with
  | "register" => return .register caller
  | "approve" => return .approve caller (← j.getObjValAs? Nat "agentId") (← j.getObjValAs? (Option Nat) "operator")
  | "setOperator" => return .setOperator caller (← j.getObjValAs? Nat "operator") (← j.getObjValAs? Bool "enabled")
  | "transfer" => return .transfer caller (← j.getObjValAs? Nat "agentId") (← j.getObjValAs? Nat "newOwner")
  | "setWallet" => return .setWallet caller (← j.getObjValAs? Nat "agentId") (← j.getObjValAs? Nat "wallet") (← j.getObjValAs? Bool "proofValid")
  | "unsetWallet" => return .unsetWallet caller (← j.getObjValAs? Nat "agentId")
  | "feedback" => return .feedback caller (← j.getObjValAs? Nat "agentId") (← parseValue (← j.getObjVal? "value")) (← j.getObjValAs? Nat "decimals")
  | "request" => return .request caller (← j.getObjValAs? Nat "agentId") (← j.getObjValAs? Nat "validator") (← j.getObjValAs? Nat "hash")
  | "respond" => return .respond caller (← j.getObjValAs? Nat "hash") (← j.getObjValAs? Nat "response")
  | _ => throw s!"unknown ERC-8004 operation: {name}"

def rejectName : Reject → String
  | .unknownAgent => "unknownAgent"
  | .unauthorized => "unauthorized"
  | .zeroAddress => "zeroAddress"
  | .invalidWalletProof => "invalidWalletProof"
  | .selfFeedback => "selfFeedback"
  | .decimalsOutOfRange => "decimalsOutOfRange"
  | .valueOutOfRange => "valueOutOfRange"
  | .duplicateRequest => "duplicateRequest"
  | .unknownRequest => "unknownRequest"
  | .wrongValidator => "wrongValidator"
  | .responseOutOfRange => "responseOutOfRange"

def outcomeJson : Outcome → Json
  | .accepted => Json.mkObj [("status", toJson "accepted")]
  | .rejected reason => Json.mkObj [("status", toJson "rejected"), ("reason", toJson (rejectName reason))]

def feedbackJson (f : Feedback) : Json := Json.mkObj [
  ("agentId", toJson f.agentId), ("client", toJson f.client), ("index", toJson f.index),
  ("value", toJson (toString f.value)), ("decimals", toJson f.decimals)]

def stateJson (s : State) : Json :=
  let agents := (List.range s.nextAgent).filterMap fun id => (s.agents id).map fun a =>
    Json.mkObj [("id", toJson id), ("owner", toJson a.owner),
      ("wallet", toJson a.wallet), ("approved", toJson a.approved)]
  let validations := s.requestHashes.filterMap fun hash => (s.validations hash).map fun v =>
    Json.mkObj [("hash", toJson hash), ("agentId", toJson v.agentId),
      ("validator", toJson v.validator), ("response", toJson v.response)]
  Json.mkObj [("nextAgent", toJson s.nextAgent), ("agents", toJson agents),
    ("feedback", toJson (s.feedback.map feedbackJson)), ("validations", toJson validations)]

def evalJson (input : Json) : Except String Json := do
  let raw ← input.getObjValAs? (Array Json) "operations"
  let operations ← raw.toList.mapM parseOperation
  let transitions := trace initial operations
  return Json.mkObj [("state", stateJson (run initial operations)),
    ("outcomes", toJson (transitions.map fun t => outcomeJson t.outcome))]

end LeanForStandardization.ERC8004
