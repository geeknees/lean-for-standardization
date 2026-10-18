-- ABOUTME: Accepts JSON event traces and emits observable Happy Eyeballs state.
-- ABOUTME: Exposes timing, handshake gates, and rejected action counts for reproducible cases.
import Lean
import LeanForStandardization.HappyEyeballs.Model

namespace LeanForStandardization.HappyEyeballs

open Lean

def parseFamily (value : Json) : Except String Family := do
  match ← value.getStr? with
  | "ipv4" => pure .ipv4
  | "ipv6" => pure .ipv6
  | other => throw s!"unknown address family: {other}"

def parseEndpoint (value : Json) : Except String Endpoint := do
  pure ⟨← parseFamily (← value.getObjVal? "family"),
         ← (← value.getObjVal? "address").getNat?⟩

def parseAnswer (value : Json) : Except String HttpsAnswer := do
  match ← value.getStr? with
  | "pending" => pure .pending
  | "alias" => pure .alias
  | "noData" => pure .noData
  | "service" => pure .service
  | "failure" => pure .failure
  | other => throw s!"unknown HTTPS answer: {other}"

def optionalNat (value : Json) (key : String) (fallback : Nat) : Except String Nat :=
  match value.getObjVal? key with
  | .error _ => pure fallback
  | .ok found => found.getNat?

def optionalBool (value : Json) (key : String) (fallback : Bool) : Except String Bool :=
  match value.getObjVal? key with
  | .error _ => pure fallback
  | .ok found => found.getBool?

def parseConfig (value : Json) : Except String Config := do
  match value with
  | .obj _ => pure ()
  | _ => throw "config must be an object"
  let defaults : Config := {}
  pure {
    resolutionDelay := ← optionalNat value "resolutionDelay" defaults.resolutionDelay
    attemptDelay := ← optionalNat value "attemptDelay" defaults.attemptDelay
    svcbReliant := ← optionalBool value "svcbReliant" defaults.svcbReliant
    mayBecomeReliant := ← optionalBool value "mayBecomeReliant" defaults.mayBecomeReliant
    dnsProtected := ← optionalBool value "dnsProtected" defaults.dnsProtected
    supportsSecurityParam := ← optionalBool value "supportsSecurityParam" defaults.supportsSecurityParam
    reliesOnSecurityParam := ← optionalBool value "reliesOnSecurityParam" defaults.reliesOnSecurityParam
  }

def parseEvent (value : Json) : Except String Event := do
  match ← (← value.getObjVal? "kind").getStr? with
  | "dnsA" => pure (.dnsA (← (← (← value.getObjVal? "addresses").getArr?).toList.mapM Json.getNat?))
  | "dnsAAAA" => pure (.dnsAAAA (← (← (← value.getObjVal? "addresses").getArr?).toList.mapM Json.getNat?))
  | "https" =>
    let answer ← parseAnswer (← value.getObjVal? "answer")
    let hints ← match value.getObjVal? "hints" with
      | .error _ => pure []
      | .ok found => (← found.getArr?).toList.mapM parseEndpoint
    pure (.https answer hints)
  | "advance" => pure (.advance (← (← value.getObjVal? "ms").getNat?))
  | "start" => pure .start
  | "transportReady" => pure (.transportReady (← parseEndpoint value))
  | "beginTls" => pure (.beginTls (← parseEndpoint value))
  | "success" => pure (.success (← parseEndpoint value))
  | "failure" => pure (.failure (← parseEndpoint value))
  | "cancel" => pure (.cancel (← parseEndpoint value))
  | other => throw s!"unknown Happy Eyeballs event: {other}"

def familyName : Family → String
  | .ipv4 => "ipv4"
  | .ipv6 => "ipv6"

def answerName : HttpsAnswer → String
  | .pending => "pending"
  | .alias => "alias"
  | .noData => "noData"
  | .service => "service"
  | .failure => "failure"

def endpointJson (endpoint : Endpoint) : Json := Json.mkObj [
  ("family", toJson (familyName endpoint.family)),
  ("address", toJson endpoint.address)]

def endpointListJson (endpoints : List Endpoint) : Json :=
  .arr (endpoints.map endpointJson).toArray

def startJson (start : Start) : Json := Json.mkObj [
  ("endpoint", endpointJson start.endpoint), ("at", toJson start.time)]

def tlsJson (start : TlsStart) : Json := Json.mkObj [
  ("endpoint", endpointJson start.endpoint), ("at", toJson start.time),
  ("observedHttps", toJson (answerName start.observedHttps))]

def actionEvent : Event → Bool
  | .start | .transportReady _ | .beginTls _ | .success _ | .failure _ | .cancel _ => true
  | _ => false

def evaluate (c : Config) (events : List Event) : State × Nat :=
  events.foldl (fun (state, rejected) event =>
    let next := step c state event
    (next, rejected + if actionEvent event && next == state then 1 else 0)) ({}, 0)

def stateJson (c : Config) (state : State) (rejected : Nat) : Json := Json.mkObj [
  ("now", toJson state.now),
  ("https", toJson (answerName state.https)),
  ("resolutionReady", toJson (resolutionReady c state)),
  ("tlsAllowed", toJson (tlsAllowed c state)),
  ("mustWait", toJson c.mustWait),
  ("candidates", endpointListJson (candidates state)),
  ("starts", .arr (state.starts.reverse.map startJson).toArray),
  ("startTimes", toJson (state.starts.reverse.map (·.time))),
  ("active", endpointListJson state.active),
  ("tls", .arr (state.tls.reverse.map tlsJson).toArray),
  ("winner", state.winner.map endpointJson |>.getD .null),
  ("failed", endpointListJson state.failed),
  ("cancelled", endpointListJson state.cancelled),
  ("aborted", toJson state.aborted),
  ("rejectedActions", toJson rejected),
  ("valid", toJson (checkState c state))]

def evalJson (input : Json) : Except String Json := do
  let config ← match input.getObjVal? "config" with
    | .error _ => pure ({} : Config)
    | .ok value => parseConfig value
  let events ← (← (← input.getObjVal? "events").getArr?).toList.mapM parseEvent
  let (state, rejected) := evaluate config events
  pure (stateJson config state rejected)

end LeanForStandardization.HappyEyeballs
