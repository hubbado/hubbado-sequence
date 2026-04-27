require_relative "../../../test_init"

# End-to-end: a sequencer that wires together Find, Contract::Build,
# Policy::Check, Contract::Validate, and Contract::Persist, exercised via
# Pipeline. This proves the parts compose; per-piece behaviour is covered in
# the dedicated tests.

context "Hubbado" do
  context "Sequencer" do
    context "End-to-end: Seqs::UpdateUser-style sequencer" do
      model_class    = Hubbado::Sequence::Controls::Model.example
      contract_class = Hubbado::Sequence::Controls::Contract.klass(valid: true, save_result: true)
      policy_class   = Hubbado::Sequence::Controls::Policy.example(decision: :permit, action: :update)

      seq_class = Class.new do
        include Hubbado::Sequence::Sequencer

        define_singleton_method(:name) { "Seqs::UpdateUser" }

        dependency :find,           Hubbado::Sequence::Macros::Model::Find
        dependency :build_contract, Hubbado::Sequence::Macros::Contract::Build
        dependency :check_policy,   Hubbado::Sequence::Macros::Policy::Check
        dependency :validate,       Hubbado::Sequence::Macros::Contract::Validate
        dependency :persist,        Hubbado::Sequence::Macros::Contract::Persist

        define_singleton_method(:build) do
          new.tap do |instance|
            Hubbado::Sequence::Macros::Model::Find.configure(instance)
            Hubbado::Sequence::Macros::Contract::Build.configure(instance)
            Hubbado::Sequence::Macros::Policy::Check.configure(instance)
            Hubbado::Sequence::Macros::Contract::Validate.configure(instance)
            Hubbado::Sequence::Macros::Contract::Persist.configure(instance)
          end
        end

        define_method(:call) do |ctx|
          pipeline(ctx) do |p|
            p.invoke(:find,           model_class,    as: :user)
            p.invoke(:build_contract, contract_class, :user)
            p.invoke(:check_policy,   policy_class,   :user, :update)
            p.invoke(:validate,       from: %i[params user])
            p.invoke(:persist)
          end
        end
      end

      context "happy path with .build (production wiring)" do
        model_class.reset
        model_class.put(1, model_class.new(name: "Old"))

        result = seq_class.(
          params: { id: 1, user: { name: "New" } },
          current_user: :alice
        )

        test "succeeds" do
          assert result.ok?
        end

        test "records the trail" do
          assert result.trail == %i[find build_contract check_policy validate persist]
        end

        test "exposes the contract on ctx" do
          assert result.ctx[:contract].is_a?(contract_class)
        end
      end

      context "with .new (substitutes installed)" do
        test "passes through with no configuration when nothing matters" do
          seq = seq_class.new
          # Substitutes default to pass-through; no setup needed except classes
          # the substitute validates against (model, policy).
          ctx = Hubbado::Sequence::Ctx.build(params: { id: 1 }, current_user: :alice)
          result = seq.(ctx)

          assert result.ok?
        end

        test "uses substitutes to control specific outcomes" do
          seq = seq_class.new
          fake_user = model_class.new(name: "Substituted")
          seq.find.succeed_with(fake_user)

          ctx = Hubbado::Sequence::Ctx.build(params: { id: 99 }, current_user: :alice)
          result = seq.(ctx)

          assert result.ok?
          assert result.ctx[:user].equal?(fake_user)
          assert seq.find.fetched?
        end

        test "stops at the failing substitute and tags the step" do
          seq = seq_class.new
          seq.check_policy.fail_with(code: :forbidden, reason: :not_owner)

          ctx = Hubbado::Sequence::Ctx.build(params: { id: 1 }, current_user: :alice)
          result = seq.(ctx)

          assert result.failure?
          assert result.error[:code] == :forbidden
          assert result.error[:step] == :check_policy
          assert result.trail == %i[find build_contract]
          refute seq.validate.validated?
          refute seq.persist.persisted?
        end
      end

      context "via RunSequence" do
        controller = Class.new do
          include Hubbado::Sequence::RunSequence
        end

        test "fires the success block on the happy path" do
          model_class.reset
          model_class.put(2, model_class.new(name: "Existing"))

          ran = nil
          controller.new.run_sequence(seq_class, params: { id: 2, user: { name: "Updated" } }, current_user: :alice) do |r|
            r.success           { |_| ran = :success }
            r.policy_failed     { |_| ran = :policy_failed }
            r.validation_failed { |_| ran = :validation_failed }
          end

          assert ran == :success
        end
      end
    end
  end
end
