-- ABOUTME: Exercises timing boundaries, DNS permutations, stale callbacks, and security gates.
-- ABOUTME: Searches finite traces and shrinks a false resolution-versus-handshake conjecture.
import LeanForStandardization.HappyEyeballs.Properties
import LeanForStandardization.HappyEyeballs.Oracle

namespace LeanForStandardization.HappyEyeballs

private def v4 : Endpoint := ⟨.ipv4, 4⟩
private def v6 : Endpoint := ⟨.ipv6, 6⟩
private def v6b : Endpoint := ⟨.ipv6, 7⟩

private def assertCase (name : String) (condition : Bool) : IO Unit :=
  unless condition do throw (IO.userError s!"Happy Eyeballs: {name}")

def spacingBoundaryEvents : List Event := [
  .dnsAAAA [6, 7], .https .service [], .start,
  .advance 9, .start, .failure v6, .start, .advance 1, .start]

def resolutionBoundaryEvents : List Event := [
  .dnsA [4], .advance 49, .start, .advance 1, .start]

def raceEvents : List Event := [
  .dnsAAAA [6], .dnsA [4], .https .service [],
  .start, .advance 10, .start,
  .transportReady v6, .beginTls v6,
  .transportReady v4, .beginTls v4,
  .success v4, .success v6, .start]

/-- A tempting conjecture which is not a requirement of the draft. -/
def transportReadyImpliesTlsAllowed (c : Config) (s : State) : Bool :=
  !(resolutionReady c s && !s.active.isEmpty && !s.transportConnected.isEmpty) ||
    tlsAllowed c s

def counterexampleAlphabet : List Event := [
  .dnsA [4], .advance 50, .start, .transportReady v4]

def words (alphabet : List α) : Nat → List (List α)
  | 0 => [[]]
  | n + 1 => alphabet.flatMap fun event => (words alphabet n).map (event :: ·)

/-- Breadth first enumeration establishes shortest length within this finite alphabet. -/
def findTransportCounterexample (bound : Nat) : Option (List Event) :=
  ((List.range (bound + 1)).flatMap (words counterexampleAlphabet)).find? fun events =>
    !(transportReadyImpliesTlsAllowed {} (run {} {} events))

private def shrinkWithFuel : Nat → List Event → List Event
  | 0, events => events
  | fuel + 1, events =>
    let shorter := (List.range events.length).findSome? fun index =>
      let candidate := events.take index ++ events.drop (index + 1)
      if !(transportReadyImpliesTlsAllowed {} (run {} {} candidate)) then some candidate else none
    match shorter with
    | none => events
    | some result => shrinkWithFuel fuel result

/-- Each deletion reduces length; initial length bounds the fixed-point iteration. -/
def shrinkCounterexample (events : List Event) : List Event :=
  shrinkWithFuel events.length events

private def explorationAlphabet : List Event := [
  .dnsA [4, 5], .dnsAAAA [6, 7], .dnsA [],
  .https .service [], .https .alias [],
  .advance 9, .advance 1, .advance 40,
  .start, .transportReady v6, .beginTls v6,
  .success v6, .failure v6, .cancel v6]

private def explore (c : Config) : Nat → State → IO Nat
  | 0, state => do
    assertCase "generated state violates safety" (checkState c state)
    pure 1
  | depth + 1, state => do
    assertCase "generated state violates safety" (checkState c state)
    let mut count := 1
    for event in explorationAlphabet do
      count := count + (← explore c depth (step c state event))
    pure count

private def dnsOrders : List (List Event) := [
  [.dnsA [4], .dnsAAAA [6], .https .service []],
  [.dnsA [4], .https .service [], .dnsAAAA [6]],
  [.dnsAAAA [6], .dnsA [4], .https .service []],
  [.dnsAAAA [6], .https .service [], .dnsA [4]],
  [.https .service [], .dnsA [4], .dnsAAAA [6]],
  [.https .service [], .dnsAAAA [6], .dnsA [4]]]

def runTests : IO Unit := do
  let shortDelay : Config := { attemptDelay := 0 }
  let (spacing, rejected) := evaluate shortDelay spacingBoundaryEvents
  assertCase "9 ms rejected, 10 ms accepted even after failure"
    (spacing.starts.reverse.map (·.time) == [0, 10] &&
      spacing.starts.map (·.endpoint) == [v6b, v6] && rejected == 2)
  let (resolution, rejected) := evaluate {} resolutionBoundaryEvents
  assertCase "49 ms rejected, 50 ms accepted"
    (resolution.starts.map (·.time) == [50] && rejected == 1)
  let (race, rejected) := evaluate shortDelay raceEvents
  assertCase "first complete connection wins and stale callback cannot replace it"
    (race.winner == some v4 && race.active.isEmpty && race.cancelled == [v6] &&
      race.starts.length == 2 && rejected == 2)
  let aliasPending := run {} {} [
    .dnsAAAA [6], .https .alias [], .advance 50,
    .start, .transportReady v6, .beginTls v6]
  assertCase "AliasMode does not supply completed service information"
    (aliasPending.starts.length == 1 && aliasPending.tls.isEmpty)
  let aliasResolved := run {} aliasPending [.https .service [], .beginTls v6]
  assertCase "ServiceMode releases a waiting handshake" (aliasResolved.tls.length == 1)
  let noDataEvents := [
    .dnsAAAA [6], .https .noData [], .start, .transportReady v6, .beginTls v6]
  let optionalNoData := run {} {} noDataEvents
  let reliantNoData := run { svcbReliant := true } {} noDataEvents
  assertCase "normal negative answer releases optional but not reliant handshakes"
    (optionalNoData.tls.length == 1 && reliantNoData.tls.isEmpty)
  let missingHttpsEvents := [
    .dnsA [4], .advance 50, .start, .transportReady v4, .beginTls v4]
  let opportunistic := run { dnsProtected := false } {} missingHttpsEvents
  let mayRely := run { dnsProtected := false, mayBecomeReliant := true } {} missingHttpsEvents
  assertCase "section 6.1 wait condition applies independently of protected DNS"
    (opportunistic.tls.length == 1 && mayRely.tls.isEmpty)
  let failure := run {} {} [
    .dnsAAAA [6], .https .service [], .start, .https .failure [],
    .transportReady v6, .beginTls v6, .success v6]
  assertCase "protected service-resolution failure abandons active attempts"
    (failure.aborted && failure.active.isEmpty && failure.winner.isNone && failure.tls.isEmpty)
  let hints := run shortDelay {} [
    .https .service [v6, v6b], .start, .dnsAAAA [8], .advance 10, .start]
  assertCase "hints start immediately, replaced hints keep only ongoing attempts"
    (hints.starts.reverse.map (·.endpoint) == [v6, ⟨.ipv6, 8⟩] &&
      hints.active.contains v6 && !(candidates hints).contains v6b)
  for order in dnsOrders do
    let state := run shortDelay {} (order ++ [.start, .advance 10, .start])
    assertCase "DNS permutations preserve safety and the complete-list interleaving"
      (checkState shortDelay state && state.starts.reverse.map (·.endpoint) == [v6, v4])
  let lateV4 := run shortDelay {} [
    .dnsAAAA [6, 7], .https .service [], .start, .dnsA [4], .advance 10, .start]
  assertCase "late IPv4 is interleaved ahead of remaining IPv6"
    (lateV4.starts.reverse.map (·.endpoint) == [v6, v4])
  let unexpectedSuccess := step {} ({} : State) (.success v6)
  assertCase "unsolicited success is rejected" (unexpectedSuccess == ({} : State))
  let counterexample := findTransportCounterexample 4
  let minimal := [.dnsA [4], .advance 50, .start, .transportReady v4]
  assertCase "finite search finds a shortest false-conjecture counterexample"
    (counterexample == some minimal && (findTransportCounterexample 3).isNone)
  assertCase "deletion shrinking retains the minimal trace"
    (shrinkCounterexample ([.advance 0] ++ minimal ++ [.advance 0]) == minimal)
  let mut visited := 0
  for config in [shortDelay, ({} : Config), ({ dnsProtected := false } : Config)] do
    visited := visited + (← explore config 4 {})
  IO.println s!"Happy Eyeballs: boundary/race/DNS tests passed; {visited} generated states; shortest conjecture counterexample has 4 events"

end LeanForStandardization.HappyEyeballs
