require_relative "../../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "Pipeline" do
      context "construction" do
        test "builds a Ctx from keyword arguments" do
          pipeline = Hubbado::Sequence::Pipeline.(params: { id: 1 }, current_user: :alice)

          ctx = pipeline.result.ctx

          assert ctx[:params] == { id: 1 }
          assert ctx[:current_user] == :alice
        end

        test "accepts an existing Ctx" do
          ctx = Hubbado::Sequence::Ctx.build(user: :a_user)
          pipeline = Hubbado::Sequence::Pipeline.(ctx)

          assert pipeline.result.ctx.equal?(ctx)
        end

        test "accepts no arguments" do
          pipeline = Hubbado::Sequence::Pipeline.()

          assert pipeline.result.ok?
        end
      end

      context "with no steps" do
        test "result is ok with the initial ctx" do
          pipeline = Hubbado::Sequence::Pipeline.(user: :a_user)

          assert pipeline.result.ok?
          assert pipeline.result.ctx[:user] == :a_user
          assert pipeline.result.trail == []
        end
      end

      context "successful steps" do
        test "runs each step in order, passing ctx" do
          pipeline = Hubbado::Sequence::Pipeline.(initial: 1)
            .step(:double) { |ctx| ctx[:value] = ctx[:initial] * 2; Hubbado::Sequence::Result.ok(ctx) }
            .step(:label)  { |ctx| ctx[:label] = "doubled"; Hubbado::Sequence::Result.ok(ctx) }

          assert pipeline.result.ok?
          assert pipeline.result.ctx[:value] == 2
          assert pipeline.result.ctx[:label] == "doubled"
        end

        test "records each successful step in the trail" do
          pipeline = Hubbado::Sequence::Pipeline.()
            .step(:first)  { |ctx| Hubbado::Sequence::Result.ok(ctx) }
            .step(:second) { |ctx| Hubbado::Sequence::Result.ok(ctx) }

          assert pipeline.result.trail == %i[first second]
        end
      end

      context "failing steps" do
        test "stops the pipeline at the first failure" do
          steps_run = []

          pipeline = Hubbado::Sequence::Pipeline.()
            .step(:first)  { |ctx| steps_run << :first; Hubbado::Sequence::Result.ok(ctx) }
            .step(:second) { |ctx| steps_run << :second; Hubbado::Sequence::Result.fail(ctx, error: { code: :bad }) }
            .step(:third)  { |ctx| steps_run << :third; Hubbado::Sequence::Result.ok(ctx) }

          assert pipeline.result.failure?
          assert steps_run == %i[first second]
        end

        test "tags the failed step name on error[:step]" do
          pipeline = Hubbado::Sequence::Pipeline.()
            .step(:check) { |ctx| Hubbado::Sequence::Result.fail(ctx, error: { code: :forbidden }) }

          assert pipeline.result.error[:step] == :check
        end

        test "trail contains successful steps only, not the failing one" do
          pipeline = Hubbado::Sequence::Pipeline.()
            .step(:first)  { |ctx| Hubbado::Sequence::Result.ok(ctx) }
            .step(:second) { |ctx| Hubbado::Sequence::Result.ok(ctx) }
            .step(:third)  { |ctx| Hubbado::Sequence::Result.fail(ctx, error: { code: :bad }) }

          assert pipeline.result.failure?
          assert pipeline.result.trail == %i[first second]
        end

        test "ctx still carries values written before the failure" do
          pipeline = Hubbado::Sequence::Pipeline.()
            .step(:write) { |ctx| ctx[:user] = :a_user; Hubbado::Sequence::Result.ok(ctx) }
            .step(:fail)  { |ctx| Hubbado::Sequence::Result.fail(ctx, error: { code: :bad }) }

          assert pipeline.result.ctx[:user] == :a_user
        end
      end

      context "non-Result return values (lenient mode)" do
        test "a non-Result return value is treated as success" do
          pipeline = Hubbado::Sequence::Pipeline.()
            .step(:returns_string) { |_ctx| "not a result" }
            .step(:returns_nil)    { |_ctx| nil }
            .step(:returns_false)  { |_ctx| false }
            .step(:returns_model)  { |_ctx| Object.new }

          assert pipeline.result.ok?
          assert pipeline.result.trail == %i[returns_string returns_nil returns_false returns_model]
        end

        test "an explicitly returned failed Result still short-circuits" do
          pipeline = Hubbado::Sequence::Pipeline.()
            .step(:fine)    { |_ctx| nil }
            .step(:explode) { |ctx| Hubbado::Sequence::Result.fail(ctx, error: { code: :nope }) }
            .step(:never)   { |_ctx| raise "should not run" }

          assert pipeline.result.failure?
          assert pipeline.result.error[:code] == :nope
          assert pipeline.result.trail == %i[fine]
        end

        test "an explicitly returned ok Result is honored without re-wrapping" do
          ctx = Hubbado::Sequence::Ctx.build(user: :alice)
          pipeline = Hubbado::Sequence::Pipeline.(ctx)
            .step(:keep_ctx) { |c| Hubbado::Sequence::Result.ok(c) }

          assert pipeline.result.ok?
          assert pipeline.result.ctx.equal?(ctx)
        end
      end

      context "preserves the inner result's i18n_scope" do
        test "when a failed result has its own scope, that scope is kept" do
          inner_scope = "seqs.present"

          pipeline = Hubbado::Sequence::Pipeline.()
            .step(:nested) do |ctx|
              Hubbado::Sequence::Result.fail(ctx, error: { code: :forbidden }, i18n_scope: inner_scope)
            end

          assert pipeline.result.i18n_scope == inner_scope
        end
      end
    end
  end
end
