require_relative "../../../test_init"

context "Hubbado" do
  context "Sequencer (module)" do
    context "when included in a class" do
      sequencer_class = Class.new do
        include Hubbado::Sequence::Sequencer

        def self.name
          "Seqs::ExampleSeq"
        end

        def self.build
          new
        end

        def sequence(ctx)
          ctx[:value] = ctx[:value] * 2
          Hubbado::Sequence::Result.success(ctx)
        end
      end

      context "class-level .call shorthand" do
        test "builds a Ctx from kwargs and delegates to instance call" do
          result = sequencer_class.(value: 21)

          assert result.success?
          assert result.ctx[:value] == 42
        end

        test "passes through an existing Ctx without rebuilding" do
          ctx = Hubbado::Sequence::Ctx.build(value: 5)
          result = sequencer_class.(ctx)

          assert result.success?
          assert result.ctx.equal?(ctx)
          assert ctx[:value] == 10
        end
      end

      context "instance call" do
        reads_missing_class = Class.new do
          include Hubbado::Sequence::Sequencer

          def self.name
            "Seqs::ReadsMissingKey"
          end

          def sequence(ctx)
            pipeline(ctx) do |p|
              p.step(:read_missing)
            end
          end

          def read_missing(ctx)
            ctx[:missing]
          end
        end

        branches_in_block_class = Class.new do
          include Hubbado::Sequence::Sequencer

          def self.name
            "Seqs::BranchesInBlock"
          end

          def sequence(ctx)
            pipeline(ctx) do |p|
              p.step(:write_flag)
              p.step(:follow_flag) if ctx[:flag]
            end
          end

          def write_flag(ctx)
            ctx[:flag] = true
          end

          def follow_flag(ctx)
            ctx[:followed] = true
          end
        end

        test "keyword arguments run on a strict Ctx" do
          assert_raises KeyError do
            reads_missing_class.new.(params: {})
          end
        end

        test "a plain Hash runs on a strict Ctx" do
          assert_raises KeyError do
            reads_missing_class.new.({ params: {} })
          end
        end

        test "the pipeline block sees a step's write" do
          result = branches_in_block_class.new.(params: {})

          assert result.ctx[:followed] == true
        end

        test "an existing Ctx passes through as the same object" do
          ctx = Hubbado::Sequence::Ctx.build(flag: false)
          result = branches_in_block_class.new.(ctx)

          assert result.ctx.equal?(ctx)
        end

        test "a Ctx and keyword arguments together are rejected" do
          assert_raises ArgumentError do
            branches_in_block_class.new.(Hubbado::Sequence::Ctx.new, params: {})
          end
        end
      end

      context "pipeline given a plain Hash" do
        defines_call_class = Class.new do
          include Hubbado::Sequence::Sequencer

          def self.name
            "Seqs::DefinesCall"
          end

          def call(ctx)
            pipeline(ctx) do |p|
              p.step(:noop)
            end
          end

          def noop(ctx); end
        end

        test "is rejected with a pointer to sequence(ctx)" do
          assert_raises(
            ArgumentError,
            "Seqs::DefinesCall#pipeline expects a Hubbado::Sequence::Ctx; " \
            "define the steps in sequence(ctx), not call(ctx)"
          ) do
            defines_call_class.new.(params: {})
          end
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
          assert result.code == :something_went_wrong
          assert result.i18n_scope == "seqs.example_seq"
        end

        test "passes through extra failure attributes" do
          instance = sequencer_class.new
          result = instance.failure(
            Hubbado::Sequence::Ctx.new,
            code: :not_shippable,
            i18n_args: { id: 1 },
            data: { reason: "shipped" }
          )

          assert result.code == :not_shippable
          assert result.i18n_args == { id: 1 }
          assert result.data == { reason: "shipped" }
        end

        test "caller-supplied i18n_scope wins over the sequencer's auto-derived scope" do
          instance = sequencer_class.new
          result = instance.failure(
            Hubbado::Sequence::Ctx.new,
            code: :not_shippable,
            i18n_scope: "seqs.alternative"
          )

          assert result.i18n_scope == "seqs.alternative"
        end
      end

      context "i18n_scope auto-applied to returned Result" do
        context "pipeline block form" do
          test "applies the sequencer's scope to a failure with no scope" do
            seq = Class.new do
              include Hubbado::Sequence::Sequencer

              def self.name; "Seqs::PipelineFails"; end
              def self.build; new; end

              def sequence(ctx)
                pipeline(ctx) do |p|
                  p.step(:fail_step)
                end
              end

              def fail_step(ctx)
                Hubbado::Sequence::Result.failure(ctx, code: :something)
              end
            end

            result = seq.(Hubbado::Sequence::Ctx.new)

            assert result.failure?
            assert result.i18n_scope == "seqs.pipeline_fails"
          end

          test "does not override an i18n_scope already set on the inner result" do
            seq = Class.new do
              include Hubbado::Sequence::Sequencer

              def self.name; "Seqs::PipelineFailsWithScope"; end
              def self.build; new; end

              def sequence(ctx)
                pipeline(ctx) do |p|
                  p.step(:fail_step)
                end
              end

              def fail_step(ctx)
                Hubbado::Sequence::Result.failure(
                  ctx, code: :something, i18n_scope: "inner.scope"
                )
              end
            end

            result = seq.(Hubbado::Sequence::Ctx.new)

            assert result.i18n_scope == "inner.scope"
          end

          test "applies the sequencer's scope to a successful pipeline result" do
            seq = Class.new do
              include Hubbado::Sequence::Sequencer

              def self.name; "Seqs::PipelineSucceeds"; end
              def self.build; new; end

              def sequence(ctx)
                pipeline(ctx) do |p|
                  p.step(:noop)
                end
              end

              def noop(ctx)
                Hubbado::Sequence::Result.success(ctx)
              end
            end

            result = seq.(Hubbado::Sequence::Ctx.new)

            assert result.success?
            assert result.i18n_scope == "seqs.pipeline_succeeds"
          end
        end

        context "class-level .()" do
          test "applies the sequencer's scope to a hand-built failure with no scope" do
            seq = Class.new do
              include Hubbado::Sequence::Sequencer

              def self.name; "Seqs::HandBuiltFails"; end
              def self.build; new; end

              def sequence(ctx)
                Hubbado::Sequence::Result.failure(ctx, code: :something)
              end
            end

            result = seq.(Hubbado::Sequence::Ctx.new)

            assert result.failure?
            assert result.i18n_scope == "seqs.hand_built_fails"
          end

          test "applies the sequencer's scope to a hand-built success" do
            seq = Class.new do
              include Hubbado::Sequence::Sequencer

              def self.name; "Seqs::HandBuiltSucceeds"; end
              def self.build; new; end

              def sequence(ctx)
                Hubbado::Sequence::Result.success(ctx)
              end
            end

            result = seq.(Hubbado::Sequence::Ctx.new)

            assert result.success?
            assert result.i18n_scope == "seqs.hand_built_succeeds"
          end

          test "does not override an i18n_scope already set by the sequencer" do
            seq = Class.new do
              include Hubbado::Sequence::Sequencer

              def self.name; "Seqs::HandBuiltWithScope"; end
              def self.build; new; end

              def sequence(ctx)
                Hubbado::Sequence::Result.failure(
                  ctx, code: :something, i18n_scope: "inner.scope"
                )
              end
            end

            result = seq.(Hubbado::Sequence::Ctx.new)

            assert result.i18n_scope == "inner.scope"
          end
        end
      end

      context "dependency macro" do
        macro_class = Class.new do
          def self.name; "ExampleMacro"; end

          def call(ctx)
            Hubbado::Sequence::Result.success(ctx)
          end
        end

        seq_with_dep = Class.new do
          include Hubbado::Sequence::Sequencer

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
            include Hubbado::Sequence::Sequencer

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
