# hubbado-sequence

A small framework for orchestrating units of business behaviour. The eventual
replacement for Trailblazer operations at Hubbado, designed to coexist with
them during migration.

A sequencer takes input, runs a sequence of steps, and returns a `Result`
indicating success or failure plus the working context that was built up
during execution.

The full design rationale lives in [`docs/design.md`](docs/design.md). This
README is a quick tour.

## Installation

Add to your Gemfile:

```ruby
gem "hubbado-sequence"
```

Then run `bundle install`.

## Requirements

- Ruby >= 3.3
- [evt-dependency](https://github.com/eventide-project/dependency) —
  dependency injection (declared as a runtime dependency of the gem).

Optional, depending on which macros you use:

- [ActiveRecord](https://github.com/rails/rails) for `Model::Find`,
  `Model::Build`, and `Pipeline#transaction`.
- [Reform](https://github.com/trailblazer/reform) for `Contract::Build`,
  `Contract::Deserialize`, `Contract::Validate`, and `Contract::Persist`.
- [hubbado-policy](https://github.com/hubbado/hubbado-policy) for
  `Policy::Check`.

## Philosophy

Sequencers sit at the controller boundary. They receive input, orchestrate
the work, and hand a `Result` back. The sequencer's job is **orchestration
only** — it should not contain business logic itself. Real behaviour lives
in the models, contracts, policies, and domain objects it calls.

The framework is built with Rails in mind but doesn't require it — the core
of the gem has no Rails dependency, and `Hubbado::Sequence::RunSequence` is
a plain mixin that works in any host that drives a sequencer from a fixed
lifecycle (Sinatra actions, Rack handlers, Hanami actions, job workers).
ActiveRecord and Reform are only needed if you use the macros that wrap
them.

In a Rails context the gem solves a specific pain: a controller action is
hard to unit-test because the framework owns its lifecycle, and that gets
worse the moment you want dependency injection. Sequencers lift the
testable work *out* of the controller into a plain Ruby object that
exposes its dependencies cleanly, and `run_sequence` keeps the controller
itself thin — branching to redirect, render, or set a flash based on the
sequencer's outcome.

Most controller actions shouldn't contain much business logic anyway. They're
a short sequence of common steps — find a model, validate a contract, save
something, redirect. The sequencer DSL is designed to make that high-level
sequence compact and easy to scan, without trying to be the home for the
business logic underneath. Regular Ruby is already excellent at that.

The DSL is deliberately minimal. A sequencer's `pipeline(ctx)` block is a
small set of conventions around how `ctx` flows and what each step
returns — nothing more. Steps are regular methods on a regular Ruby
object, dependencies are regular Ruby objects, and the pipeline lets you
use regular Ruby `if` / `unless` / `case` for control flow rather than
inventing a conditional DSL. Where the framework can get out of your way,
it does.

The gem doesn't impose a nesting depth, but in practice we keep nesting
very shallow — typically one level. The only nesting we use is a `Present`
sequencer inside an `Update` sequencer: Present loads the record, builds
the contract, and checks the policy; Update calls Present and then
validates and persists. Anything deeper is a signal that a chunk of the
work should be a plain Ruby object instead.

The framework uses [evt-dependency](https://github.com/eventide-project/dependency)
for dependency injection. Every macro and every nested sequencer is an
injected dependency, which means calling `.new` on a sequencer installs
substitutes for all of them. Unit tests exercise the sequencer's
orchestration logic — what runs, in what order, what short-circuits —
without hitting the database, the policy gem, or Reform. The substitutes
default to pass-through success, so a test only configures the outcomes
that matter for the scenario it's verifying.

Integration coverage (using `.build` to wire real collaborators) is
reserved for the controller boundary — one happy-path integration test
per sequencer is usually enough to confirm the wiring is correct.

## Quick start

```ruby
class Seqs::UpdateUser
  include Hubbado::Sequence::Sequencer

  dependency :find,           Macros::Model::Find
  dependency :build_contract, Macros::Contract::Build
  dependency :check_policy,   Macros::Policy::Check
  dependency :validate,       Macros::Contract::Validate
  dependency :persist,        Macros::Contract::Persist

  def self.build
    new.tap do |instance|
      Macros::Model::Find.configure(instance)
      Macros::Contract::Build.configure(instance)
      Macros::Policy::Check.configure(instance)
      Macros::Contract::Validate.configure(instance)
      Macros::Contract::Persist.configure(instance)
    end
  end

  def call(ctx)
    pipeline(ctx) do |p|
      p.invoke(:find,           User,                  as: :user)
      p.invoke(:build_contract, Contracts::UpdateUser, :user)
      p.invoke(:check_policy,   Policies::User,        :user, :update)

      p.transaction do |t|
        t.invoke(:validate, from: %i[params user])
        t.invoke(:persist)
      end
    end
  end
end

# In a controller:
class UsersController < ApplicationController
  include Hubbado::Sequence::RunSequence

  def update
    run_sequence Seqs::UpdateUser, params: params, current_user: current_user do |result|
      result.success           { |ctx| redirect_to ctx[:user] }
      result.policy_failed     { |ctx| redirect_to root_path, alert: result.message }
      result.not_found         { |ctx| render_404 }
      result.validation_failed { |ctx| render :edit, locals: { contract: ctx[:contract] } }
    end
  end
end
```

## The two step shapes

```ruby
pipeline(ctx) do |p|
  p.invoke(:find, User, as: :user)  # declared dependency (macro or sequencer)
  p.step(:scrub_params)             # local method `def scrub_params(ctx)`
end
```

- `p.invoke(:foo, *args, **kwargs)` — a `dependency :foo, …` declared on the
  sequencer (a macro or a nested sequencer). Calls
  `dispatcher.foo.(ctx, *args, **kwargs)`.
- `p.step(:foo)` — a local instance method. Dispatches to `self.foo(ctx)`.

Every `step` is a method on the sequencer with the same name as the step.
This makes the `call` body a table of contents — scan `p.step(:...)` lines
to see the sequence shape, jump to the method for details.

`pipeline(ctx)` is the only way to build a pipeline. The underlying
Pipeline class is an implementation detail; sequencers do not construct
it directly.

## Built-in macros

Each macro is a dependency declared on a sequencer with `dependency :name, Macros::...`
and wired via `.configure(instance)` in `.build`. The built-in macros are
grouped by the gem they expect to be available.

### ActiveRecord macros

Designed to work with [ActiveRecord](https://github.com/rails/rails) models.

#### Model::Find

Fetches a record using `model.find_by(id:)` and writes it to `ctx[as]`.

```ruby
p.invoke(:find, User, as: :user)
p.invoke(:find, User, as: :user, id_key: :user_id)   # single key
p.invoke(:find, User, as: :user, id_key: %i[params id])  # nested path (default)
```

| | |
|---|---|
| **Reads** | `ctx` at `id_key` (default: `%i[params id]`) |
| **Writes** | `ctx[as]` — the found record |
| **Fails** | `:not_found` when `find_by` returns nil |

#### Model::Build

Instantiates a new record and writes it to `ctx[as]`.

```ruby
p.invoke(:build_record, User, as: :user)
p.invoke(:build_record, User, as: :user, attributes: { role: :admin })
```

| | |
|---|---|
| **Reads** | nothing |
| **Writes** | `ctx[as]` — the new instance |
| **Fails** | never |

### Reform macros

Designed to work with [Reform](https://github.com/trailblazer/reform) form
objects (contracts).

#### Contract::Build

Wraps a model in a contract and writes it to `ctx[:contract]`.

```ruby
p.invoke(:build_contract, Contracts::UpdateUser, :user)  # model from ctx[:user]
p.invoke(:build_contract, Contracts::CreateUser)         # no model
```

| | |
|---|---|
| **Reads** | `ctx[attr_name]` for the model (optional) |
| **Writes** | `ctx[:contract]` |
| **Fails** | never |

#### Contract::Deserialize

Deserializes params into the contract via `contract.deserialize(params)`.

```ruby
p.invoke(:deserialize_to_contract, from: %i[params user])
p.invoke(:deserialize_to_contract, from: :raw_params)
```

| | |
|---|---|
| **Reads** | `ctx[:contract]`, `ctx` at `from:` |
| **Writes** | nothing (mutates the contract in place) |
| **Fails** | never (no-op when the `from:` path is absent) |

#### Contract::Validate

Validates the contract via `contract.validate(params)` and checks `errors`.

```ruby
p.invoke(:validate, from: %i[params user])
p.invoke(:validate)   # contract already deserialized; passes empty params
```

| | |
|---|---|
| **Reads** | `ctx[:contract]`, `ctx` at `from:` (when given) |
| **Writes** | nothing (populates `contract.errors` on invalid) |
| **Fails** | `:validation_failed` when `contract.errors` is non-empty |

#### Contract::Persist

Saves the contract via `contract.save`.

```ruby
p.invoke(:persist)
```

| | |
|---|---|
| **Reads** | `ctx[:contract]` |
| **Writes** | nothing |
| **Fails** | `:persist_failed` when `save` returns false |

### hubbado-policy macros

Designed to work with the
[hubbado-policy](https://github.com/hubbado/hubbado-policy) gem.

#### Policy::Check

Builds a policy and calls the named action to authorise the operation.

```ruby
p.invoke(:check_policy, Policies::User, :user, :update)
```

The policy class must respond to `.build(current_user, record)`; the
instance must respond to the action method and return an object with
`permitted?`.

| | |
|---|---|
| **Reads** | `ctx[:current_user]`, `ctx[record_key]` |
| **Writes** | nothing |
| **Fails** | `:forbidden` when `permitted?` is false; `error[:data]` carries `{ policy:, policy_result: }` |

## Transactions

`Pipeline#transaction` wraps inner steps in `ActiveRecord::Base.transaction`.
A failed inner step raises `ActiveRecord::Rollback` and the failed `Result`
still propagates outward.

```ruby
def call(ctx)
  pipeline(ctx) do |p|
    p.invoke(:find,           User,                  as: :user)
    p.invoke(:build_contract, Contracts::UpdateUser, :user)
    p.invoke(:check_policy,   Policies::User,        :user, :update)

    p.transaction do |t|
      t.invoke(:validate, from: %i[params user])
      t.invoke(:persist)
    end

    p.step(:notify)
  end
end

private

def notify(ctx)
  UserMailer.updated(ctx[:user]).deliver_later
end
```

Steps before the transaction run outside it (read-only lookups, policy
checks). Steps after run after commit (notifications, emails — things that
shouldn't run if the DB write didn't stick).

When ActiveRecord isn't loaded, `transaction` runs the inner block inline
as part of the same pipeline.

## Nested sequencers (Present + Update)

The "find the record, build the contract, check the policy" shape is shared
between an edit form and an update action — both need exactly that, and the
update then validates and persists. Define Present as a nested class on the
outer sequencer so the two stay co-located:

```ruby
class Seqs::UpdateUser
  class Present
    include Hubbado::Sequence::Sequencer

    configure :present   # so a parent can use `Present.configure(instance)`

    dependency :find,           Macros::Model::Find
    dependency :build_contract, Macros::Contract::Build
    dependency :check_policy,   Macros::Policy::Check

    def self.build
      new.tap do |instance|
        Macros::Model::Find.configure(instance)
        Macros::Contract::Build.configure(instance)
        Macros::Policy::Check.configure(instance)
      end
    end

    def call(ctx)
      pipeline(ctx) do |p|
        p.invoke(:find,           User,                  as: :user)
        p.invoke(:build_contract, Contracts::UpdateUser, :user)
        p.invoke(:check_policy,   Policies::User,        :user, :update)
      end
    end
  end

  include Hubbado::Sequence::Sequencer

  dependency :present,  Present
  dependency :validate, Macros::Contract::Validate
  dependency :persist,  Macros::Contract::Persist

  def self.build
    new.tap do |instance|
      Present.configure(instance)
      Macros::Contract::Validate.configure(instance)
      Macros::Contract::Persist.configure(instance)
    end
  end

  def call(ctx)
    pipeline(ctx) do |p|
      p.invoke(:present)

      p.transaction do |t|
        t.invoke(:validate, from: %i[params user])
        t.invoke(:persist)
      end
    end
  end
end
```

The edit action runs Present and renders the form; the update action runs
Update and either redirects or re-renders:

```ruby
class UsersController < ApplicationController
  include Hubbado::Sequence::RunSequence

  def edit
    run_sequence Seqs::UpdateUser::Present, params: params, current_user: current_user do |result|
      result.success       { |ctx| render :edit, locals: { contract: ctx[:contract] } }
      result.policy_failed { |_|   redirect_to root_path, alert: result.message }
      result.not_found     { |_|   render_404 }
    end
  end

  def update
    run_sequence Seqs::UpdateUser, params: params, current_user: current_user do |result|
      result.success           { |ctx| redirect_to ctx[:user] }
      result.policy_failed     { |_|   redirect_to root_path, alert: result.message }
      result.not_found         { |_|   render_404 }
      result.validation_failed { |ctx| render :edit, locals: { contract: ctx[:contract] } }
    end
  end
end
```

Inner writes (`ctx[:user]`, `ctx[:contract]`) are visible to outer steps —
Present and Update share the same `Ctx`, so `:validate` and `:persist` see
exactly what Present built. The outer pipeline records `:present` as a single
entry in `successful_steps`; Present's inner steps stay opaque to the parent.

## Result, success, failure

A step is **successful unless it explicitly returns a failed `Result`**. Any
other return value (`nil`, `false`, a model, `Result.success(...)`) is taken as
success and the pipeline continues with the same `ctx`. Only
`Result.failure(...)` or the `failure(ctx, code: ...)` helper short-circuits.

```ruby
def call(ctx)
  pipeline(ctx) do |p|
    p.step(:must_be_premium)
    p.invoke(:persist)
  end
end

private

def must_be_premium(ctx)
  return failure(ctx, code: :forbidden) unless ctx[:user].premium?
  # implicit success if we get here
end
```

`failure(ctx, ...)` is a sequencer helper that builds a failed `Result`
with the sequencer's auto-derived i18n scope already applied. It takes the
same error attrs as the underlying error hash (`code:`, `i18n_key:`,
`i18n_args:`, `data:`, `message:`).

## Testing

The gem doesn't prescribe a testing library — sequencers, macros, and
substitutes are plain Ruby objects that work with whatever you use.
The examples below are written in
[TestBench](https://github.com/test-bench/test-bench) (what we use at
Hubbado), but the same patterns translate directly to RSpec, Minitest,
or any other framework.

`Seqs::UpdateUser.new` returns a sequencer with all dependencies installed
as substitutes. Tests configure the substitutes for the scenario at hand.
`Seqs::UpdateUser.build` runs the production wiring (the real macros).
Substitutes default to pass-through `Result.success(ctx)` so a test only
configures the ones whose return matters.

### Substituting macros directly

```ruby
context "Seqs::UpdateUser::Present happy path" do
  user     = User.new(id: 1, email: "old@example.com")
  contract = Contracts::UpdateUser.new(user)

  seq = Seqs::UpdateUser::Present.new
  seq.find.succeed_with(user)
  seq.build_contract.succeed_with(contract)

  result = seq.(params: { id: 1 }, current_user: User.new)

  test "Is success" do
    assert(result.success?)
  end

  test "Fetched the user from ctx[:user]" do
    assert(seq.find.fetched?(as: :user))
  end

  test "Built the contract" do
    assert(seq.build_contract.built?)
  end

  test "Checked the policy" do
    assert(seq.check_policy.checked?)
  end
end

context "Seqs::UpdateUser::Present when the user is not found" do
  seq = Seqs::UpdateUser::Present.new
  seq.find.fail_with(code: :not_found)

  result = seq.(params: { id: 999 }, current_user: User.new)

  test "Fails with :not_found" do
    assert(result.error[:code] == :not_found)
  end

  test "Does not build the contract" do
    refute(seq.build_contract.built?)
  end

  test "Does not check the policy" do
    refute(seq.check_policy.checked?)
  end
end
```

### Substituting a nested sequencer

Every sequencer ships a default `Substitute` module (installed by
`include Hubbado::Sequence::Sequencer`) with `succeed_with(**ctx_writes)` /
`fail_with(**error)` / `called?(**partial_kwargs)`. The parent's tests can
short-circuit a nested sequencer without reaching into its inner pieces:

```ruby
context "Seqs::UpdateUser happy path" do
  user     = User.new(id: 1, email: "old@example.com")
  contract = Contracts::UpdateUser.new(user)

  seq = Seqs::UpdateUser.new
  seq.present.succeed_with(user: user, contract: contract)

  result = seq.(
    params:       { user: { email: "new@example.com" } },
    current_user: User.new
  )

  test "Is success" do
    assert(result.success?)
  end

  test "Calls Present" do
    assert(seq.present.called?)
  end

  test "Persists the contract" do
    assert(seq.persist.persisted?)
  end
end

context "Seqs::UpdateUser when Present denies access" do
  seq = Seqs::UpdateUser.new
  seq.present.fail_with(code: :forbidden)

  result = seq.(params: { user: {} }, current_user: User.new)

  test "Fails" do
    assert(result.failure?)
  end

  test "Fails with :forbidden" do
    assert(result.error[:code] == :forbidden)
  end

  test "Does not validate" do
    refute(seq.validate.validated?)
  end

  test "Does not persist" do
    refute(seq.persist.persisted?)
  end
end

context "Seqs::UpdateUser when Present cannot find the record" do
  seq = Seqs::UpdateUser.new
  seq.present.fail_with(code: :not_found)

  result = seq.(params: { id: 999, user: {} }, current_user: User.new)

  test "Fails with :not_found" do
    assert(result.error[:code] == :not_found)
  end

  test "Does not validate" do
    refute(seq.validate.validated?)
  end

  test "Does not persist" do
    refute(seq.persist.persisted?)
  end
end
```

`succeed_with(**ctx_writes)` writes the given keys into `ctx` and returns
`Result.success(ctx)`, so the outer steps see what the real Present would have
left behind. `fail_with(**error)` returns a failed `Result` with the given
error, short-circuiting the outer pipeline. The Update spec doesn't need
to exercise Find / Build / Policy::Check directly — those live in
`Seqs::UpdateUser::Present`'s spec, where they belong.

## Observability

Every `Result` carries **successful_steps** — the list of step names that
completed successfully, in order. On failure, the failing step is *not* in
`successful_steps`; it's tagged on `error[:step]` instead.

```ruby
result.successful_steps  # => [:find, :build_contract, :check_policy, :validate, :persist]  # success
result.successful_steps  # => [:find, :build_contract]                                       # failed at :check_policy
result.error[:step]      # => :check_policy
```

When invoked via `run_sequence`, the dispatcher logs a single line per
invocation summarising the successful steps and (on failure) where it
stopped:

```
Sequencer Seqs::UpdateUser succeeded: find → build_contract → check_policy → validate → persist
Sequencer Seqs::UpdateUser failed at :check_policy (forbidden): find → build_contract
```

Nested sequencer steps are opaque to the parent: a parent's `successful_steps`
lists `:present` once, not Present's inner sub-steps.
`error[:step]` carries the inner step name when a nested sequencer fails.

## Standard error codes

- `:not_found` — `Model::Find` couldn't find the record.
- `:forbidden` — policy denied.
- `:validation_failed` — contract invalid; see `ctx[:contract].errors`.
- `:persist_failed` — save failed for non-validation reasons.
- `:conflict` — uniqueness or optimistic locking.

Sequencers can mint their own codes for domain-specific failures
(`:not_shippable`, `:already_cancelled`).

## Documentation

- [`docs/design.md`](docs/design.md) — full design and rationale (decisions
  considered and rejected, "Resolved Through Iteration" log of reversals,
  open questions).

## License

Released under the [MIT License](LICENSE).
