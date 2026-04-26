require_relative "../../../test_init"

context "Hubbado" do
  context "Sequencer (module)" do
    context "when included in a class" do
      sequencer_class = Class.new do
        include Hubbado::Sequence

        def self.name
          "Seqs::ExampleSeq"
        end

        def self.build
          new
        end

        def call(ctx)
          ctx[:value] = ctx[:value] * 2
          Hubbado::Sequence::Result.ok(ctx)
        end
      end

      context "class-level .call shorthand" do
        test "builds a Ctx from kwargs and delegates to instance call" do
          result = sequencer_class.(value: 21)

          assert result.ok?
          assert result.ctx[:value] == 42
        end

        test "passes through an existing Ctx without rebuilding" do
          ctx = Hubbado::Sequence::Ctx.build(value: 5)
          result = sequencer_class.(ctx)

          assert result.ok?
          assert result.ctx.equal?(ctx)
          assert ctx[:value] == 10
        end
      end

      context "i18n scope auto-derivation" do
        test "derives the scope from the class name" do
          assert sequencer_class.i18n_scope == "seqs.example_seq"
        end

        test "the instance returns the same scope" do
          assert sequencer_class.new.i18n_scope == "seqs.example_seq"
        end
      end

      context "#failure helper" do
        test "builds a failed result with the sequencer's i18n scope auto-applied" do
          instance = sequencer_class.new
          ctx = Hubbado::Sequence::Ctx.new
          result = instance.failure(ctx, code: :something_went_wrong)

          assert result.failure?
          assert result.error[:code] == :something_went_wrong
          assert result.i18n_scope == "seqs.example_seq"
        end

        test "passes through extra error attributes" do
          instance = sequencer_class.new
          result = instance.failure(
            Hubbado::Sequence::Ctx.new,
            code: :not_shippable,
            i18n_args: { id: 1 },
            data: { reason: "shipped" }
          )

          assert result.error[:code] == :not_shippable
          assert result.error[:i18n_args] == { id: 1 }
          assert result.error[:data] == { reason: "shipped" }
        end
      end

      context "dependency macro" do
        macro_class = Class.new do
          def self.name; "ExampleMacro"; end

          def call(ctx)
            Hubbado::Sequence::Result.ok(ctx)
          end
        end

        seq_with_dep = Class.new do
          include Hubbado::Sequence

          def self.name; "Seqs::WithDep"; end
        end
        seq_with_dep.dependency :example, macro_class

        test "exposes a substitute reader by default" do
          instance = seq_with_dep.new
          refute instance.example.nil?
        end

        test "the substitute responds to the interface methods" do
          instance = seq_with_dep.new
          # Static mimic: should respond to call but not to undefined methods
          assert instance.example.respond_to?(:call)
        end
      end

      context "configure macro" do
        test "is available on the including class" do
          klass = Class.new do
            include Hubbado::Sequence

            def self.name; "Seqs::Configurable"; end

            configure :configurable

            def self.build
              new
            end
          end

          receiver = Object.new
          receiver.singleton_class.attr_accessor :configurable

          klass.configure(receiver)

          assert receiver.configurable.is_a?(klass)
        end
      end
    end
  end
end
