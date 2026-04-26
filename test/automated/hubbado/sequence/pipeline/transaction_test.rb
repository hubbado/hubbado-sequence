require_relative "../../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "Pipeline" do
      context "#transaction" do
        # Minimal ActiveRecord stub: tracks transaction and rollback counts.
        active_record_stub = Module.new
        active_record_stub.const_set(:Rollback, Class.new(StandardError))
        active_record_stub.const_set(:Base, Module.new)
        active_record_stub.singleton_class.attr_accessor :transactions, :rollbacks
        active_record_stub.define_singleton_method(:reset) do
          self.transactions = 0
          self.rollbacks = 0
        end
        active_record_stub::Base.define_singleton_method(:transaction) do |&block|
          ::ActiveRecord.transactions += 1
          begin
            block.call
          rescue ::ActiveRecord::Rollback
            ::ActiveRecord.rollbacks += 1
            nil
          end
        end

        with_active_record = ->(&block) {
          Object.const_set(:ActiveRecord, active_record_stub)
          ActiveRecord.reset
          begin
            block.call
          ensure
            Object.send(:remove_const, :ActiveRecord)
          end
        }

        context "without ActiveRecord defined" do
          test "runs the block inline as part of the same pipeline" do
            pipeline = Hubbado::Sequence::Pipeline.()
              .step(:before) { |ctx| ctx[:before] = true; Hubbado::Sequence::Result.ok(ctx) }
              .transaction do |p|
                p.step(:inside) { |ctx| ctx[:inside] = true; Hubbado::Sequence::Result.ok(ctx) }
              end
              .step(:after) { |ctx| ctx[:after] = true; Hubbado::Sequence::Result.ok(ctx) }

            assert pipeline.result.ok?
            assert pipeline.result.ctx[:before]
            assert pipeline.result.ctx[:inside]
            assert pipeline.result.ctx[:after]
            assert pipeline.result.trail == %i[before inside after]
          end

          test "propagates an inner failure outward" do
            pipeline = Hubbado::Sequence::Pipeline.()
              .transaction do |p|
                p.step(:fail_inside) { |ctx| Hubbado::Sequence::Result.fail(ctx, error: { code: :boom }) }
              end
              .step(:after) { |ctx| Hubbado::Sequence::Result.ok(ctx) }

            assert pipeline.result.failure?
            assert pipeline.result.error[:code] == :boom
            assert pipeline.result.error[:step] == :fail_inside
          end
        end

        context "with ActiveRecord defined" do
          test "wraps inner steps in ActiveRecord::Base.transaction" do
            with_active_record.call do
              Hubbado::Sequence::Pipeline.()
                .transaction do |p|
                  p.step(:inside) { |ctx| Hubbado::Sequence::Result.ok(ctx) }
                end

              assert ActiveRecord.transactions == 1
              assert ActiveRecord.rollbacks == 0
            end
          end

          test "raises ActiveRecord::Rollback when an inner step fails" do
            with_active_record.call do
              Hubbado::Sequence::Pipeline.()
                .transaction do |p|
                  p.step(:inside) { |ctx| Hubbado::Sequence::Result.fail(ctx, error: { code: :nope }) }
                end

              assert ActiveRecord.rollbacks == 1
            end
          end

          test "the failed Result still propagates to the caller" do
            with_active_record.call do
              pipeline = Hubbado::Sequence::Pipeline.()
                .transaction do |p|
                  p.step(:inside) { |ctx| Hubbado::Sequence::Result.fail(ctx, error: { code: :nope }) }
                end

              assert pipeline.result.failure?
              assert pipeline.result.error[:code] == :nope
            end
          end

          test "skips a transaction when the pipeline has already failed" do
            with_active_record.call do
              Hubbado::Sequence::Pipeline.()
                .step(:fail_first) { |ctx| Hubbado::Sequence::Result.fail(ctx, error: { code: :nope }) }
                .transaction do |p|
                  p.step(:should_not_run) { |ctx| raise "should not be called" }
                end

              assert ActiveRecord.transactions == 0
            end
          end
        end
      end
    end
  end
end
