require_relative "../../../../test_init"

# Auto-dispatch: when a Pipeline is built via the sequencer's `pipeline(ctx)`
# helper, `step(:foo)` dispatches to `self.foo(ctx)` on the sequencer. This
# is the only step form — every step name must resolve to a method of the
# same name on the dispatcher.

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
            Hubbado::Sequence::Result.success(ctx)
          end

          define_method(:add_one) do |ctx|
            ctx[:value] = ctx[:value] + 1
            Hubbado::Sequence::Result.success(ctx)
          end
        end

        test "step(:foo) calls self.foo(ctx)" do
          result = seq_class.(value: 10)

          assert result.success?
          assert result.ctx[:value] == 21
        end

        test "records each dispatched step in successful_steps" do
          result = seq_class.(value: 10)

          assert result.successful_steps == %i[double_value add_one]
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

            define_method(:fine)       { |ctx| Hubbado::Sequence::Result.success(ctx) }
            define_method(:bad)        { |ctx| Hubbado::Sequence::Result.failure(ctx, code: :bad) }
            define_method(:never_runs) { |ctx| raise "should not run" }
          end

          result = failing.()

          assert result.failure?
          assert result.code == :bad
          assert result.step == :bad
          assert result.successful_steps == %i[fine]
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

          define_method(:before_tx) { |ctx| ctx[:before] = true; Hubbado::Sequence::Result.success(ctx) }
          define_method(:inside_tx) { |ctx| ctx[:inside] = true; Hubbado::Sequence::Result.success(ctx) }
          define_method(:after_tx)  { |ctx| ctx[:after]  = true; Hubbado::Sequence::Result.success(ctx) }
        end

        test "inner step dispatches to the same sequencer instance" do
          result = seq_class.()

          assert result.ctx[:before]
          assert result.ctx[:inside]
          assert result.ctx[:after]
          assert result.successful_steps == %i[before_tx inside_tx after_tx]
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
    end
  end
end
