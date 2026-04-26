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

```ruby
it "updates the user" do
  seq = described_class.new
  user     = User.new(id: 1, email: "old@example.com")
  contract = Contracts::UpdateUser.new(user)
  seq.find.succeed_with(user)
  seq.build_contract.succeed_with(contract)

  result = seq.(Hubbado::Sequence::Ctx.build(
    params:       { user: { email: "new@example.com" } },
    current_user: User.new
  ))

  expect(result).to be_ok
  expect(seq.find.fetched?(as: :user)).to be true
  expect(seq.persist.persisted?).to be true
end
```

Substitutes default to pass-through `Result.ok(ctx)` so a test only
configures the ones whose return matters. Each sequencer also gets a default
`Substitute` module via `include Hubbado::Sequence`, so a parent can
substitute a nested sequencer with `seq.present.fail_with(code: :forbidden)`
without reaching into its inner pieces.

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
