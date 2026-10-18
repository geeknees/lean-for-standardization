-- ABOUTME: Defines the bounded Happy Eyeballs v3 protocol vocabulary and state.
-- ABOUTME: Keeps connection starts, TCP progress, and TLS starts as separate observations.
import Std

namespace LeanForStandardization.HappyEyeballs

inductive Family where
  | ipv4 | ipv6
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Inhabited

structure Endpoint where
  family : Family
  address : Nat
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Inhabited

inductive HttpsAnswer where
  | pending | alias | noData | service | failure
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Inhabited

def HttpsAnswer.ready : HttpsAnswer → Bool
  | .noData | .service => true
  | _ => false

structure Config where
  resolutionDelay : Nat := 50
  attemptDelay : Nat := 250
  svcbReliant : Bool := false
  mayBecomeReliant : Bool := false
  dnsProtected : Bool := true
  supportsSecurityParam : Bool := true
  reliesOnSecurityParam : Bool := true
  deriving Repr, DecidableEq, Inhabited

/-- The two independently stated SVCB wait conditions in §§6.1 and 6.3. -/
def Config.mustWait (c : Config) : Bool :=
  c.svcbReliant || c.mayBecomeReliant ||
    (c.dnsProtected && c.supportsSecurityParam && c.reliesOnSecurityParam)

structure Start where
  endpoint : Endpoint
  time : Nat
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Inhabited

structure TlsStart where
  endpoint : Endpoint
  time : Nat
  observedHttps : HttpsAnswer
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Inhabited

structure State where
  now : Nat := 0
  a : Option (List Nat) := none
  aaaa : Option (List Nat) := none
  https : HttpsAnswer := .pending
  hints : List Endpoint := []
  firstPositiveAt : Option Nat := none
  starts : List Start := []
  active : List Endpoint := []
  transportConnected : List Endpoint := []
  tls : List TlsStart := []
  failed : List Endpoint := []
  cancelled : List Endpoint := []
  winner : Option Endpoint := none
  aborted : Bool := false
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Inhabited

inductive Event where
  | dnsA (addresses : List Nat)
  | dnsAAAA (addresses : List Nat)
  | https (answer : HttpsAnswer) (hints : List Endpoint)
  | advance (milliseconds : Nat)
  | start
  | transportReady (endpoint : Endpoint)
  | beginTls (endpoint : Endpoint)
  | success (endpoint : Endpoint)
  | failure (endpoint : Endpoint)
  | cancel (endpoint : Endpoint)
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Inhabited

/-- Newest starts are stored first. Every pair of consecutive starts is separated. -/
def Spaced : List Start → Prop
  | [] => True
  | [_] => True
  | newer :: older :: rest => older.time + 10 ≤ newer.time ∧ Spaced (older :: rest)

/-- Audit the DNS status at handshake time, rather than at the end of a trace. -/
def TlsSafe (c : Config) (s : State) : Prop :=
  ∀ t ∈ s.tls, c.mustWait = true → t.observedHttps.ready = true

def WinnerStopped (s : State) : Prop :=
  s.winner.isSome = true → s.active = []

/-- Validity covers the safety obligations proved by this PoC, not the full draft. -/
def ValidState (c : Config) (s : State) : Prop :=
  Spaced s.starts ∧ TlsSafe c s ∧ WinnerStopped s

end LeanForStandardization.HappyEyeballs
