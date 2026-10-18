# Working guidance

We work as a team. Be thoughtful, honest, and willing to push back with evidence.
Prefer low operational debt, explicit business/data flows, and human-centered automation.
Represent stakeholder interests fairly; distinguish facts from inferred perspectives.

## Scope and authorization

- An explicit request authorizes its stated scope. Continue reversible local implementation and checks within it.
- Ask before unapproved architecture, core logic, dependency, schema, CI, or authentication changes. Continue independent work while waiting.
- Secret-bearing files such as `.env`, `.pem`, and credentials need explicit authorization. Never print the complete environment.
- Destructive operations, external messages/publication, push, and deployment require explicit authorization.
- Preserve unrelated work and supplied source material. Do not save private data, credentials, or raw logs in durable notes.
- Local commits may complete a task; never bypass hooks, use GPG signing, or push directly to a protected branch.

## Implementation

- Ruby/Node use mise. If resolution fails, use `mise exec -- <command>`.
- Prefer Ruby for auxiliary scripts. Keep the executable protocol semantics and proofs in Lean.
- TDD is the default for behavior changes; preserve test intent and cover changed behavior. Existing coverage may suffice.
- Start hand-written source files with two `ABOUTME:` comment lines where idiomatic; exclude generated, lock, data, and vendored files.
- Name current behavior. Keep useful intent comments and remove obsolete comments alongside code.
- Search relevant project decisions or `gotchas.md` when a prior choice matters. Record reusable substantive corrections locally.

## Research requirements

- Read the pinned original specification before changing the model. `specs/*/manifest.json` records the versions and hashes.
- Keep MUST, SHOULD, MAY, prose requirements, external assumptions, and model policies distinct in `docs/spec-traceability.md`.
- Lean model correctness does not establish natural-language interpretation or implementation correctness.
- Do not use admitted proofs, custom unproved axioms, or native decision procedures to present a proof as complete.
- A failed candidate property calls for a counterexample or an explicit missing assumption, not a hidden strengthening.
- Record findings as Specification issue, Implementation issue, Model issue, or Open question. Do not manufacture defects.
- Never post upstream automatically. Reproduction, interpretation review, duplicate search, and human review precede external reports.
- If behavior coverage cannot be provided, explain why and obtain agreement to the exception unless already authorized.

## Verification

```sh
lake build
lake env lean LeanForStandardization.lean
lake env lean Audit.lean
ruby scripts/check-audit.rb
lake exe model-tests
ruby scripts/check.rb
ruby scripts/check-json.rb
```

Use `scripts/bootstrap-lean.sh` for a repository-local toolchain. Report executed verification separately from configured CI and unexecuted EVM tests.
Keep `docs/findings.md`, `docs/limitations.md`, and the traceability table consistent when a decision changes.

## Relevant references

- Commit conventions: `~/.config/aichat/roles/commit.md`
- Architecture: `~/.codex/docs/system_architecture_guidelines.md`
- Difficult test/refactor tradeoffs: `~/.codex/docs/testing_guidelines.md`
- Discovery/prioritization: `~/.codex/docs/product_management_guidelines.md`
- External write recovery: `~/.codex/docs/external-writes.md`
- Locally adapted skills: `~/.codex/skills/_shared/references/skill-maintenance.md`

Consult only the reference relevant to the current decision. User instructions and tool permissions still apply.
