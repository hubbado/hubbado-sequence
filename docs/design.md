# Sequencer: Design Rationale

This document records the decisions made when building Sequencer — the
alternatives we considered and rejected, and the reversals we made along the
way. It is not a usage reference; see [`../README.md`](../README.md) for that.
The point is to preserve the reasoning so a future maintainer doesn't
re-litigate questions that have already been settled.

## Overview

Sequencer is a small framework for orchestrating units of business behaviour
in Hubbado. It is the eventual replacement for our use of Trailblazer
operations, and it is designed to coexist with them during migration.

The core proposition is small: about 200 lines of framework code, plus a
handful of conventions that give it identity. Most of the value is in the
conventions, not the code.

## Naming

We landed on **Sequencer** with the namespace `Seqs::`. The shape we needed
to name was: a class that orchestrates other things (macros, methods, nested
sequencers), runs them in a defined order, short-circuits on failure, and
returns a result. "Sequencer" describes that accurately, the namespace
abbreviates well to `Seqs`, and it doesn't collide with anything in our
existing stack.

Names we considered and rejected:

- **Operation** — overlaps with existing Trailblazer operations during the
  migration period. Confusing.
- **Command** — overlaps with Eventide's `Messaging::Message` commands.
- **Action** — heavily overloaded by Rails (`ActionController`, `ActionMailer`,
  `ActiveJob#perform`).
- **Job** — taken by `ActiveJob`.
- **Interactor** — taken by the `interactor` gem.
- **UseCase** — clean but slightly academic. No abbreviation.
- **Procedure** — accurate but unusual. No abbreviation.
- **Service** — too generic. Every Rails app has `app/services`.
- **Workflow** — implies multi-step long-running, doesn't fit single-step
  cases.
- **Orchestrator** — accurate to what these things do, but doesn't abbreviate
  well. `Orchs::` reads badly.
- **Coordinator**, **Conductor**, **Director**, **Choreographer** — all close
  in meaning to Orchestrator, all worse abbreviations.

The cost of "Sequencer" being slightly off for the trivial case (a sequencer
with one step isn't really sequencing anything) was judged acceptable.
Orchestrator has the same problem.

## Goals

The starting point was an inventory of what we like and dislike about
Trailblazer.

What we kept from Trailblazer:

- The macro pattern: reusable, configurable units that handle common
  concerns (find a record, validate a contract, check a policy, persist a
  contract).
- The railway: a sequence of steps that short-circuits on the first failure.
- A shared context that accumulates state through the pipeline and is
  available to the caller after completion.
- Categorical outcome handling (success / policy_failed / not_found /
  validation_failed / otherwise) at the controller boundary, with safety
  nets that raise if a serious failure isn't handled.

What we rejected from Trailblazer:

- **`.build` is private.** Trailblazer doesn't let us instantiate operations
  with our own dependencies. We need to, both for production wiring and for
  tests that substitute dependencies.
- **Calling another operation is awkward.** Nested operations require
  `Subprocess` with input/output mappings. We wanted nested calls to feel
  like calling any other Ruby object.
- **Macros aren't dependencies.** In Trailblazer, macros are DSL-level
  things, not objects we can inject. We wanted them to be dependencies so
  they can be substituted in tests.
- **Nested operations are hard to substitute.** With macros and nested
  operations as first-class dependencies, tests can swap any of them out at
  any depth.

Specific Trailblazer pain points the design addresses:

- Dynamic policy lookup. Trailblazer's `Policy::Pundit` macro is rigid; once
  you reach for `Policy::Guard` to do anything dynamic you lose the
  structured policy result and the macro semantics diverge from the static
  case. We want one shape regardless of how the policy is selected.
- Errors scattered across `ctx['result.policy.default']`, `ctx['contract.default'].errors`,
  the operation's terminus, and the implicit success/failure of the ctx
  itself. We want one place for control-flow signals (`Result#error`) and
  one place for user-facing errors (the contract).

## Architecture

The framework has three layers:

- **Core (always used)** — a Sequencer (the orchestration unit), a Result
  (value object wrapping ctx + ok/fail flag + structured error + i18n
  scope), a Ctx (strict hash carrying inputs, intermediate values, and
  outputs), and the structured error payload.
- **Railway helper** — a Sequencer's `pipeline(ctx) { |p| ... }` helper
  runs a sequence of named steps, short-circuits on failure, and tags
  errors with their step name. The Pipeline class behind it is an
  implementation detail; sequencers reach it through the helper, not
  directly.
- **Reusable steps** — Macros that capture common concerns (model lookup,
  contract handling, policy checks) as configurable, substitutable
  dependencies.

A sequencer doesn't have to use the `pipeline` helper. The minimum
contract is "returns a Result." Trivial sequencers can hand-build the
Result and skip the rest.

## The Result and Ctx Shape

We considered several options for how steps communicate.

**Each step returns its own Result with its own ctx.** Rejected. Either the
step gets the parent ctx, mutates it, *and* returns a Result (belt and
braces, the Result's ctx is redundant), or steps return Results carrying
just their outputs and the railway has to merge keys back into a parent ctx.
The second is cleaner in principle but requires every macro to declare what
keys it exposes, and at that point you've reinvented half of `dry-monads`
or `dry-transaction`.

**Single-value threading (the article's `.then` chain).** Rejected because
once a step needs more than the previous step's single output, you end up
threading tuples (`Success([user, params])`) or closing over instance
variables. A shared ctx sidesteps the issue.

**Shared mutable ctx, steps return truthy/falsy.** Considered. Simple but
loses the structured error payload that lets controllers categorise failures.

**Shared mutable ctx, steps return a Result wrapping that same ctx.** What
we picked. The ctx is the value that rides the railway. A step always
receives the ctx and always returns a `Result` whose `ctx` is that same
object — `Result.success(ctx)` on success, `Result.failure(ctx, error: ...)` on
failure. The Result tells the caller what happened; the ctx tells the
caller what was built.

This has two important properties:

- Even when a step fails, the caller still gets everything that was written
  to ctx by the steps that ran before it. `result.ctx[:user]` is populated
  even if a later step failed. This is what lets a controller re-render a
  form on validation failure with the contract from ctx.
- Calling another sequencer is just another step. Because sequencers return
  `Result`, and steps return `Result`, a sequencer *is* a step. No adapter
  needed.

### Strict Ctx

`Ctx` is a `Hash` subclass that raises on missing keys via `[]`. This catches
typos and ordering errors at the failure site rather than three steps later
when something else blows up because it got `nil`. `fetch` is preserved
unchanged, so optional reads use `ctx.fetch(:locale, :en)` in the standard
Ruby way.

## The Pipeline

We considered three sequencing approaches.

**A `step :name` declarative DSL** (Trailblazer-style). Lists steps at the
class level and a runner walks them. Considered but rejected because it
made calling other sequencers awkward (every nested call needs a wrapping
step adapter), and conditional flow becomes DSL growth rather than plain
Ruby.

**A `.then` chain** (article-style). Result has a `.then` method that
yields ctx if ok, returns self if failed. Considered, and we got far enough
to question whether we even needed a custom `then` method. We could:

- Use `Kernel#then` with explicit guards in every block (`r.success? ? step.(r.ctx) : r`)
  — works but ugly.
- Use `reduce` with a lambda — pure Ruby but inflexible.
- Raise on failure and `rescue` at the operation boundary — pragmatic but
  brings back exception-driven control flow, which is what railway-oriented
  design was reacting against.
- `catch`/`throw` — works but unusual.
- A custom method — most idiomatic for Ruby with method dispatch.

We were going to land on `.then` on a Pipeline object (rather than directly
on Result, to keep Result a pure value object), but realised that once
`step` always takes a name (for failure tagging and observability), `.then`
adds nothing. We dropped `.then` and kept `step`.

**Block form `pipeline(ctx) do |p| ... end`** — what we picked. The block
form yields the pipeline, runs the block, and returns the final `Result`
automatically. Conditionals and branching are plain Ruby because each
`p.step` is a statement, not a chained call.

Each `step` takes a name. The step name is mandatory. This forces every
step to be identifiable in failures and logs, and reads as documentation —
you can see the sequencer's shape at a glance.

### Auto-dispatch is the only step form

`p.step(:foo)` always dispatches to `self.foo(ctx)` on the sequencer. No
inline-block step bodies — every step is a method on the sequencer with
the same name. This makes the `call` body a pure table of contents: the
reader scans `p.step(:...)` lines to see the sequence shape, then jumps
to the method when they want details.

Missing methods raise `NoMethodError` with the step name and the
sequencer class in the message — no silent fall-through, no
`respond_to_missing?` magic.

### Lenient return convention

A step is treated as successful unless it explicitly returns a failed
`Result`. Any other return value (`nil`, `false`, a model, a hash,
`Result.success(...)`) is taken as success and the pipeline continues. Only
`Result.failure(...)` / `failure(ctx, code: ...)` short-circuits.

The trade-off: a step method that *meant* to write to ctx but accidentally
returned a stray value silently passes. With strict `Ctx` still in place,
the missing key surfaces at the next read site rather than at the offending
line — so you'll find the bug, just one step later. We took the ergonomic
win after seeing how much `Result.success(ctx)` ceremony piled up in real
sequencers.

### The `pipeline` helper isn't required

A sequencer's only contract is "returns a Result". It can hand-build one.
This is a feature: it keeps the helper honest by forcing it to earn its
place over raw Ruby, and it lets trivial sequencers stay trivial.

### Pipeline is internal

The Pipeline class behind the `pipeline(ctx)` helper is not part of the
public API. Sequencers reach Pipeline through `pipeline(ctx)`, never
through `Pipeline.(ctx)` directly. Two reasons:

- **No use case for the bare class.** Without inline-block step bodies
  every step is a method on the dispatcher, so a Pipeline without a
  dispatcher can't run anything. The only callers that ever wanted bare
  `Pipeline.()` were the framework's own tests.
- **One way to do it.** A user-facing class that only works through one
  specific call site is a confusion magnet. Folding it into a single
  helper removes the "which one do I call?" question entirely.

Framework tests still exercise Pipeline directly, but they construct it
the same way the helper does — `Pipeline.new(ctx, dispatcher: self)` —
with a test-local dispatcher that holds the step methods.

## Errors

We separated two things that both get called "errors":

1. **Step failure** — the Result is fail, with a structured error explaining
   why. Lives on the Result, not in ctx. Used for control flow.
2. **User-facing validation errors** — per-field messages for re-rendering
   a form. Lives on the contract (`ctx[:contract].errors`).

These are different things. The step failure says "the operation stopped
here." The validation errors say "the form was bad, here's what to tell the
user." A failed validation step produces *both*: a `:validation_failed`
Result *and* a populated contract.

Why both? Because the controller needs both. `result.success?` tells it whether
to redirect or re-render. `ctx[:contract].errors` tells it what to render.
`result.error[:code]` tells it the HTTP status.

We initially considered a third location, `ctx[:errors]`, but dropped it.
The contract owns user-facing errors; the Result owns operational errors.
Two places, clear ownership.

### Where Different Failures Go

The mental test: "if I were rendering this in a form, where would the user
expect to see it?"

- **Per-field validation errors** → `contract.errors[field]`. Result fails
  with `:validation_failed`.
- **Non-field domain rule failures, when a contract exists** →
  `contract.errors[:base]`. Result fails with a semantic code
  (`:invalid_state`, `:not_shippable`).
- **Failures with no contract** (e.g. `Model::Find` not finding the record)
  → Result error only.
- **Policy denial** → Result error only, code `:forbidden`. Don't put policy
  denials on the contract — they're not about the input, they're about
  authorization.
- **Infrastructure failures** → Result error only, code like
  `:persist_failed`.

### Error Payload

The error hash distinguishes `code` (the stable semantic identifier callers
match against) from `i18n_key` (the translation handle). They're separate
fields because the code is stable — changing it breaks controllers — and
the translation handle is volatile, changing whenever copy is edited.

### i18n

`Result#message` translates the error using a fallback chain:

1. Per-error scope override (if the error sets `i18n_scope:`)
2. Sequencer's auto-derived scope (matching the convention in
   `hubbado-policy`: `Seqs::UpdateUser` → `seqs.update_user`)
3. Framework default (`sequence.errors.<code>`)
4. The `message:` field on the error
5. Humanized code (`"Not found"`)

The chain means a fresh app gets sensible behaviour with zero config (the
gem ships translations for the standard codes), apps can override per-code
in their own locale files, and missing translations degrade gracefully to
humanised codes.

For nested sequencers, the innermost scope wins. If `UpdateUser` calls
`Present` and Present's `Model::Find` fails, the Result is tagged with
Present's scope, and `UpdateUser`'s class-level `with_i18n_scope` is a
no-op when the Result already has one. This means errors are translated
under the namespace of the sequencer that actually produced them, not the
outermost wrapper.

### `failure` Helper

Inside a sequencer, `failure` builds a failed Result with the sequencer's
scope auto-applied.

We considered `fail_sequence` / `pass_sequence`, but the asymmetry didn't
exist (success has no i18n concerns to fix), and `failure` reads better
alongside `result.failure?`. We didn't add a `success` helper because
`Result.success(ctx)` is already short and i18n-free.

## Macros

A macro is a reusable step class that encapsulates a common concern.

We considered making more things macros and considered making fewer things
macros. The discipline test we landed on: **a macro earns its place when it
captures a pattern with non-trivial logic that's worth substituting in
tests, or when removing it would force the same `Result.success` ceremony into
many sequencers.**

The framework's discipline is that adding a new macro should require
demonstrating that it captures real reusable logic with a real failure
mode, not just that it's "common."

### Macro Configuration

Macros use `evt-configure` (already part of our Eventide-based stack) to
expose themselves as dependencies. `configure` takes only the receiver and
an optional `attr_name:` — no structural parameters. The macro instance is
generic; everything per-invocation comes through `call`.

Earlier iterations split arguments into **configure-time** (the model
class, the policy class — bound once to the macro instance) and
**call-time** (where in ctx to read from, where to write to, the action).
We moved everything to call time. Three reasons:

- **Substitute validation.** With the class at call time, the substitute
  receives it on every call and can validate against it — for example,
  `Policy::Check::Substitute` raises if the configured policy doesn't
  declare the requested action. With the class at configure time, the
  substitute had no way to see what `.build` was given (different
  construction paths) and so couldn't catch policy-action typos at
  unit-test level.
- **Uniformity with `Contract::Build`.** That macro already took
  `contract_class` at call time. Splitting the others between
  configure-time class and call-time everything-else was the worst of both.
- **The class is the most important argument.** Reads naturally as the
  first user-supplied positional, with the rest of the call-site
  documenting how the operation uses that class.

Symbol arguments that **name a destination** in ctx (where the result will
be written) are kwargs — `as:` for Find and Build. Symbol arguments that
**reference an existing ctx slot** (record to authorize, model to wrap)
stay positional, because they're inputs the operation acts on, not output
annotations.

### Macro Substitutes

Each macro provides a `Substitute` class that records calls and exposes
`succeed_with(...)` and `fail_with(...)` for setup, plus inspection methods
that take keyword args for partial matching. This matches the Eventide
convention.

We initially proposed `result =` as the setter (`find.result = user`) but
rejected it: ambiguous (is "result" the Result object or the value?) and
asymmetric. `succeed_with`/`fail_with` are symmetric, self-documenting, and
the substitute internally handles wrapping in a `Result.success` or `Result.failure`.

Default behaviour for an unconfigured substitute is pass-through:
`Result.success(ctx)` with no mutation. This means tests only configure the
substitutes whose return matters, and everything else just passes through.

## Sequencers

A sequencer is a class that includes `Hubbado::Sequence::Sequencer`,
declares its dependencies, defines a `build` factory, and implements `call`.

### Call Signature

A sequencer's instance `call` takes a `Ctx`. The class-level `.()` shorthand
bridges the kwargs world (controllers and other top-level callers) to the
ctx world by building a `Ctx` from its kwargs and delegating to the
instance.

We considered two conventions for sequencer `call`:

- **`call(ctx)`** — uniform with steps and macros, ctx flows through
  unchanged when nested.
- **`call(**kwargs)`** — kwargs become a fresh ctx, signature documents
  inputs.

We picked **`call(ctx)`** at the instance level (kwargs at the class level).
Reasons:

- **Symmetry with macros and steps.** A nested sequencer is "wired the same
  way as a macro"; the call sites should match too. With ctx-passing,
  nesting is `present.(ctx)` — visually identical to a macro call. With
  kwargs, nesting requires `present.(**ctx)` splatting, which strips the
  `Ctx` object identity at the boundary and silently produces a fresh ctx
  inside the nested sequencer; the inner sequencer's writes then never
  reach the parent.
- **Composability without merging.** Because the same `Ctx` instance flows
  through the inner pipeline, the inner sequencer's mutations are
  automatically visible to subsequent outer steps. The design's "shares
  ctx happily" claim is now mechanically true rather than aspirational.
- **Documented contract argument doesn't survive contact with the body.**
  `def call(params:, current_user:)` documents the two kwargs the *outer*
  caller passes — but a real sequencer reads many things from ctx. The
  signature was never going to be the source of truth; ctx access is.
  Strict `Ctx` already raises `KeyError` on a missing read, with the
  failing step name in successful_steps, so the "fail-fast at the boundary"
  property is preserved with only a small shift in *where* the failure
  surfaces.
- **The kwargs-at-the-controller property is preserved** by the class-level
  `.()`. Only the *internal* convention flipped.

Steps and macros stay `call(ctx, ...)` for the same reason — they're
internal and always work with the assembled ctx.

### Sequencers as Dependencies

A sequencer can be a dependency of another sequencer, declared and wired
the same way as a macro. We use `evt-configure`'s `configure :name` to give
the sequencer a default attribute name, and the parent uses
`Present.configure(instance)` to wire it in.

This makes nesting symmetric to macros at the use site — whether a
dependency is a macro or a sequencer doesn't change how it's wired or how
it's substituted.

We use this primarily for Present sequencers nested inside Update
sequencers. The Present loads the model, builds the contract, and checks
the policy; the Update calls Present and then validates and persists. This
shares authorization and form construction between the edit and update
actions.

Earlier we considered making nested operations a more elaborate first-class
concept (with input/output mappings, scoped ctx, etc., as Trailblazer's
`Subprocess` does). We rejected this after noting that the only nesting we
actually use in practice is Present-inside-Update, which is shallow, shares
ctx happily, and writes the keys the parent expects. Anything more
complicated is better expressed as plain Ruby calling another sequencer
than as a framework feature.

### Why Build is Public

`build` is a regular class method. This is one of the central things we
wanted to fix from Trailblazer, where `build` is private and tests can't
substitute dependencies cleanly. Callers can use any of:

- `Seqs::UpdateUser.(params: ..., current_user: ...)` — production use,
  outermost call (kwargs become the initial ctx).
- `Seqs::UpdateUser.(some_ctx)` — pass an existing ctx through, used when
  one sequencer invokes another at the class level rather than as a
  declared dependency.
- `Seqs::UpdateUser.build` — get a configured instance for inspection.
- `Seqs::UpdateUser.new` — get an instance with substitutes installed, for
  tests.

## Testing

`described_class.new` returns a sequencer with all dependencies installed
as substitutes. Tests configure the substitutes for the scenario at hand
and call the sequencer.

Properties this enables:

- Each test exercises one decision point. Unconfigured substitutes
  pass-through, so you don't set up everything for every test.
- Substitution is recursive. A nested sequencer's substitutes are reachable
  through `seq.present.find.succeed_with(...)`.
- Assertions are about codes and recorded interactions, never about
  translated messages. Translation changes don't break tests.

### Substitute validation: what it catches and what it doesn't

The macros take their classes (model, policy, contract) at call time, so
substitutes receive the same arguments at the same time the real macro
would. That lets the substitute introspect the configured class and reject
typos before they reach production:

- `Macros::Policy::Check::Substitute` raises `ArgumentError` if the policy
  class doesn't declare the requested action method. A typo like
  `check_policy.(ctx, Policies::Job, :job, :updte)` fails at the unit-test
  level with a clear message.
- `Macros::Model::Find::Substitute` raises if the model class doesn't
  respond to `find_by` (so passing a non-AR class is caught).
- `Macros::Model::Build::Substitute` raises if the model class doesn't
  respond to `new`.

This is the closure of an earlier gap where configure-time class binding
made the substitute blind to what `.build` had been given. Moving classes
to call-time was the design lever that made it possible.

What substitutes still don't catch:

- **App-level dependencies (sequencers, services, hand-written
  substitutes).** Their substitute modules are written by the app author
  and can drift from the real class's signature.
- **Step bodies that reference constants directly** (e.g. inline
  `Cell::Form::Show::ViewModel.new(...)` in a step). Substitute tests
  don't exercise these unless they're behind a declared dependency.
- **`.build` wiring errors that aren't reachable from a substitute path.**
  A typo in `instance.build_view_model = Op::Form::BuildViewModeel` only
  blows up when `.build` runs.

Mitigation for what's left is integration coverage at the boundary:

- For sequencers reached from a controller, the existing request specs
  exercise `.build` and the real configured collaborators end-to-end.
- For sub-sequencers used internally (called from jobs, services, or other
  sequencers but not directly by a request), one happy-path integration
  test using `.build` instead of `.new` covers the same ground.

Substitute tests verify orchestration; integration tests verify that the
orchestration reaches the right real targets with valid arguments.

## Controller Integration

Controllers use `run_sequence`, which dispatches the Result to outcome
blocks and enforces safety nets matching our existing `RunOperation`
behaviour:

- Forgetting to handle `policy_failed` raises
  `Hubbado::Sequence::Errors::Unauthorized`.
- Forgetting to handle `not_found` raises `ActiveRecord::RecordNotFound`.
- Forgetting to handle any other failure raises a generic sequencer error.
- `otherwise` deliberately doesn't catch policy denials — this prevents an
  `otherwise` block accidentally rendering a form when the policy failed,
  which would be a security hole.

Sequencers are also callable bare (`Seqs::UpdateUser.(...)`) for use in
jobs, tests, and other sequencers. `run_sequence` is the standard for
controllers, not the only way to invoke.

## Observability

A sequencer's `Result` carries **successful_steps** — the list of step
names that completed successfully, in order. On failure, the failing step
is *not* in `successful_steps`; it lives on `error[:step]` instead. The two
together tell the whole story: `successful_steps` is "what got done,"
`error[:step]` is "where it stopped."

We considered recording outcomes alongside step names (`[[:find_user, :success],
...]`) but rejected it as redundant: `successful_steps` plus error
reconstructs the same information with no duplication.

The dispatcher logs a single line per sequencer invocation, summarising
the successful steps and (on failure) where it stopped. This split keeps
the layers honest:

- **Pipeline records.** It knows the steps and outcomes, has zero I/O, and
  stays trivially testable.
- **Dispatcher logs.** It's at the boundary, holds the logger, knows the
  sequencer name and outcome category. One log line per top-level
  invocation.
- **Macros stay quiet.** No logging in the hot path. No per-step
  `logger.debug` noise.

For non-controller invocations (jobs, tests, sequencers calling sequencers),
there's no dispatcher and therefore no log line. That's correct — the
outermost dispatcher is the right boundary for logging.

Nested sequencer steps are opaque to the parent: the parent's
`successful_steps` records `:present` as a single step, not the sub-steps
inside Present. If Present fails, `error[:step]` carries the inner step
name (set by Present's own Pipeline before the Result bubbles out), and
the parent's `successful_steps` shows `[:present]` was where things
stopped. This is enough to debug most failures from a single log line; if
it isn't, full nested-step flattening is something we can add later
without changing the public surface.

## Coexistence with Trailblazer

Sequencer and Trailblazer operations coexist during migration. Controllers
include both `Hubbado::Trailblazer::RunOperation` and
`Hubbado::Sequence::RunSequence` and call whichever applies. Sequencers
can call Trailblazer operations and vice versa, with appropriate adapter
steps. The Result shape is different from Trailblazer's ctx, so the
boundary is explicit when crossing it.

We're not aiming for source-compatibility with Trailblazer. The point of
building Sequencer is that we want different ergonomics; converging on the
same shape would defeat the purpose.

## What's Deliberately Not Included

- **Conditional steps / branching DSL.** Plain Ruby `if`/`unless` around
  `p.step(:foo)` lines inside the `pipeline(ctx)` block handles this. We
  don't want a `step :foo, if: :bar?` DSL because it grows without bound.
- **`pass` / `fail` step variants.** Pipeline's `step` is the only step
  type. Logging or cleanup that should run regardless of pipeline state can
  be done in the controller after `run_sequence` returns.
- **Scoped ctx for nested sequencers.** Trailblazer's `Subprocess` with
  input/output mappings isn't here. The only nested case we care about
  (Present-inside-Update) shares ctx happily. If deeper nesting becomes
  common, we'd add scoping then, not before.
- **A typed ctx schema.** Ctx is a strict hash, not a typed struct. The
  discipline comes from conventions and code review, not types.
- **Built-in retry, circuit breaking, timeout.** These are concerns for the
  layers above (job runners, HTTP clients), not for the sequencer.

## Open Questions

- **Tracing.** Our existing `TRACE_OPERATION` env var (which swaps `call`
  for `wtf?` to dump the operation's trace to stdout) is genuinely useful
  for debugging. The equivalent for Sequencer would be an env var that
  enables verbose per-step logging (input ctx keys, output ctx keys,
  timing), separate from the single-line dispatcher log. Designed but not
  yet specified.
- **Background job integration.** Jobs invoking sequencers don't have a
  controller's `current_user`. Convention for system-initiated work needs
  to be settled (probably a `System` null-object actor that policies and
  audit logging both understand). Affects every async sequencer call so
  needs to be solved before the first job-driven sequencer ships.
- **Migration playbook.** "Coexists with Trailblazer" isn't a plan. Real
  questions: do we migrate one controller action at a time? Is there a
  helper for running a Trailblazer operation from inside a sequencer (or
  vice versa) during the transition? Without a playbook the migration
  stalls.
- **Tooling for common shapes.** "Find a thing, check policy, return it"
  will be 30%+ of all sequencers. A factory like
  `Seqs::Show.for(model: User, policy: Policies::User, action: :show)`
  could write the whole sequencer. Worth designing before we accumulate 50
  near-identical hand-written sequencers.
- **Pure-computation sequencers.** A `CalculateInvoiceTotal` returns
  `ctx[:total]`, which feels forced for what's really a function. The
  framework is biased toward the CRUD shape; non-CRUD use cases fit
  awkwardly. May or may not be a real problem in practice — worth watching
  rather than designing for now.
- **Naming for non-record ctx keys.** `ctx[:user]` is clear by the
  named-records convention. `ctx[:audit_data]`, `ctx[:notification_recipients]`,
  `ctx[:price_breakdown]` aren't records and don't have an obvious naming
  rule. Probably just "use a descriptive snake_case symbol," but worth
  documenting.

## Resolved Through Iteration

For posterity, things that were originally open questions and have since
been settled:

- **Inline step blocks removed; Pipeline made internal** — originally a
  `step(:name)` accepted either a block (`step(:foo) { |ctx| ... }`) or
  was blockless and auto-dispatched to `self.foo(ctx)`. Block beat
  dispatch when both were present. The reasoning was that one-line
  steps shouldn't need a separate method.

  In practice, mixed step shapes broke scanability. Reading a real
  sequencer body now matters more than writing it — Hubbado does most
  new development with AI assistance, and review time dominates. Every
  `p.step(:name) { ... }` line forces the reader to parse "is this a
  bare step or does it have a body?" before they can move on. Uniform
  `p.step(:name)` lines remove that cost: every step looks identical at
  the call site, the sequencer body becomes a literal table of
  contents, and details live in private methods named at the same
  abstraction level.

  At the same time, `Pipeline.(ctx)` (the bare class entry point) lost
  the only reason it existed. With every step required to be a method
  on the dispatcher, a Pipeline without a dispatcher can't run
  anything. The class is still there as the implementation behind
  `pipeline(ctx)`, but it's no longer part of the public API —
  sequencers reach it only through the helper.

  The trade-off is that genuinely trivial one-line steps now require a
  one-line method (the `accept_tcs` shape, where the method body is
  `user.update!(tcs_accepted: true)` and the method name repeats the
  step name). We took the consistency win — eye velocity across the
  step list matters more than saving an indirection on individual
  trivial steps, and a sequencer body that mixes styles is the worst
  outcome of all.

- **`evt-dependency` substitute compatibility** — confirmed working. We
  use evt-dependency's "static mimic with mixed-in `Substitute` module"
  shape: each macro and each sequencer (via the mixin's auto-installed
  default) defines an inner `module Substitute` that gets mixed into the
  generated mimic. `include ::RecordInvocation` inside that module enables
  the `record def call` macro for invocation tracking. No wrapper layer
  was needed.

- **Lenient return convention for step blocks** — reversed from the
  original strict choice. Originally a step block had to return a `Result`
  or Pipeline raised `TypeError`. The reasoning was symmetry with strict
  `Ctx` and protection against a block accidentally returning the wrong
  thing. In practice, real sequencer bodies stack up `Result.success(ctx)`
  trailing lines on every step that mutates ctx but has nothing
  meaningful to return — `ctx[:job_application].save!`, `model.update!(…)`,
  inline assignments. The ceremony piles up fast, and it adds nothing
  because the macro library handles every "real" failure path on its own
  Result-returning macros. Lenient mode now treats any non-failure return
  as success: only `Result.failure(...)` / `failure(ctx, code: ...)`
  short-circuits. The footgun (a block returning a User instance instead
  of writing to ctx and returning success) still surfaces — strict `Ctx`
  raises `KeyError` at the next read site, with the failing step name
  in successful_steps — just one step later than the strict TypeError would
  have. Worth the trade for clean step bodies.

- **Pipeline records successful_steps; dispatcher logs it** — clean separation,
  no I/O in the hot path.

- **Model::Build added back** — once strict block returns made the inline
  ceremony non-trivial, having a dedicated `Model::Build` macro was worth
  the cost.

- **Contract::Deserialize added** — split out from `Contract::Validate`
  once a real use case appeared (a form whose deserialised value needed
  to be inspected or mutated before validation ran). The `from:` argument
  semantics differ: Validate's `from:` is "where to read params for this
  validation pass," Deserialize's `from:` is "where to read params to
  populate the contract," and Deserialize must be a safe no-op when the
  path isn't yet populated.

- **Instance `call` takes a Ctx; class-level `.()` accepts kwargs** —
  reversed from the original kwargs-everywhere choice. The original
  reasoning prized signature-as-documentation, but in practice that
  signature only documented the *outer* caller's two kwargs while a real
  sequencer reads many ctx keys; the documentation property leaked anyway.
  Worse, a nested call like `Other.(**ctx)` splatted the parent's `Ctx`
  into a fresh kwargs hash, which `Pipeline.()` then turned into a *new*
  `Ctx` inside the nested sequencer — so writes the inner sequencer made
  (`ctx[:contract]`, `ctx[:user]`, …) never reached the parent. The
  documented "shares ctx happily" property was structurally impossible.

  Switching to `def call(ctx)` at the instance level makes a nested call
  `Other.(ctx)` — visually and behaviourally identical to a macro step,
  with the same `Ctx` instance threaded through. The kwargs-at-the-edge
  property is preserved by the class-level `.()`, which still accepts
  kwargs from controllers and builds the initial ctx itself. Reading the
  body, not the signature, is now the way to know what a sequencer needs;
  strict `Ctx` raises `KeyError` on missing keys with the failing step
  name in successful_steps, so the fail-fast property survives intact.

  As a side effect, every sequencer now ships with a default `Substitute`
  module (added by `include Hubbado::Sequence::Sequencer`) that exposes
  `succeed_with(**ctx_writes)` / `fail_with(**error)` / `called?(...)`,
  matching the macro substitute pattern. Tests can short-circuit a nested
  sequencer with `seq.present.fail_with(code: :forbidden)` without
  reaching into its inner pieces.

- **Path traversal semantics** — settled as hash-only with an explicit
  `missing:` policy. `Hubbado::Sequence::Path.resolve` accepts a Symbol
  or Array of Symbols and walks the ctx via `fetch`. `missing: :raise`
  (the default) propagates `KeyError` — right for Find/Validate/Build
  where a missing path is a wiring bug. `missing: :nil` returns nil —
  right for Deserialize, which legitimately runs before any params have
  been posted. The earlier idea of falling back to `send` on a non-hash
  was rejected: it would have made path traversal silently overlap with
  method calls, undermining the strict-Ctx contract.
