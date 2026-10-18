-- ABOUTME: Proves trace-wide spacing, handshake security, and winner stability.
-- ABOUTME: Uses kernel-checked proofs without admitted facts or native evaluation.
import LeanForStandardization.HappyEyeballs.Model

namespace LeanForStandardization.HappyEyeballs

@[simp] theorem markFirstPositive_starts (s : State) :
    (markFirstPositive s).starts = s.starts := by
  unfold markFirstPositive
  split <;> rfl

@[simp] theorem markFirstPositive_tls (s : State) :
    (markFirstPositive s).tls = s.tls := by
  unfold markFirstPositive
  split <;> rfl

@[simp] theorem markFirstPositive_winner (s : State) :
    (markFirstPositive s).winner = s.winner := by
  unfold markFirstPositive
  split <;> rfl

@[simp] theorem markFirstPositive_active (s : State) :
    (markFirstPositive s).active = s.active := by
  unfold markFirstPositive
  split <;> rfl

theorem spaced_cons (s : State) (endpoint : Endpoint)
    (valid : Spaced s.starts) (allowed : SpacingAllowed s) :
    Spaced (⟨endpoint, s.now⟩ :: s.starts) := by
  cases h : s.starts <;> simp_all [Spaced, SpacingAllowed]

theorem start_preserves_spacing (c : Config) (s : State)
    (valid : Spaced s.starts) : Spaced (startConnection c s).starts := by
  unfold startConnection
  split <;> try exact valid
  split <;> try exact valid
  split <;> try exact valid
  split
  · exact spaced_cons s _ valid ‹SpacingAllowed s ∧ DelayAllowed c s›.1
  · exact valid

theorem tlsAllowed_ready (c : Config) (s : State)
    (waiting : c.mustWait = true) (allowed : tlsAllowed c s = true) :
    s.https.ready = true := by
  unfold tlsAllowed at allowed
  split at allowed
  · have hs : s.https = .service := by simpa using allowed
    simp [hs, HttpsAnswer.ready]
  · simpa [waiting] using allowed

theorem handshake_preserves_safety (c : Config) (s : State) (endpoint : Endpoint)
    (valid : TlsSafe c s) : TlsSafe c (beginHandshake c s endpoint) := by
  unfold beginHandshake
  split <;> try exact valid
  split
  · rename_i accepted
    intro t member waiting
    simp only [List.mem_cons] at member
    rcases member with rfl | old
    · exact tlsAllowed_ready c s waiting accepted.2.2.2
    · exact valid t old waiting
  · exact valid

theorem step_preserves_spacing (c : Config) (s : State) (event : Event)
    (valid : Spaced s.starts) : Spaced (step c s event).starts := by
  cases event with
  | start => exact start_preserves_spacing c s valid
  | dnsA addresses => simpa [step] using valid
  | dnsAAAA addresses => simpa [step] using valid
  | https answer hints =>
    simp only [step, receiveHttps]
    split <;> simpa using valid
  | advance milliseconds => exact valid
  | transportReady endpoint =>
    simp only [step]
    split <;> exact valid
  | beginTls endpoint =>
    simp only [step, beginHandshake]
    split <;> try exact valid
    split <;> exact valid
  | success endpoint =>
    simp only [step, succeed]
    split <;> try exact valid
    split <;> exact valid
  | failure endpoint =>
    simp only [step]
    split <;> exact valid
  | cancel endpoint =>
    simp only [step]
    split <;> exact valid

theorem step_preserves_tls_safety (c : Config) (s : State) (event : Event)
    (valid : TlsSafe c s) : TlsSafe c (step c s event) := by
  cases event with
  | beginTls endpoint => exact handshake_preserves_safety c s endpoint valid
  | dnsA addresses => simpa [step, TlsSafe] using valid
  | dnsAAAA addresses => simpa [step, TlsSafe] using valid
  | https answer hints =>
    simp only [step, receiveHttps]
    split <;> simpa [TlsSafe] using valid
  | advance milliseconds => exact valid
  | start =>
    simp only [step, startConnection]
    split <;> try exact valid
    split <;> try exact valid
    split <;> try exact valid
    split <;> exact valid
  | transportReady endpoint =>
    simp only [step]
    split <;> exact valid
  | success endpoint =>
    simp only [step, succeed]
    split <;> try exact valid
    split <;> exact valid
  | failure endpoint =>
    simp only [step]
    split <;> exact valid
  | cancel endpoint =>
    simp only [step]
    split <;> exact valid

theorem step_preserves_stopped (c : Config) (s : State) (event : Event)
    (valid : WinnerStopped s) : WinnerStopped (step c s event) := by
  cases event <;>
    simp only [step, startConnection, beginHandshake, succeed, receiveHttps] <;>
    repeat' first | split | (solve | simp_all [WinnerStopped])

theorem step_preserves_valid (c : Config) (s : State) (event : Event)
    (valid : ValidState c s) : ValidState c (step c s event) :=
  ⟨step_preserves_spacing c s event valid.1,
   step_preserves_tls_safety c s event valid.2.1,
   step_preserves_stopped c s event valid.2.2⟩

theorem initial_valid (c : Config) : ValidState c ({} : State) := by
  simp [ValidState, Spaced, TlsSafe, WinnerStopped]

theorem run_preserves_valid (c : Config) (s : State) (events : List Event)
    (valid : ValidState c s) : ValidState c (run c s events) := by
  induction events generalizing s with
  | nil => exact valid
  | cons event events ih =>
    exact ih (step c s event) (step_preserves_valid c s event valid)

/-- Includes arbitrary DNS orders, timer advances, failures, and stale callbacks. -/
theorem all_traces_valid (c : Config) (events : List Event) :
    ValidState c (run c {} events) :=
  run_preserves_valid c {} events (initial_valid c)

theorem all_traces_spaced (c : Config) (events : List Event) :
    Spaced (run c {} events).starts := (all_traces_valid c events).1

theorem all_traces_tls_safe (c : Config) (events : List Event) :
    TlsSafe c (run c {} events) := (all_traces_valid c events).2.1

theorem step_winner_stable (c : Config) (s : State) (event : Event)
    (winner : s.winner = some endpoint) :
    (step c s event).winner = some endpoint := by
  cases event <;>
    simp only [step, startConnection, beginHandshake, succeed, receiveHttps] <;>
    repeat' first | split | (solve | simp_all)

theorem run_winner_stable (c : Config) (s : State) (events : List Event)
    (winner : s.winner = some endpoint) :
    (run c s events).winner = some endpoint := by
  induction events generalizing s with
  | nil => exact winner
  | cons event events ih => exact ih _ (step_winner_stable c s event winner)

theorem step_no_start_after_winner (c : Config) (s : State) (event : Event)
    (winner : s.winner = some endpoint) :
    (step c s event).starts = s.starts := by
  cases event <;>
    simp only [step, startConnection, beginHandshake, succeed, receiveHttps] <;>
    repeat' first | split | (solve | simp_all)

theorem run_no_start_after_winner (c : Config) (s : State) (events : List Event)
    (winner : s.winner = some endpoint) :
    (run c s events).starts = s.starts := by
  induction events generalizing s with
  | nil => rfl
  | cons event events ih =>
    calc
      (run c (step c s event) events).starts = (step c s event).starts :=
        ih _ (step_winner_stable c s event winner)
      _ = s.starts := step_no_start_after_winner c s event winner

end LeanForStandardization.HappyEyeballs
