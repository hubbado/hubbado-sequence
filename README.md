# hubbado-sequence

A small framework for orchestrating units of business behaviour. The eventual
replacement for Trailblazer operations at Hubbado, designed to coexist with
them during migration.

A sequencer takes input, runs a sequence of steps, and returns a `Result`
indicating success or failure plus the working context that was built up
during execution.

The full design rationale lives in [`docs/design.md`](docs/design.md). This
README is a quick tour.

## Quick start

```ruby
class Seqs::UpdateUser
  include Hubbado::Sequence

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

## Nested sequencers (Present + Update)

The "find the record, build the contract, check the policy" shape is shared
between an edit form and an update action — both need exactly that, and the
update then validates and persists. Extract the shared part as a Present
sequencer and nest it as a dependency:

```ruby
class Seqs::PresentUser
  include Hubbado::Sequence

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
  include Hubbado::Sequence

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
`include Hubbado::Sequence`) with `succeed_with(**ctx_writes)` /
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
