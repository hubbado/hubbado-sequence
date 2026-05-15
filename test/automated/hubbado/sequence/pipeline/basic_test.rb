require_relative "../../../../test_init"

# Pipeline runs against a dispatcher: every step name resolves to a method
# of the same name on the dispatcher. These tests build a dispatcher with
# the relevant methods inline.

context "Hubbado" do
  context "Sequencer" do
    context "Pipeline" do
      context "with no steps" do
        test "result is ok with the initial ctx" do
          dispatcher = Class.new.new
          ctx = Hubbado::Sequence::Ctx.build(user: :a_user)
          pipeline = Hubbado::Sequence::Pipeline.new(ctx, dispatcher: dispatcher)

          assert pipeline.result.ok?
          assert pipeline.result.ctx[:user] == :a_user
          assert pipeline.result.trail == []
        end
      end

      context "successful steps" do
        test "runs each step in order, passing ctx" do
          dispatcher = Class.new do
            define_method(:double) { |ctx| ctx[:value] = ctx[:initial] * 2; Hubbado::Sequence::Result.ok(ctx) }
            define_method(:label)  { |ctx| ctx[:label] = "doubled"; Hubbado::Sequence::Result.ok(ctx) }
          end.new

          ctx = Hubbado::Sequence::Ctx.build(initial: 1)
          pipeline = Hubbado::Sequence::Pipeline.new(ctx, dispatcher: dispatcher)
            .step(:double)
            .step(:label)

          assert pipeline.result.ok?
          assert pipeline.result.ctx[:value] == 2
          assert pipeline.result.ctx[:label] == "doubled"
        end

        test "records each successful step in the trail" do
          dispatcher = Class.new do
            define_method(:first)  { |ctx| Hubbado::Sequence::Result.ok(ctx) }
            define_method(:second) { |ctx| Hubbado::Sequence::Result.ok(ctx) }
          end.new

          pipeline = Hubbado::Sequence::Pipeline.new(Hubbado::Sequence::Ctx.new, dispatcher: dispatcher)
            .step(:first)
            .step(:second)

          assert pipeline.result.trail == %i[first second]
        end
      end

      context "failing steps" do
        test "stops the pipeline at the first failure" do
          steps_run = []
          dispatcher = Class.new do
            define_method(:first)  { |ctx| steps_run << :first;  Hubbado::Sequence::Result.ok(ctx) }
            define_method(:second) { |ctx| steps_run << :second; Hubbado::Sequence::Result.fail(ctx, error: { code: :bad }) }
            define_method(:third)  { |ctx| steps_run << :third;  Hubbado::Sequence::Result.ok(ctx) }
          end.new

          pipeline = Hubbado::Sequence::Pipeline.new(Hubbado::Sequence::Ctx.new, dispatcher: dispatcher)
            .step(:first)
            .step(:second)
            .step(:third)

          assert pipeline.result.failure?
          assert steps_run == %i[first second]
        end

        test "tags the failed step name on error[:step]" do
          dispatcher = Class.new do
            define_method(:check) { |ctx| Hubbado::Sequence::Result.fail(ctx, error: { code: :forbidden }) }
          end.new

          pipeline = Hubbado::Sequence::Pipeline.new(Hubbado::Sequence::Ctx.new, dispatcher: dispatcher)
            .step(:check)

          assert pipeline.result.error[:step] == :check
        end

        test "trail contains successful steps only, not the failing one" do
          dispatcher = Class.new do
            define_method(:first)  { |ctx| Hubbado::Sequence::Result.ok(ctx) }
            define_method(:second) { |ctx| Hubbado::Sequence::Result.ok(ctx) }
            define_method(:third)  { |ctx| Hubbado::Sequence::Result.fail(ctx, error: { code: :bad }) }
          end.new

          pipeline = Hubbado::Sequence::Pipeline.new(Hubbado::Sequence::Ctx.new, dispatcher: dispatcher)
            .step(:first)
            .step(:second)
            .step(:third)

          assert pipeline.result.failure?
          assert pipeline.result.trail == %i[first second]
        end

        test "ctx still carries values written before the failure" do
          dispatcher = Class.new do
            define_method(:write) { |ctx| ctx[:user] = :a_user; Hubbado::Sequence::Result.ok(ctx) }
            define_method(:fail)  { |ctx| Hubbado::Sequence::Result.fail(ctx, error: { code: :bad }) }
          end.new

          pipeline = Hubbado::Sequence::Pipeline.new(Hubbado::Sequence::Ctx.new, dispatcher: dispatcher)
            .step(:write)
            .step(:fail)

          assert pipeline.result.ctx[:user] == :a_user
        end
      end

      context "non-Result return values (lenient mode)" do
        test "a non-Result return value is treated as success" do
          dispatcher = Class.new do
            define_method(:returns_string) { |_ctx| "not a result" }
            define_method(:returns_nil)    { |_ctx| nil }
            define_method(:returns_false)  { |_ctx| false }
            define_method(:returns_model)  { |_ctx| Object.new }
          end.new

          pipeline = Hubbado::Sequence::Pipeline.new(Hubbado::Sequence::Ctx.new, dispatcher: dispatcher)
            .step(:returns_string)
            .step(:returns_nil)
            .step(:returns_false)
            .step(:returns_model)

          assert pipeline.result.ok?
          assert pipeline.result.trail == %i[returns_string returns_nil returns_false returns_model]
        end

        test "an explicitly returned failed Result still short-circuits" do
          dispatcher = Class.new do
            define_method(:fine)    { |_ctx| nil }
            define_method(:explode) { |ctx| Hubbado::Sequence::Result.fail(ctx, error: { code: :nope }) }
            define_method(:never)   { |_ctx| raise "should not run" }
          end.new

          pipeline = Hubbado::Sequence::Pipeline.new(Hubbado::Sequence::Ctx.new, dispatcher: dispatcher)
            .step(:fine)
            .step(:explode)
            .step(:never)

          assert pipeline.result.failure?
          assert pipeline.result.error[:code] == :nope
          assert pipeline.result.trail == %i[fine]
        end

        test "an explicitly returned ok Result is honored without re-wrapping" do
          ctx = Hubbado::Sequence::Ctx.build(user: :alice)
          dispatcher = Class.new do
            define_method(:keep_ctx) { |c| Hubbado::Sequence::Result.ok(c) }
          end.new

          pipeline = Hubbado::Sequence::Pipeline.new(ctx, dispatcher: dispatcher)
            .step(:keep_ctx)

          assert pipeline.result.ok?
          assert pipeline.result.ctx.equal?(ctx)
        end
      end

      context "preserves the inner result's i18n_scope" do
        test "when a failed result has its own scope, that scope is kept" do
          inner_scope = "seqs.present"
          dispatcher = Class.new do
            define_method(:nested) do |ctx|
              Hubbado::Sequence::Result.fail(ctx, error: { code: :forbidden }, i18n_scope: inner_scope)
            end
          end.new

          pipeline = Hubbado::Sequence::Pipeline.new(Hubbado::Sequence::Ctx.new, dispatcher: dispatcher)
            .step(:nested)

          assert pipeline.result.i18n_scope == inner_scope
        end
      end

      context "missing dispatcher method" do
        test "raises NoMethodError naming the step and the dispatcher" do
          dispatcher = Class.new do
            define_singleton_method(:name) { "TestDispatcher" }
          end.new

          pipeline = Hubbado::Sequence::Pipeline.new(Hubbado::Sequence::Ctx.new, dispatcher: dispatcher)

          captured = nil
          begin
            pipeline.step(:nope)
          rescue NoMethodError => e
            captured = e
          end

          refute captured.nil?
          assert captured.message.include?("nope")
        end
      end
    end
  end
end
