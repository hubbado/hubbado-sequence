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
- [evt-dependency](https://github.com/eventide-project/dependency) — powers
  the injectable macro / nested-sequencer pattern (declared as a runtime
  dependency of the gem).

Optional, depending on which macros you use:

- [ActiveRecord](https://github.com/rails/rails) for `Model::Find`,
  `Model::Build`, and `Pipeline#transaction`.
- [Reform](https://github.com/trailblazer/reform) for `Contract::Build`,
  `Contract::Deserialize`, `Contract::Validate`, and `Contract::Persist`.
- [hubbado-policy](https://github.com/hubbado/hubbado-policy) for
  `Policy::Check`.

## Philosophy

Sequencers sit at the controller boundary. They receive input from a Rails
action, orchestrate the work, and hand a `Result` back. The sequencer's job
is **orchestration only** — it should not contain business logic itself. Real
behaviour lives in the models, contracts, policies, and domain objects it
calls.

Nesting is intentionally shallow. The only nesting we use in practice is a
`Present` sequencer inside an `Update` sequencer: Present loads the record,
builds the contract, and checks the policy; Update calls Present and then
validates and persists. Chains longer than one level are rare enough to be a
signal that something should be a plain Ruby object instead.

The framework uses [evt-dependency](https://github.com/eventide-project/dependency),
which means every macro and every nested sequencer is an injectable
dependency. Calling `.new` on a sequencer installs substitutes for all of
them, so unit tests exercise the sequencer's orchestration logic — what runs,
in what order, what short-circuits — without hitting the database, the policy
gem, or Reform. The substitutes default to pass-through `ok`, so a test only
configures the outcomes that matter for the scenario it's verifying.

Integration coverage (using `.build` to wire real collaborators) is reserved
for the controller boundary — one happy-path integration test per sequencer
is usually enough to confirm the wiring is correct.

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

## The three step shapes

```ruby
pipeline(ctx) do |p|
  p.invoke(:find, :user)                # declared dependency (macro or sequencer)
  p.step(:scrub_params)                 # local method `def scrub_params(ctx)`
  p.step(:audit) { |c| AuditLog.append(c[:user]) }   # inline block
end
```

- `p.invoke(:foo, *args, **kwargs)` — a `dependency :foo, …` declared on the
  sequencer (a macro or a nested sequencer). Calls
  `dispatcher.foo.(ctx, *args, **kwargs)`.
- `p.step(:foo)` — a local instance method. Auto-dispatches to
  `self.foo(ctx)`.
- `p.step(:foo) { |ctx| … }` — explicit inline block.

The `pipeline(ctx)` helper (lowercase `p`) is what enables blockless
`p.step(:foo)` auto-dispatch — it builds a Pipeline that knows which
sequencer to dispatch back to. `Pipeline.(ctx)` (capital `P`) is the bare
constructor with no dispatcher and requires every `step` to have a block.
Use `pipeline(ctx)` inside a sequencer; `Pipeline.(ctx)` is mainly useful
for framework tests.

## Built-in macros

Each macro is a dependency declared on a sequencer with `dependency :name, Macros::...`
and wired via `.configure(instance)` in `.build`.

The model macros are designed to work with ActiveRecord models.

### Model::Find

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

### Model::Build

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

The contract macros are designed to work with [Reform](https://github.com/trailblazer/reform) form objects.

### Contract::Build

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

### Contract::Deserialize

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

### Contract::Validate

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

### Contract::Persist

Saves the contract via `contract.save`.

```ruby
p.invoke(:persist)
```

| | |
|---|---|
| **Reads** | `ctx[:contract]` |
| **Writes** | nothing |
| **Fails** | `:persist_failed` when `save` returns false |

### Policy::Check

Builds a policy and calls the named action to authorise the operation.

```ruby
p.invoke(:check_policy, Policies::User, :user, :update)
```

Designed to work with the [hubbado-policy](https://github.com/hubbado/hubbado-policy) gem.
The policy class must respond to `.build(current_user, record)`; the instance must
respond to the action method and return an object with `permitted?`.

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

    p.step(:notify) { |c| UserMailer.updated(c[:user]).deliver_later }
  end
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
update then validates and persists. Extract the shared part as a Present
sequencer and nest it as a dependency:

```ruby
class Seqs::PresentUser
  include Hubbado::Sequence::Sequencer

  configure :present   # so a parent can use `Seqs::PresentUser.configure(instance)`

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

class Seqs::UpdateUser
  include Hubbado::Sequence::Sequencer

  dependency :present,  Seqs::PresentUser
  dependency :validate, Macros::Contract::Validate
  dependency :persist,  Macros::Contract::Persist

  def self.build
    new.tap do |instance|
      Seqs::PresentUser.configure(instance)
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
    run_sequence Seqs::PresentUser, params: params, current_user: current_user do |result|
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
exactly what Present built. The outer trail records `:present` as a single
step; Present's inner steps stay opaque to the parent.

## Result, success, failure

A step is **successful unless it explicitly returns a failed `Result`**. Any
other return value (`nil`, `false`, a model, `Result.ok(...)`) is taken as
success and the pipeline continues with the same `ctx`. Only
`Result.fail(...)` or the `failure(ctx, code: ...)` helper short-circuits.

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
  # implicit ok if we get here
end
```

`failure(ctx, ...)` is a sequencer helper that builds a failed `Result`
with the sequencer's auto-derived i18n scope already applied. It takes the
same error attrs as the underlying error hash (`code:`, `i18n_key:`,
`i18n_args:`, `data:`, `message:`).

## Testing

`described_class.new` returns a sequencer with all dependencies installed as
substitutes. Tests configure the substitutes for the scenario at hand.
`described_class.build` runs the production wiring (the real macros).
Substitutes default to pass-through `Result.ok(ctx)` so a test only
configures the ones whose return matters.

### Substituting macros directly

```ruby
RSpec.describe Seqs::PresentUser do
  it "loads the user, builds the contract, and passes the policy" do
    seq = described_class.new
    user     = User.new(id: 1, email: "old@example.com")
    contract = Contracts::UpdateUser.new(user)
    seq.find.succeed_with(user)
    seq.build_contract.succeed_with(contract)

    result = seq.(Hubbado::Sequence::Ctx.build(
      params:       { id: 1 },
      current_user: User.new
    ))

    expect(result).to be_ok
    expect(seq.find.fetched?(as: :user)).to be true
    expect(seq.build_contract.built?).to be true
    expect(seq.check_policy.checked?).to be true
  end

  it "fails with :not_found when the user doesn't exist" do
    seq = described_class.new
    seq.find.fail_with(code: :not_found)

    result = seq.(Hubbado::Sequence::Ctx.build(
      params:       { id: 999 },
      current_user: User.new
    ))

    expect(result.error[:code]).to eq(:not_found)
    expect(seq.build_contract.built?).to be false
    expect(seq.check_policy.checked?).to be false
  end
end
```

### Substituting a nested sequencer

Every sequencer ships a default `Substitute` module (installed by
`include Hubbado::Sequence::Sequencer`) with `succeed_with(**ctx_writes)` /
`fail_with(**error)` / `called?(**partial_kwargs)`. The parent's tests can
short-circuit a nested sequencer without reaching into its inner pieces:

```ruby
RSpec.describe Seqs::UpdateUser do
  it "updates the user when present succeeds" do
    seq = described_class.new

    user     = User.new(id: 1, email: "old@example.com")
    contract = Contracts::UpdateUser.new(user)
    seq.present.succeed_with(user: user, contract: contract)

    result = seq.(Hubbado::Sequence::Ctx.build(
      params:       { user: { email: "new@example.com" } },
      current_user: User.new
    ))

    expect(result).to be_ok
    expect(seq.present.called?).to be true
    expect(seq.persist.persisted?).to be true
  end

  it "stops when present denies access" do
    seq = described_class.new
    seq.present.fail_with(code: :forbidden)

    result = seq.(Hubbado::Sequence::Ctx.build(
      params:       { user: {} },
      current_user: User.new
    ))

    expect(result.failure?).to be true
    expect(result.error[:code]).to eq(:forbidden)
    expect(seq.validate.validated?).to be false
    expect(seq.persist.persisted?).to be false
  end

  it "stops when present cannot find the record" do
    seq = described_class.new
    seq.present.fail_with(code: :not_found)

    result = seq.(Hubbado::Sequence::Ctx.build(
      params:       { id: 999, user: {} },
      current_user: User.new
    ))

    expect(result.error[:code]).to eq(:not_found)
    expect(seq.validate.validated?).to be false
    expect(seq.persist.persisted?).to be false
  end
end
```

`succeed_with(**ctx_writes)` writes the given keys into `ctx` and returns
`Result.ok(ctx)`, so the outer steps see what the real Present would have
left behind. `fail_with(**error)` returns a failed `Result` with the given
error, short-circuiting the outer pipeline. The Update spec doesn't need
to exercise Find / Build / Policy::Check directly — those live in
PresentUser's spec, where they belong.

## Observability

Every `Result` carries a **trail** — the list of step names that completed
successfully, in order. On failure, the failing step is *not* in the trail;
it's tagged on `error[:step]` instead.

```ruby
result.trail         # => [:find, :build_contract, :check_policy, :validate, :persist]  # success
result.trail         # => [:find, :build_contract]                                       # failed at :check_policy
result.error[:step]  # => :check_policy
```

When invoked via `run_sequence`, the dispatcher logs a single line per
invocation summarising the trail and (on failure) where it stopped:

```
Sequencer Seqs::UpdateUser succeeded: find → build_contract → check_policy → validate → persist
Sequencer Seqs::UpdateUser failed at :check_policy (forbidden): find → build_contract
```

Nested sequencer trails are opaque to the parent: a parent's trail shows
`:present` as a single step, not the sub-steps inside Present.
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

Internal Hubbado gem.
