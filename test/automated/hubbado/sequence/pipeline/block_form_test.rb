require_relative "../../../../test_init"

# Block form: `Pipeline.(ctx) { |p| ... }` and `pipeline(ctx) { |p| ... }`
# yield the pipeline, run the block, and return the final Result. Removes the
# `p.result` boilerplate at the end of every sequencer's call body.

context "Hubbado" do
  context "Sequencer" do
    context "Pipeline block form" do
      context "Pipeline.(ctx) { |p| ... }" do
        test "returns the Result automatically" do
          result = Hubbado::Sequence::Pipeline.(value: 1) do |p|
            p.step(:double) { |c| c[:value] = c[:value] * 2; Hubbado::Sequence::Result.ok(c) }
          end

          assert result.is_a?(Hubbado::Sequence::Result)
          assert result.ok?
          assert result.ctx[:value] == 2
        end

        test "yields the pipeline so statement form works inside the block" do
          result = Hubbado::Sequence::Pipeline.() do |p|
            p.step(:a) { |c| c[:a] = true; Hubbado::Sequence::Result.ok(c) }
            p.step(:b) { |c| c[:b] = true; Hubbado::Sequence::Result.ok(c) }
          end

          assert result.ctx[:a]
          assert result.ctx[:b]
          assert result.trail == %i[a b]
        end

        test "supports conditionals naturally inside the block" do
          should_run_extra = true
          result = Hubbado::Sequence::Pipeline.() do |p|
            p.step(:always)        { |c| Hubbado::Sequence::Result.ok(c) }
            p.step(:extra)         { |c| Hubbado::Sequence::Result.ok(c) } if should_run_extra
            p.step(:always_again)  { |c| Hubbado::Sequence::Result.ok(c) }
          end

          assert result.trail == %i[always extra always_again]
        end

        test "propagates failure as the returned Result" do
          result = Hubbado::Sequence::Pipeline.() do |p|
            p.step(:fine) { |c| Hubbado::Sequence::Result.ok(c) }
            p.step(:bad)  { |c| Hubbado::Sequence::Result.fail(c, error: { code: :nope }) }
          end

          assert result.failure?
          assert result.error[:code] == :nope
          assert result.error[:step] == :bad
          assert result.trail == %i[fine]
        end

        test "without a block, returns the pipeline (chained form still works)" do
          pipe = Hubbado::Sequence::Pipeline.(value: 1)

          assert pipe.is_a?(Hubbado::Sequence::Pipeline)
        end

        test "blockless step inside the block raises (no dispatcher)" do
          assert_raises ArgumentError do
            Hubbado::Sequence::Pipeline.() do |p|
              p.step(:no_block_no_dispatcher)
            end
          end
        end
      end

      context "pipeline(ctx) { |p| ... } from a sequencer" do
        seq_class = Class.new do
          include Hubbado::Sequence
          define_singleton_method(:name) { "Seqs::BlockForm" }

          define_method(:call) do |ctx|
            pipeline(ctx) do |p|
              p.step(:double_value)
              p.step(:add_one)
              p.step(:tag) { |c| c[:tagged] = true; Hubbado::Sequence::Result.ok(c) }
            end
          end

          define_method(:double_value) { |ctx| ctx[:value] = ctx[:value] * 2; Hubbado::Sequence::Result.ok(ctx) }
          define_method(:add_one)      { |ctx| ctx[:value] = ctx[:value] + 1; Hubbado::Sequence::Result.ok(ctx) }
        end

        test "returns the Result automatically" do
          result = seq_class.(value: 5)

          assert result.is_a?(Hubbado::Sequence::Result)
          assert result.ok?
          assert result.ctx[:value] == 11
          assert result.ctx[:tagged]
        end

        test "auto-dispatch works inside the block" do
          result = seq_class.(value: 5)

          assert result.trail == %i[double_value add_one tag]
        end

        test "transaction works inside the block" do
          tx_seq = Class.new do
            include Hubbado::Sequence
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

            define_method(:before_tx) { |ctx| ctx[:before] = true; Hubbado::Sequence::Result.ok(ctx) }
            define_method(:inside_tx) { |ctx| ctx[:inside] = true; Hubbado::Sequence::Result.ok(ctx) }
            define_method(:after_tx)  { |ctx| ctx[:after]  = true; Hubbado::Sequence::Result.ok(ctx) }
          end

          result = tx_seq.()

          assert result.ok?
          assert result.ctx[:before]
          assert result.ctx[:inside]
          assert result.ctx[:after]
        end

        test "without a block, returns the pipeline (chained form still works)" do
          chain_seq = Class.new do
            include Hubbado::Sequence
            define_singleton_method(:name) { "Seqs::Chained" }

            define_method(:call) do |ctx|
              pipeline(ctx)
                .step(:set) { |c| c[:set] = true; Hubbado::Sequence::Result.ok(c) }
                .result
            end
          end

          result = chain_seq.()

          assert result.ok?
          assert result.ctx[:set]
        end
      end
    end
  end
end
