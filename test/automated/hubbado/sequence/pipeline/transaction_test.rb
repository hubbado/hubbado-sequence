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

        dispatcher_ok = -> {
          Class.new do
            define_method(:before)      { |ctx| ctx[:before] = true; Hubbado::Sequence::Result.success(ctx) }
            define_method(:inside)      { |ctx| ctx[:inside] = true; Hubbado::Sequence::Result.success(ctx) }
            define_method(:after)       { |ctx| ctx[:after]  = true; Hubbado::Sequence::Result.success(ctx) }
            define_method(:fail_inside) { |ctx| Hubbado::Sequence::Result.failure(ctx, error: { code: :boom }) }
            define_method(:fail_first)  { |ctx| Hubbado::Sequence::Result.failure(ctx, error: { code: :nope }) }
            define_method(:should_not_run) { |_ctx| raise "should not be called" }
          end.new
        }

        context "without ActiveRecord defined" do
          test "runs the block inline as part of the same pipeline" do
            pipeline = Hubbado::Sequence::Pipeline.new(Hubbado::Sequence::Ctx.new, dispatcher: dispatcher_ok.call)
              .step(:before)
              .transaction do |p|
                p.step(:inside)
              end
              .step(:after)

            assert pipeline.result.success?
            assert pipeline.result.ctx[:before]
            assert pipeline.result.ctx[:inside]
            assert pipeline.result.ctx[:after]
            assert pipeline.result.successful_steps == %i[before inside after]
          end

          test "propagates an inner failure outward" do
            pipeline = Hubbado::Sequence::Pipeline.new(Hubbado::Sequence::Ctx.new, dispatcher: dispatcher_ok.call)
              .transaction do |p|
                p.step(:fail_inside)
              end
              .step(:after)

            assert pipeline.result.failure?
            assert pipeline.result.error[:code] == :boom
            assert pipeline.result.error[:step] == :fail_inside
          end
        end

        context "with ActiveRecord defined" do
          test "wraps inner steps in ActiveRecord::Base.transaction" do
            with_active_record.call do
              Hubbado::Sequence::Pipeline.new(Hubbado::Sequence::Ctx.new, dispatcher: dispatcher_ok.call)
                .transaction do |p|
                  p.step(:inside)
                end

              assert ActiveRecord.transactions == 1
              assert ActiveRecord.rollbacks == 0
            end
          end

          test "raises ActiveRecord::Rollback when an inner step fails" do
            with_active_record.call do
              Hubbado::Sequence::Pipeline.new(Hubbado::Sequence::Ctx.new, dispatcher: dispatcher_ok.call)
                .transaction do |p|
                  p.step(:fail_inside)
                end

              assert ActiveRecord.rollbacks == 1
            end
          end

          test "the failed Result still propagates to the caller" do
            with_active_record.call do
              pipeline = Hubbado::Sequence::Pipeline.new(Hubbado::Sequence::Ctx.new, dispatcher: dispatcher_ok.call)
                .transaction do |p|
                  p.step(:fail_inside)
                end

              assert pipeline.result.failure?
              assert pipeline.result.error[:code] == :boom
            end
          end

          test "skips a transaction when the pipeline has already failed" do
            with_active_record.call do
              Hubbado::Sequence::Pipeline.new(Hubbado::Sequence::Ctx.new, dispatcher: dispatcher_ok.call)
                .step(:fail_first)
                .transaction do |p|
                  p.step(:should_not_run)
                end

              assert ActiveRecord.transactions == 0
            end
          end
        end
      end
    end
  end
end
