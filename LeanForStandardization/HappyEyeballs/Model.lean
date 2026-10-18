-- ABOUTME: Executes a single-service TCP/TLS subset of Happy Eyeballs v3-04.
-- ABOUTME: Treats input events as adversarial proposals and rejects disallowed transitions.
import LeanForStandardization.HappyEyeballs.Basic

namespace LeanForStandardization.HappyEyeballs

def interleave : List α → List α → List α
  | [], ys => ys
  | xs, [] => xs
  | x :: xs, y :: ys => x :: y :: interleave xs ys

/-- Each family's input order stands for an externally supplied RFC 6724 ordering. -/
def familyCandidates (s : State) (family : Family) : List Endpoint :=
  match (if family == .ipv6 then s.aaaa else s.a) with
  | some addresses => addresses.map fun address => ⟨family, address⟩
  | none => s.hints.filter (fun endpoint => endpoint.family == family)

def candidates (s : State) : List Endpoint :=
  interleave (familyCandidates s .ipv6) (familyCandidates s .ipv4)

/-- Recompute the full interleaving before excluding already attempted endpoints (§7). -/
def nextCandidate (s : State) : Option Endpoint :=
  (candidates s).find? fun endpoint =>
    !(s.starts.any fun attempt => attempt.endpoint == endpoint)

def markFirstPositive (s : State) : State :=
  if s.firstPositiveAt.isNone && !(candidates s).isEmpty then
    { s with firstPositiveAt := some s.now }
  else s

def resolutionReady (c : Config) (s : State) : Bool :=
  !(candidates s).isEmpty &&
    (((s.aaaa.isSome || !(familyCandidates s .ipv6).isEmpty) && s.https.ready) ||
      match s.firstPositiveAt with
      | none => false
      | some first => decide (first + c.resolutionDelay ≤ s.now))

def SpacingAllowed (s : State) : Prop :=
  match s.starts with
  | [] => True
  | previous :: _ => previous.time + 10 ≤ s.now

def DelayAllowed (c : Config) (s : State) : Prop :=
  match s.starts with
  | [] => True
  | previous :: _ => previous.time + c.attemptDelay ≤ s.now

instance (s : State) : Decidable (SpacingAllowed s) := by
  unfold SpacingAllowed
  split <;> infer_instance

instance (c : Config) (s : State) : Decidable (DelayAllowed c s) := by
  unfold DelayAllowed
  split <;> infer_instance

def startConnection (c : Config) (s : State) : State :=
  if s.winner.isSome || s.aborted then s
  else if resolutionReady c s then
    match nextCandidate s with
    | none => s
    | some endpoint =>
      if SpacingAllowed s ∧ DelayAllowed c s then
        { s with starts := ⟨endpoint, s.now⟩ :: s.starts,
                 active := endpoint :: s.active }
      else s
  else s

/-- A reliant client cannot fall back on a negative service answer. -/
def tlsAllowed (c : Config) (s : State) : Bool :=
  if c.svcbReliant then s.https == .service
  else if c.mustWait then s.https.ready
  else true

def beginHandshake (c : Config) (s : State) (endpoint : Endpoint) : State :=
  if s.winner.isSome || s.aborted then s
  else if endpoint ∈ s.active ∧ endpoint ∈ s.transportConnected ∧
      !(s.tls.any fun t => t.endpoint == endpoint) ∧ tlsAllowed c s then
    { s with tls := ⟨endpoint, s.now, s.https⟩ :: s.tls }
  else s

def succeed (s : State) (endpoint : Endpoint) : State :=
  if s.winner.isSome || s.aborted then s
  else if endpoint ∈ s.active ∧ (s.tls.any fun t => t.endpoint == endpoint) then
    { s with winner := some endpoint, active := [],
             cancelled := s.active.filter (· != endpoint) ++ s.cancelled }
  else s

/-- Protected SVCB failure follows the §6.3 SHOULD to abandon this setup. -/
def receiveHttps (c : Config) (s : State) (answer : HttpsAnswer)
    (hints : List Endpoint) : State :=
  let updated := { s with
    https := answer
    hints := if answer == .service then hints else [] }
  if answer == .failure && c.dnsProtected && s.winner.isNone then
    markFirstPositive { updated with
      aborted := true
      active := []
      cancelled := s.active ++ s.cancelled }
  else markFirstPositive updated

def step (c : Config) (s : State) : Event → State
  | .dnsA addresses => markFirstPositive { s with a := some addresses }
  | .dnsAAAA addresses => markFirstPositive { s with aaaa := some addresses }
  | .https answer hints => receiveHttps c s answer hints
  | .advance milliseconds => { s with now := s.now + milliseconds }
  | .start => startConnection c s
  | .transportReady endpoint =>
    if endpoint ∈ s.active ∧ endpoint ∉ s.transportConnected then
      { s with transportConnected := endpoint :: s.transportConnected }
    else s
  | .beginTls endpoint => beginHandshake c s endpoint
  | .success endpoint => succeed s endpoint
  | .failure endpoint =>
    if endpoint ∈ s.active then
      { s with active := s.active.filter (· != endpoint), failed := endpoint :: s.failed }
    else s
  | .cancel endpoint =>
    if endpoint ∈ s.active then
      { s with active := s.active.filter (· != endpoint), cancelled := endpoint :: s.cancelled }
    else s

def run (c : Config) (s : State) : List Event → State
  | [] => s
  | event :: events => run c (step c s event) events

def checkSpacing : List Start → Bool
  | [] => true
  | [_] => true
  | newer :: older :: rest =>
    decide (older.time + 10 ≤ newer.time) && checkSpacing (older :: rest)

/-- Executable observation checks supplement, and do not replace, the trace proofs. -/
def checkState (c : Config) (s : State) : Bool :=
  checkSpacing s.starts &&
    (s.tls.all fun t => !c.mustWait || t.observedHttps.ready) &&
    (!s.winner.isSome || s.active.isEmpty)

end LeanForStandardization.HappyEyeballs
