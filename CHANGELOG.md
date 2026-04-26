# Change Log
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.1.0] - Initial release

Initial public surface, building on `evt-dependency`, `evt-configure`,
`evt-template_method`, `evt-record_invocation`, `evt-casing`, `i18n`, and
`hubbado-log`.

### Added

- **Core types**
  - `Hubbado::Sequence::Result` — value object wrapping a `Ctx`, an ok/fail
    flag, a structured error payload, an i18n scope, and a `trail` of
    completed step names. `Result#message` resolves through a per-error
    scope → result scope → framework default → inline message → humanized
    code chain.
  - `Hubbado::Sequence::Ctx` — `Hash` subclass that raises `KeyError` on
    missing keys via `[]`, leaves `fetch` alone for opt-in optional reads.
  - `Hubbado::Sequence::Pipeline` — railway-style step orchestrator with
    block form (`pipeline(ctx) { |p| ... }`) returning the final `Result`
    automatically. Three call shapes: `p.step(:foo)` for local methods,
    `p.step(:foo) { ... }` for inline blocks, `p.invoke(:foo, *args,
    **kwargs)` for declared dependencies. Lenient return convention — only
    explicitly returned failed Results short-circuit. `p.transaction { |t|
    ... }` wraps inner steps in `ActiveRecord::Base.transaction`.

- **Sequencer mixin** (`include Hubbado::Sequence`)
  - Brings `dependency` (evt-dependency) and `configure` (evt-configure).
  - Class-level `.()` accepts kwargs *or* an existing `Ctx`.
  - Instance `pipeline(ctx)` helper sets `self` as auto-dispatch target.
  - `failure(ctx, **err)` helper auto-applies the sequencer's i18n scope.
  - Auto-derived i18n scope (`Seqs::UpdateUser` → `seqs.update_user`).
  - Default `Substitute` module installed on every including class with
    `succeed_with(**ctx_writes)` / `fail_with(**error)` / `called?(...)`,
    so any sequencer used as a dependency is substitutable without bespoke
    test scaffolding.

- **Six framework macros** — declared dependencies that return `Result`s.
  Each ships an inline `Substitute` with `succeed_with` / `fail_with` and a
  past-tense semantic predicate (`fetched?`, `built?`, `validated?`,
  `persisted?`, `checked?`):
  - `Macros::Model::Find` — DB lookup; fails with `:not_found`.
  - `Macros::Model::Build` — instantiate a new (unsaved) record.
  - `Macros::Contract::Build` — wrap a model in a contract.
  - `Macros::Contract::Validate` — run validations against params; fails
    with `:validation_failed`.
  - `Macros::Contract::Persist` — save the contract; fails with
    `:persist_failed`.
  - `Macros::Policy::Check` — authorise via hubbado-policy; fails with
    `:forbidden`, carrying the policy and policy result on `error[:data]`.

- **Errors**
  - `Hubbado::Sequence::Errors::Failed` — generic unhandled failure.
  - `Hubbado::Sequence::Errors::NotFound` — unhandled `:not_found`.
  - `Hubbado::Sequence::Errors::Unauthorized` — unhandled `:forbidden`,
    carries the failed `Result`.

- **Controller integration** (`include Hubbado::Sequence::RunSequence`)
  - `run_sequence` dispatcher with `success` / `policy_failed` /
    `not_found` / `validation_failed` / `otherwise` outcome blocks.
  - Safety-net raises when `:forbidden` / `:not_found` / any other failure
    isn't handled. `otherwise` deliberately doesn't catch policy denials
    or not_found.
  - Per-handler logging via `Hubbado::Log::Dependency`. Unhandled paths
    log at `:error` before raising.

- **Controls** (shipped in `lib/`, à la `hubbado-policy`)
  - `Controls::Model` / `Controls::Contract` / `Controls::Policy` — fake
    AR / Reform / hubbado-policy stand-ins for use in consumer tests.

- **i18n**
  - Framework default locale at `config/locales/en.yml` for the standard
    error codes (`:not_found`, `:forbidden`, `:validation_failed`,
    `:persist_failed`, `:conflict`).
