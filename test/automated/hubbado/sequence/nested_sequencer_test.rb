require_relative "../../../test_init"

# Verifies the design's "shares ctx happily" property for nested sequencers:
# the inner sequencer mutates the same Ctx the outer sequencer holds, so
# subsequent outer steps can read what the inner step wrote.

context "Hubbado" do
  context "Sequencer" do
    context "Nested sequencer" do
      model_class    = Hubbado::Sequence::Controls::Model.example
      contract_class = Hubbado::Sequence::Controls::Contract.klass(valid: true, save_result: true)
      policy_class   = Hubbado::Sequence::Controls::Policy.example(decision: :permit, action: :update)

      # Inner: loads the model, builds the contract, checks the policy.
      present_class = Class.new do
        include Hubbado::Sequence::Sequencer

        define_singleton_method(:name) { "Seqs::Present" }

        configure :present

        dependency :find,           Hubbado::Sequence::Macros::Model::Find
        dependency :build_contract, Hubbado::Sequence::Macros::Contract::Build
        dependency :check_policy,   Hubbado::Sequence::Macros::Policy::Check

        define_singleton_method(:build) do
          new.tap do |instance|
            Hubbado::Sequence::Macros::Model::Find.configure(instance)
            Hubbado::Sequence::Macros::Contract::Build.configure(instance)
            Hubbado::Sequence::Macros::Policy::Check.configure(instance)
          end
        end

        define_method(:call) do |ctx|
          Hubbado::Sequence::Pipeline.(ctx)
            .step(:find_user)      { |c| find.(c, model_class, as: :user) }
            .step(:build_contract) { |c| build_contract.(c, contract_class, :user) }
            .step(:check_policy)   { |c| check_policy.(c, policy_class, :user, :update) }
            .result
        end
      end

      # Outer: nests Present, then validates and persists.
      update_class = Class.new do
        include Hubbado::Sequence::Sequencer

        define_singleton_method(:name) { "Seqs::UpdateUser" }

        dependency :present,  present_class
        dependency :validate, Hubbado::Sequence::Macros::Contract::Validate
        dependency :persist,  Hubbado::Sequence::Macros::Contract::Persist

        define_singleton_method(:build) do
          new.tap do |instance|
            present_class.configure(instance)
            Hubbado::Sequence::Macros::Contract::Validate.configure(instance)
            Hubbado::Sequence::Macros::Contract::Persist.configure(instance)
          end
        end

        define_method(:call) do |ctx|
          Hubbado::Sequence::Pipeline.(ctx)
            .step(:present)  { |c| present.(c) }
            .step(:validate) { |c| validate.(c, from: %i[params user]) }
            .step(:persist)  { |c| persist.(c) }
            .result
        end
      end

      context "happy path" do
        model_class.reset
        model_class.put(1, model_class.new(name: "Existing"))

        result = update_class.(
          params: { id: 1, user: { name: "Updated" } },
          current_user: :alice
        )

        test "the outer pipeline succeeds" do
          assert result.ok?
        end

        test "the inner sequencer's writes are visible to outer steps" do
          # If ctx weren't shared, ctx[:contract] (set inside Present) would be
          # missing when the outer :validate step runs, raising KeyError.
          assert result.ctx[:contract].is_a?(contract_class)
          assert result.ctx[:user].is_a?(model_class)
        end

        test "the validate step ran, proving it saw the inner-built contract" do
          # The contract control records what was passed to validate(...)
          assert result.ctx[:contract].validated_with == { name: "Updated" }
        end

        test "outer trail is opaque to the inner sequencer's steps" do
          assert result.trail == %i[present validate persist]
        end
      end

      context "inner failure short-circuits the outer pipeline" do
        denying_policy   = Hubbado::Sequence::Controls::Policy.example(decision: :deny, action: :update)
        denying_present  = Class.new do
          include Hubbado::Sequence::Sequencer
          define_singleton_method(:name) { "Seqs::PresentDenying" }
          configure :present
          dependency :find,           Hubbado::Sequence::Macros::Model::Find
          dependency :build_contract, Hubbado::Sequence::Macros::Contract::Build
          dependency :check_policy,   Hubbado::Sequence::Macros::Policy::Check
          define_singleton_method(:build) do
            new.tap do |instance|
              Hubbado::Sequence::Macros::Model::Find.configure(instance)
              Hubbado::Sequence::Macros::Contract::Build.configure(instance)
              Hubbado::Sequence::Macros::Policy::Check.configure(instance)
            end
          end
          define_method(:call) do |ctx|
            Hubbado::Sequence::Pipeline.(ctx)
              .step(:find_user)      { |c| find.(c, model_class, as: :user) }
              .step(:build_contract) { |c| build_contract.(c, contract_class, :user) }
              .step(:check_policy)   { |c| check_policy.(c, denying_policy, :user, :update) }
              .result
          end
        end

        denying_update = Class.new do
          include Hubbado::Sequence::Sequencer
          define_singleton_method(:name) { "Seqs::UpdateDenying" }
          dependency :present,  denying_present
          dependency :validate, Hubbado::Sequence::Macros::Contract::Validate
          dependency :persist,  Hubbado::Sequence::Macros::Contract::Persist
          define_singleton_method(:build) do
            new.tap do |instance|
              denying_present.configure(instance)
              Hubbado::Sequence::Macros::Contract::Validate.configure(instance)
              Hubbado::Sequence::Macros::Contract::Persist.configure(instance)
            end
          end
          define_method(:call) do |ctx|
            Hubbado::Sequence::Pipeline.(ctx)
              .step(:present)  { |c| present.(c) }
              .step(:validate) { |c| validate.(c, from: %i[params user]) }
              .step(:persist)  { |c| persist.(c) }
              .result
          end
        end

        model_class.reset
        model_class.put(1, model_class.new(name: "Existing"))

        result = denying_update.(
          params: { id: 1, user: { name: "Updated" } },
          current_user: :alice
        )

        test "the outer result is a failure" do
          assert result.failure?
        end

        test "the inner step's failure code propagates outward" do
          assert result.error[:code] == :forbidden
        end

        test "outer trail stops at the nested step name (opaque)" do
          assert result.trail == []
        end

        test "error[:step] reflects the outer step that ran the nested sequencer" do
          # Pipeline tags the failure with the OUTER step name (:present),
          # because that's the step that returned the failed Result.
          assert result.error[:step] == :present
        end
      end

      context "via .new (substitutes installed) the nested seq is also substituted" do
        test "the parent's substitute short-circuits the entire nested sequencer with fail_with" do
          seq = update_class.new
          seq.present.fail_with(code: :forbidden)

          ctx = Hubbado::Sequence::Ctx.build(params: { id: 1 }, current_user: :alice)
          result = seq.(ctx)

          assert result.failure?
          assert result.error[:code] == :forbidden
          refute seq.validate.validated?
          refute seq.persist.persisted?
        end

        test "the parent's substitute can write ctx values via succeed_with" do
          seq = update_class.new
          fake_user     = model_class.new(name: "Subbed")
          fake_contract = contract_class.new(fake_user)
          seq.present.succeed_with(user: fake_user, contract: fake_contract)

          ctx = Hubbado::Sequence::Ctx.build(params: { id: 1, user: { name: "x" } }, current_user: :alice)
          result = seq.(ctx)

          assert result.ok?
          assert result.ctx[:user].equal?(fake_user)
          assert result.ctx[:contract].equal?(fake_contract)
          assert seq.present.called?
        end
      end
    end
  end
end
