# Change Log
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

### Changed (breaking)

- **`Macros::Policy::Check#call` signature changed** from `(ctx, policy,
  record_key, action)` to `(ctx, policy, action, record_key = nil)`.
  `record_key` is now a trailing optional positional; omitting it
  builds the policy with `nil` as the record, the shape required by
  plural / collection policies (e.g. `Policies::Jobs`) that authorise
  on a non-record subject rather than gating on a specific record:

  ```ruby
  # before
  p.invoke(:check_policy, Policies::User, :user, :update)

  # after
  p.invoke(:check_policy, Policies::User, :update, :user)  # singular
  p.invoke(:check_policy, Policies::Jobs, :list)           # record-less
  ```

  Migration: at every `p.invoke(:check_policy, ...)` call site, swap
  the third and fourth positional arguments. Substitutes and the
  underlying `policy.method_defined?(action)` typo-catch are
  unchanged in behaviour; the parameter order on the substitute's
  `call` is migrated to match.

  See `docs/design.md` "Resolved Through Iteration" for the rationale
  and the alternatives considered.

### Added

- **`Macros::Policy::Check.failure(ctx, policy, policy_result)`** class
  helper. Returns `Result.failure(ctx, code: :forbidden, data: { policy:,
  policy_result: })` — the same failure shape the macro produces. Lets
  hand-rolled policy-check steps (for policy actions that take arguments,
  or for compound logic the macro doesn't cover) produce the standard
  failure shape without duplicating framework knowledge.

- **`Macros::Policy::Check` now stores the built policy on `ctx[:policy]`.**
  After building the policy instance and before invoking the action, the
  macro writes it to ctx under `:policy` by default. Downstream steps (e.g.
  contract construction that needs the policy injected) can read it
  directly without re-building. Pass `as:` to store under a different key
  when a sequencer runs multiple policy checks:

  ```ruby
  p.invoke(:check_policy, Policies::Document, :update, :document)
  # ctx[:policy] is now the built Policies::Document instance

  p.invoke(:check_policy, Policies::User, :show, :user, as: :user_policy)
  # ctx[:user_policy] is the built Policies::User instance
  ```

  The substitute's `succeed_with` now accepts an optional policy instance;
  passing one mirrors the production write to `ctx[as]` so substituted
  specs can drive the same downstream paths.

### Changed

- **`Macros::Contract::Build`'s second parameter renamed** from
  `attr_name` to `model`. The positional shape is unchanged — this is
  an internal rename only — and the name now describes what the
  parameter is (the ctx key/path for the model the contract wraps)
  rather than what it isn't (an "attribute name" on anything). Callers
  passing the value positionally (the only in-tree shape) are
  unaffected.

### Fixed

- **`Sequencer#pipeline` and `Sequencer.()` now apply the sequencer's
  auto-derived `i18n_scope` to the returned Result.** Closes a
  documented-but-unimplemented step in the `Result#message`
  translation fallback chain. Previously only `Sequencer#failure` (the
  explicit helper) tagged a result with the sequencer's scope; macros
  call `Result.failure` directly with no scope, so a sequencer body
  that returned a macro's failure unchanged produced an unscoped
  Result and `Result#message` fell through to the framework default
  (`sequence.errors.<code>`) instead of the per-sequencer scoped
  translation. Pure-macro sequencers (e.g. a body that's just
  `pipeline(ctx) { |p| p.invoke(:check_policy, ...) }`) could never
  produce a message translated under their own namespace. Tagging at
  the boundary (`pipeline.result` and `Sequencer.()`) via
  `Result#with_i18n_scope` preserves nested-sequencer "innermost scope
  wins" semantics — `with_i18n_scope` is a no-op when the scope is
  already set, so an inner sequencer's scope survives the outer
  wrapper. See `docs/design.md` "Resolved Through Iteration" for the
  rationale.

## [0.6.0] - Result.failure flat kwargs; Dispatch delegates reads and exposes raise helpers

### Changed (breaking)

- **`Result.failure` takes flat kwargs; the `error:` hash wrapper is
  gone.** The previous shape — `Result.failure(ctx, error: { code:,
  data:, ... })` — wrapped its keys in an `error:` hash for no reason
  beyond convention. The fields are now first-class kwargs on
  `Result.failure` and first-class attrs on `Result`:

  ```ruby
  # before
  Result.failure(ctx, error: { code: :forbidden, data: { policy_result: pr } })
  result.error[:code]                # => :forbidden
  result.error[:data][:policy_result]

  # after
  Result.failure(ctx, code: :forbidden, data: { policy_result: pr })
  result.code                        # => :forbidden
  result.data[:policy_result]
  ```

  `Result` exposes `code`, `data`, `step`, `message_override`,
  `i18n_scope`, `i18n_key`, `i18n_args` as readers. `Result#error`
  is removed.

  Migration: in callers, replace `Result.failure(ctx, error: { code:
  :X })` with `Result.failure(ctx, code: :X)`. Replace `result.error[:X]`
  reads with `result.X`. The `Sequencer#failure(ctx, **error_attrs)`
  helper is unchanged at the call site (it always took flat kwargs).
  Macro substitutes' `fail_with(**error_attrs)` is unchanged at the call
  site; arbitrary extra attrs that used to live in the error hash should
  move into `data:` (`fail_with(code: :forbidden, data: { reason:
  :not_owner })`).

- **The per-error `i18n_scope` override path is removed.** Previously a
  caller could put `i18n_scope:` inside the `error:` hash *and* pass a
  separate `i18n_scope:` to the surrounding wrapper, with the per-error
  one winning. With flat kwargs there is one `i18n_scope` slot. The
  `Sequencer#failure` helper still applies the sequencer's auto-derived
  scope when the caller doesn't pass one (`error_attrs[:i18n_scope] ||=
  i18n_scope`), preserving the "caller wins" semantics where it matters
  in practice. `Result#with_i18n_scope` (used to apply a scope to an
  already-built Result) is unchanged.

- **`Runner::Dispatch#result` is removed.** Master exposed the wrapped
  Result via `attr_reader :result`, which was the source of the
  `result.result.error.dig(...)` four-hop pattern. With the new
  read-through delegations (`code`, `data`, `step`, `message`,
  `successful_steps`, `ctx`) there's no reason for outcome blocks to
  reach into the inner Result. Any caller still doing
  `result.result.X` from inside a `run_sequence` block will now raise
  `NoMethodError`; replace with the matching delegation on the
  dispatch object itself.

- **The `message:` kwarg on `Result.failure` is removed.** It set a
  literal-string fallback returned by `Result#message` when no
  translation matched. No in-tree caller used it (the
  i18n-translation chain plus `humanize_code` fallback covered every
  real case), and the path was test-only. If a caller needs a custom
  message they can supply `i18n_key:` and a matching translation, or
  pass a humanizable `code:` symbol.

### Added

- **`Runner::Dispatch` delegates reads to its wrapped `Result`.** Outcome
  blocks can call `result.code`, `result.data`, `result.message`,
  `result.step`, `result.successful_steps`, `result.ctx` on the
  `Dispatch` object (the block argument) without hopping through an
  inner `.result.` reference. The previous `result.result.error.dig(...)`
  pattern collapses to one read.

  ```ruby
  result.policy_failed do |ctx|
    if result.data[:policy_result].reason == :not_open
      redirect_to public_path(ctx[:job])
    else
      result.raise_policy_failed
    end
  end
  ```

- **Public raise helpers on `Runner::Dispatch`:** `raise_policy_failed`,
  `raise_not_found`, and `raise_failed`. They produce the same exceptions
  the safety net would raise, but can be called explicitly from inside an
  outcome block — useful when a caller handles some failure cases inline
  and wants the framework's standard escalation for the rest.
  `enforce_safety_nets!` now delegates to the same helpers, so the
  exception shapes stay aligned whether the caller invokes them directly
  or the runner does it automatically.

## [0.5.0] - Result vocabulary renamed: success/failure and successful_steps

### Changed (breaking)

- **`Result.ok` → `Result.success`** and **`Result.fail` → `Result.failure`**.
  Aligns with the wider Ruby railway-oriented vocabulary (dry-monads,
  dry-transaction) and replaces the asymmetric `ok`/`failure?` pair with a
  consistent `success`/`failure` pair.

  ```ruby
  # before
  Result.ok(ctx)
  Result.fail(ctx, error: { code: :forbidden })
  result.ok?

  # after
  Result.success(ctx)
  Result.failure(ctx, error: { code: :forbidden })
  result.success?
  ```

  `result.failure?` is unchanged.

  Migration: search-and-replace `Result.ok(` → `Result.success(`,
  `Result.fail(` → `Result.failure(`, and `.ok?` → `.success?`. RSpec
  matchers `be_ok` become `be_success`.

- **`Result#trail` → `Result#successful_steps`** (and `with_trail` →
  `with_successful_steps`, `trail:` kwarg → `successful_steps:`). The old
  name was confusing because the failing step is *not* in the list — it
  lives on `error[:step]`. The new name says exactly what's there.

  ```ruby
  # before
  result.trail               # => [:find, :build_contract]
  result.with_trail([...])
  Result.ok(ctx, trail: [...])

  # after
  result.successful_steps    # => [:find, :build_contract]
  result.with_successful_steps([...])
  Result.success(ctx, successful_steps: [...])
  ```

  Migration: search-and-replace `.trail` → `.successful_steps`,
  `with_trail(` → `with_successful_steps(`, and the keyword argument
  `trail:` → `successful_steps:`.

## [0.4.0] - Inline step blocks removed; Pipeline made internal

### Removed (breaking)

- **Inline block form of `step` removed.** `p.step(:name) { |ctx| ... }`
  is no longer supported. Every step must be a method on the sequencer
  with the same name:

  ```ruby
  # before
  p.step(:notify) { |ctx| UserMailer.updated(ctx[:user]).deliver_later }

  # after
  p.step(:notify)          # dispatches to def notify(ctx)
  ```

  Migration: extract each inline block to a private method of the same
  name. One method per step; one method per responsibility.

- **`Pipeline` is no longer part of the public API.** `Pipeline.(ctx)`
  and `Pipeline.new` are internal to the framework. Sequencers build
  pipelines exclusively through the `pipeline(ctx)` helper.

  Migration: any direct `Pipeline.(ctx)` or `Pipeline.new(ctx, ...)`
  call sites must be replaced with a sequencer that uses `pipeline(ctx)`.

### Changed

- **`Pipeline#step` always auto-dispatches.** With inline blocks gone,
  `step(:foo)` unconditionally dispatches to `self.foo(ctx)` on the
  sequencer — no block-versus-dispatch ambiguity. Missing methods raise
  `NoMethodError` with the step name and the sequencer class in the
  message.

## [0.3.0] - Contract::Deserialize macro, Runner extraction, Path helper

### Added

- **`Macros::Contract::Deserialize`** — new macro for populating
  `ctx[:contract]` from submitted params.
  - Calls `contract.deserialize(params)` with params read from a
    configurable ctx path.
  - No-op when the path is absent — safe for fresh-form GETs before any
    params have been posted.
  - Configure name is `:deserialize_to_contract` rather than the generic
    `:deserialize`, to avoid colliding with sequencer-local methods of
    the same name.

- **`Hubbado::Sequence::Runner`** — outcome-dispatch + safety-net logic
  extracted from `RunSequence` into a standalone object.
  - Ships with its own `Substitute` for unit-testing the dispatch
    behaviour in isolation.
  - `Runner.build` factory lets `Runner.configure` install it as a
    dependency on any consumer.
  - `RunSequence` is now a thin delegator that retains its existing
    controller-side API; no migration is needed for controllers already
    using `run_sequence`.

- **`Hubbado::Sequence::Path.resolve`** — shared ctx-path helper used by
  every macro that reads a configurable location from ctx.
  - Accepts a Symbol (one-key shorthand) or an Array of Symbols (nested
    fetch); walks via `fetch`.
  - Explicit `missing:` policy:
    - `:raise` (default) — propagates `KeyError`. Right for
      Find/Validate/Build, where a missing path is a wiring bug.
    - `:nil` — returns nil. Right for Deserialize, which may legitimately
      run before any params have been posted.
  - Falling back to `send` on a non-hash was considered and rejected: it
    would silently overlap path traversal with method calls and undermine
    the strict-Ctx contract.

- **`Macros::Contract::Validate`** — `from:` is now optional.
  - Omit it when the contract has already been deserialised (e.g. via
    `Contract::Deserialize`) to validate as-is and skip re-deserialising.
  - When supplied, behaviour is unchanged.

### Changed (breaking)

- **Controls factory method renamed to `example_class`**, matching the
  Eventide convention (`example` returns a configured instance,
  `example_class` returns the configurable class).
  - `Controls::Contract.klass` → `Controls::Contract.example_class`.
  - `Controls::Model.example` → `Controls::Model.example_class`.
  - `Controls::Policy.example` → `Controls::Policy.example_class`.
  - The previous shapes returned classes despite being named `example` /
    `klass`. Consumer tests need their call sites updated.

- **`Macros::Model::Find`** — `id_key:` is now a single ctx-path argument
  resolved via `Path.resolve`.
  - Accepts a Symbol (e.g. `id_key: :user_id`) or an Array of Symbols
    (e.g. `id_key: %i[params id]`).
  - Default remains `%i[params id]`.
  - Callers passing the previous shape need to switch to the path form.

- **`Macros::Contract::Build`** — the model attribute is now optional and
  accepts a ctx-path.
  - Symbol or Array of Symbols, resolved via `Path.resolve`.
  - Omit it for contract-first flows where there is no model yet.
  - Previous form (single Symbol naming a top-level ctx key, required)
    continues to work because a Symbol is a valid path.

### Removed

- **`I18n.default_locale = :en` override** no longer set by
  `lib/hubbado/sequence.rb` on require.
  - Host apps are responsible for their own I18n configuration.
  - The gem's translation registration (`I18n.load_path += …`) is
    unchanged — `config/locales/en.yml` still ships and is still loaded.

## [0.2.0] - Sequencer mixin moved off the namespace

### Changed (breaking)

- The sequencer mixin moved from `Hubbado::Sequence` to a dedicated
  `Hubbado::Sequence::Sequencer` submodule. Clients now write
  `include Hubbado::Sequence::Sequencer` instead of `include Hubbado::Sequence`.
  The top-level `Hubbado::Sequence` module is now a pure namespace, leaving
  `Sequence::Pipeline`, `Sequence::Ctx`, `Sequence::Result`, etc. unaffected by
  including the sequencer machinery and avoiding constant-lookup leakage from
  the namespace into including classes. No deprecation shim — call sites must
  be updated in lockstep with the gem upgrade.

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
