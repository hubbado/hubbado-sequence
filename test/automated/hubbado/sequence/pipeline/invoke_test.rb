require_relative "../../../../test_init"

# `p.invoke(:name, *args, **kwargs)` is shorthand for
# `p.step(:name) { |c| dispatcher.send(:name).(c, *args, **kwargs) }`.
# Use it when the step is invoking a declared dependency — a macro
# (`Macros::Model::Find`) or a nested sequencer — rather than a local
# instance method.

context "Hubbado" do
  context "Sequencer" do
    context "Pipeline#invoke" do
      model = Hubbado::Sequence::Controls::Model.example
      contract_class = Hubbado::Sequence::Controls::Contract.klass(valid: true)

      seq_class = Class.new do
        include Hubbado::Sequence::Sequencer

        define_singleton_method(:name) { "Seqs::WithInvokeSteps" }

        dependency :find,           Hubbado::Sequence::Macros::Model::Find
        dependency :build_contract, Hubbado::Sequence::Macros::Contract::Build

        define_singleton_method(:build) do
          new.tap do |instance|
            Hubbado::Sequence::Macros::Model::Find.configure(instance)
            Hubbado::Sequence::Macros::Contract::Build.configure(instance)
          end
        end

        define_method(:call) do |ctx|
          pipeline(ctx) do |p|
            p.invoke(:find, model, as: :user)
            p.invoke(:build_contract, contract_class, :user)
          end
        end
      end

      context "happy path" do
        model.reset
        model.put(1, model.new(name: "Alice"))

        result = seq_class.(params: { id: 1 })

        test "succeeds" do
          assert result.ok?
        end

        test "forwards positional args to the dependency call" do
          # Find with attr_name = :user wrote ctx[:user]
          assert result.ctx[:user].is_a?(model)
        end

        test "forwards keyword args to the dependency call" do
          # Contract::Build was given contract_class: contract_class
          assert result.ctx[:contract].is_a?(contract_class)
        end

        test "records the dependency names in the trail" do
          assert result.trail == %i[find build_contract]
        end
      end

      context "failure short-circuits the pipeline" do
        model.reset

        result = seq_class.(params: { id: 999 })

        test "returns a failed Result with the dependency's failure code" do
          assert result.failure?
          assert result.error[:code] == :not_found
        end

        test "tags the failed step with the dependency name" do
          assert result.error[:step] == :find
        end

        test "trail reflects what completed before the failure" do
          assert result.trail == []
        end

        test "subsequent invocations are not run" do
          seq = seq_class.new
          seq.find.fail_with(code: :not_found)

          ctx = Hubbado::Sequence::Ctx.build(params: { id: 1 })
          seq.(ctx)

          refute seq.build_contract.built?
        end
      end

      context "lenient return convention" do
        # A dependency whose call returns nil. The pipeline should treat that
        # as success per the lenient convention.
        nil_returning_dep = Class.new do
          def call(_ctx)
            nil
          end
        end

        seq = Class.new do
          include Hubbado::Sequence::Sequencer
          define_singleton_method(:name) { "Seqs::LenientInvoke" }

          dependency :returns_nil, nil_returning_dep

          define_singleton_method(:build) do
            new.tap { |instance| instance.returns_nil = nil_returning_dep.new }
          end

          define_method(:call) do |ctx|
            pipeline(ctx) do |p|
              p.invoke(:returns_nil)
            end
          end
        end

        test "non-Result returns from an invoked dependency are treated as success" do
          result = seq.()
          assert result.ok?
          assert result.trail == [:returns_nil]
        end
      end

      context "without a dispatcher" do
        test "raises a clear error explaining invoke needs a sequencer" do
          captured = nil
          begin
            Hubbado::Sequence::Pipeline.() do |p|
              p.invoke(:find, model, as: :user)
            end
          rescue ArgumentError => e
            captured = e
          end

          refute captured.nil?
          assert captured.message.include?("dispatcher")
        end
      end

      context "missing dependency" do
        test "raises NoMethodError naming the sequencer and dependency" do
          empty_seq = Class.new do
            include Hubbado::Sequence::Sequencer
            define_singleton_method(:name) { "Seqs::Empty" }

            define_method(:call) do |ctx|
              pipeline(ctx) do |p|
                p.invoke(:nonexistent, :arg)
              end
            end
          end

          captured = nil
          begin
            empty_seq.()
          rescue NoMethodError => e
            captured = e
          end

          refute captured.nil?
          assert captured.message.include?("nonexistent")
          assert captured.message.include?("Seqs::Empty")
        end
      end
    end
  end
end
