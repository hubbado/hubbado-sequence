require_relative "../../../../test_init"

# Block form: `pipeline(ctx) { |p| ... }` yields the pipeline, runs the
# block, and returns the final Result. Removes the `p.result` boilerplate
# at the end of every sequencer's call body.

context "Hubbado" do
  context "Sequencer" do
    context "Pipeline block form" do
      context "pipeline(ctx) { |p| ... } from a sequencer" do
        seq_class = Class.new do
          include Hubbado::Sequence::Sequencer
          define_singleton_method(:name) { "Seqs::BlockForm" }

          define_method(:call) do |ctx|
            pipeline(ctx) do |p|
              p.step(:double_value)
              p.step(:add_one)
              p.step(:tag)
            end
          end

          define_method(:double_value) { |ctx| ctx[:value] = ctx[:value] * 2; Hubbado::Sequence::Result.success(ctx) }
          define_method(:add_one)      { |ctx| ctx[:value] = ctx[:value] + 1; Hubbado::Sequence::Result.success(ctx) }
          define_method(:tag)          { |ctx| ctx[:tagged] = true; Hubbado::Sequence::Result.success(ctx) }
        end

        test "returns the Result automatically" do
          result = seq_class.(value: 5)

          assert result.is_a?(Hubbado::Sequence::Result)
          assert result.success?
          assert result.ctx[:value] == 11
          assert result.ctx[:tagged]
        end

        test "yields the pipeline so statement form works inside the block" do
          result = seq_class.(value: 5)

          assert result.successful_steps == %i[double_value add_one tag]
        end

        test "supports conditionals naturally inside the block" do
          conditional_seq = Class.new do
            include Hubbado::Sequence::Sequencer
            define_singleton_method(:name) { "Seqs::Conditional" }

            define_method(:call) do |ctx|
              pipeline(ctx) do |p|
                p.step(:always)
                p.step(:extra) if ctx[:run_extra]
                p.step(:always_again)
              end
            end

            define_method(:always)        { |ctx| Hubbado::Sequence::Result.success(ctx) }
            define_method(:extra)         { |ctx| Hubbado::Sequence::Result.success(ctx) }
            define_method(:always_again)  { |ctx| Hubbado::Sequence::Result.success(ctx) }
          end

          result = conditional_seq.(run_extra: true)

          assert result.successful_steps == %i[always extra always_again]
        end

        test "propagates failure as the returned Result" do
          failing_seq = Class.new do
            include Hubbado::Sequence::Sequencer
            define_singleton_method(:name) { "Seqs::BlockFormFailing" }

            define_method(:call) do |ctx|
              pipeline(ctx) do |p|
                p.step(:fine)
                p.step(:bad)
              end
            end

            define_method(:fine) { |ctx| Hubbado::Sequence::Result.success(ctx) }
            define_method(:bad)  { |ctx| Hubbado::Sequence::Result.failure(ctx, error: { code: :nope }) }
          end

          result = failing_seq.()

          assert result.failure?
          assert result.error[:code] == :nope
          assert result.error[:step] == :bad
          assert result.successful_steps == %i[fine]
        end

        test "transaction works inside the block" do
          tx_seq = Class.new do
            include Hubbado::Sequence::Sequencer
            define_singleton_method(:name) { "Seqs::BlockFormTx" }

            define_method(:call) do |ctx|
              pipeline(ctx) do |p|
                p.step(:before_tx)
                p.transaction do |t|
                  t.step(:inside_tx)
                end
                p.step(:after_tx)
              end
            end

            define_method(:before_tx) { |ctx| ctx[:before] = true; Hubbado::Sequence::Result.success(ctx) }
            define_method(:inside_tx) { |ctx| ctx[:inside] = true; Hubbado::Sequence::Result.success(ctx) }
            define_method(:after_tx)  { |ctx| ctx[:after]  = true; Hubbado::Sequence::Result.success(ctx) }
          end

          result = tx_seq.()

          assert result.success?
          assert result.ctx[:before]
          assert result.ctx[:inside]
          assert result.ctx[:after]
        end

        test "without a block, returns the pipeline (chained form still works)" do
          chain_seq = Class.new do
            include Hubbado::Sequence::Sequencer
            define_singleton_method(:name) { "Seqs::Chained" }

            define_method(:call) do |ctx|
              pipeline(ctx)
                .step(:set)
                .result
            end

            define_method(:set) { |ctx| ctx[:set] = true; Hubbado::Sequence::Result.success(ctx) }
          end

          result = chain_seq.()

          assert result.success?
          assert result.ctx[:set]
        end
      end
    end
  end
end
