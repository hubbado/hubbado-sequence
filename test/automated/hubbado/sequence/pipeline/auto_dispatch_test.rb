require_relative "../../../../test_init"

# Auto-dispatch: when a Pipeline is built via the sequencer's `pipeline(ctx)`
# helper, `step(:foo)` with no block dispatches to `self.foo(ctx)` on the
# sequencer. This collapses the boilerplate of step blocks that just delegate
# to a same-named method.

context "Hubbado" do
  context "Sequencer" do
    context "Pipeline auto-dispatch" do
      context "via a sequencer's #pipeline helper" do
        seq_class = Class.new do
          include Hubbado::Sequence::Sequencer

          define_singleton_method(:name) { "Seqs::AutoDispatch" }

          define_method(:call) do |ctx|
            pipeline(ctx)
              .step(:double_value)
              .step(:add_one)
              .result
          end

          define_method(:double_value) do |ctx|
            ctx[:value] = ctx[:value] * 2
            Hubbado::Sequence::Result.ok(ctx)
          end

          define_method(:add_one) do |ctx|
            ctx[:value] = ctx[:value] + 1
            Hubbado::Sequence::Result.ok(ctx)
          end
        end

        test "step(:foo) with no block calls self.foo(ctx)" do
          result = seq_class.(value: 10)

          assert result.ok?
          assert result.ctx[:value] == 21
        end

        test "records each dispatched step in the trail" do
          result = seq_class.(value: 10)

          assert result.trail == %i[double_value add_one]
        end

        test "a returning failure short-circuits the pipeline" do
          failing = Class.new do
            include Hubbado::Sequence::Sequencer
            define_singleton_method(:name) { "Seqs::Failing" }

            define_method(:call) do |ctx|
              pipeline(ctx)
                .step(:fine)
                .step(:bad)
                .step(:never_runs)
                .result
            end

            define_method(:fine)       { |ctx| Hubbado::Sequence::Result.ok(ctx) }
            define_method(:bad)        { |ctx| Hubbado::Sequence::Result.fail(ctx, error: { code: :bad }) }
            define_method(:never_runs) { |ctx| raise "should not run" }
          end

          result = failing.()

          assert result.failure?
          assert result.error[:code] == :bad
          assert result.error[:step] == :bad
          assert result.trail == %i[fine]
        end
      end

      context "block overrides auto-dispatch" do
        seq_class = Class.new do
          include Hubbado::Sequence::Sequencer
          define_singleton_method(:name) { "Seqs::Override" }

          define_method(:call) do |ctx|
            pipeline(ctx)
              .step(:present) { |c| run_present(c) }   # block wins over dispatch
              .step(:finish)                            # → self.finish(ctx)
              .result
          end

          define_method(:run_present) { |ctx| ctx[:presented] = true; Hubbado::Sequence::Result.ok(ctx) }
          define_method(:finish)      { |ctx| ctx[:finished]  = true; Hubbado::Sequence::Result.ok(ctx) }
        end

        test "uses the block when one is given" do
          result = seq_class.()

          assert result.ctx[:presented]
          assert result.ctx[:finished]
        end

        test "the step name in the trail is unchanged" do
          result = seq_class.()

          assert result.trail == %i[present finish]
        end
      end

      context "auto-dispatch carries through transaction" do
        seq_class = Class.new do
          include Hubbado::Sequence::Sequencer
          define_singleton_method(:name) { "Seqs::WithTransaction" }

          define_method(:call) do |ctx|
            pipeline(ctx)
              .step(:before_tx)
              .transaction do |t|
                t.step(:inside_tx)
              end
              .step(:after_tx)
              .result
          end

          define_method(:before_tx) { |ctx| ctx[:before] = true; Hubbado::Sequence::Result.ok(ctx) }
          define_method(:inside_tx) { |ctx| ctx[:inside] = true; Hubbado::Sequence::Result.ok(ctx) }
          define_method(:after_tx)  { |ctx| ctx[:after]  = true; Hubbado::Sequence::Result.ok(ctx) }
        end

        test "inner step dispatches to the same sequencer instance" do
          result = seq_class.()

          assert result.ctx[:before]
          assert result.ctx[:inside]
          assert result.ctx[:after]
          assert result.trail == %i[before_tx inside_tx after_tx]
        end
      end

      context "missing method" do
        seq_class = Class.new do
          include Hubbado::Sequence::Sequencer
          define_singleton_method(:name) { "Seqs::Missing" }

          define_method(:call) do |ctx|
            pipeline(ctx).step(:nope).result
          end
        end

        test "raises NoMethodError naming the step and the sequencer" do
          captured = nil
          begin
            seq_class.()
          rescue NoMethodError => e
            captured = e
          end

          refute captured.nil?
          assert captured.message.include?("nope")
          assert captured.message.include?("Seqs::Missing")
        end
      end

      context "Pipeline.() (no helper) with no block still raises" do
        # Pipeline.() doesn't carry a dispatcher, so step(:foo) with no block
        # has nowhere to go — preserve the strict-by-default behaviour.
        test "step without a block raises when no dispatcher is set" do
          pipe = Hubbado::Sequence::Pipeline.(value: 1)

          assert_raises ArgumentError do
            pipe.step(:nothing)
          end
        end
      end
    end
  end
end
