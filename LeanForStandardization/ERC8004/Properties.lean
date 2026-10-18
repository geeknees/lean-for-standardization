-- ABOUTME: Proves transfer cleanup and registry authorization against the executable model.
-- ABOUTME: Uses kernel-checked proofs and makes every environmental hypothesis explicit.
import LeanForStandardization.ERC8004.Model

namespace LeanForStandardization.ERC8004

theorem rejection_preserves_state (s : State) (op : Operation) (reason : Reject)
    (h : execute s op = .error reason) :
    (step s op).state = s ∧ (step s op).events = [] := by
  simp [step, h]

theorem transfer_clears_wallet_and_approval (s s' : State) (caller newOwner : Address)
    (id : AgentId) (events : List Event)
    (h : execute s (.transfer caller id newOwner) = .ok (s', events)) :
    s'.agents id = some { owner := newOwner, wallet := none, approved := none } := by
  simp only [execute, transferAgent] at h
  split at h
  · contradiction
  · split at h
    · split at h
      · contradiction
      · cases h
        simp [putAgent]
    · contradiction

theorem transfer_revokes_unapproved_authority (s s' : State) (caller newOwner outsider : Address)
    (id : AgentId) (events : List Event)
    (h : execute s (.transfer caller id newOwner) = .ok (s', events))
    (hDifferent : outsider ≠ newOwner) (hNoGlobal : s.operators newOwner outsider = false) :
    ∃ a, s'.agents id = some a ∧ ¬ authorized s' a outsider := by
  simp only [execute, transferAgent] at h
  split at h
  · contradiction
  · split at h
    · split at h
      · contradiction
      · cases h
        refine ⟨{ owner := newOwner, wallet := none, approved := none }, ?_, ?_⟩
        · simp [putAgent]
        · simp [authorized, putAgent, hDifferent, hNoGlobal]
    · contradiction

theorem accepted_feedback_excludes_authority (s s' : State) (caller : Address)
    (id : AgentId) (value : Int) (decimals : Nat) (events : List Event)
    (h : execute s (.feedback caller id value decimals) = .ok (s', events)) :
    ∃ a, s.agents id = some a ∧ ¬ authorized s a caller ∧ decimals ≤ 18 ∧ int128Valid value := by
  cases ha : s.agents id with
  | none => simp [execute, giveFeedback, ha] at h
  | some a =>
    by_cases auth : authorized s a caller
    · simp [execute, giveFeedback, ha, auth] at h
    · by_cases hd : decimals ≤ 18
      · by_cases hv : int128Valid value
        · exact ⟨a, rfl, auth, hd, hv⟩
        · simp [execute, giveFeedback, ha, auth, hd, hv] at h
      · simp [execute, giveFeedback, ha, auth, hd] at h

theorem authorized_feedback_rejected (s : State) (a : Agent) (caller : Address)
    (id : AgentId) (value : Int) (decimals : Nat)
    (ha : s.agents id = some a) (auth : authorized s a caller) :
    (step s (.feedback caller id value decimals)).state = s ∧
    (step s (.feedback caller id value decimals)).outcome = .rejected .selfFeedback := by
  simp [step, execute, giveFeedback, ha, auth]

theorem request_requires_authority (s s' : State) (caller validator : Address)
    (id : AgentId) (hash : RequestHash) (events : List Event)
    (h : execute s (.request caller id validator hash) = .ok (s', events)) :
    ∃ a, s.agents id = some a ∧ authorized s a caller := by
  cases ha : s.agents id with
  | none => simp [execute, requestValidation, ha] at h
  | some a =>
    by_cases auth : authorized s a caller
    · exact ⟨a, rfl, auth⟩
    · simp [execute, requestValidation, ha, auth] at h

theorem response_requires_designated_validator (s s' : State) (caller : Address)
    (hash : RequestHash) (response : Nat) (events : List Event)
    (h : execute s (.respond caller hash response) = .ok (s', events)) :
    ∃ v, s.validations hash = some v ∧ caller = v.validator ∧ response ≤ 100 := by
  cases hv : s.validations hash with
  | none => simp [execute, respondValidation, hv] at h
  | some v =>
    by_cases hc : caller = v.validator
    · by_cases hr : response ≤ 100
      · exact ⟨v, rfl, hc, hr⟩
      · simp [execute, respondValidation, hv, hc, hr] at h
    · simp [execute, respondValidation, hv, hc] at h

theorem response_preserves_request_binding (s s' : State) (v : Validation) (caller : Address)
    (hash : RequestHash) (response : Nat) (events : List Event)
    (hv : s.validations hash = some v)
    (h : execute s (.respond caller hash response) = .ok (s', events)) :
    s'.validations hash = some { v with response := some response } := by
  simp only [execute, respondValidation, hv] at h
  split at h
  · split at h
    · cases h
      simp [putValidation]
    · contradiction
  · contradiction

end LeanForStandardization.ERC8004
