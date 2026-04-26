require_relative "../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "RunSequence" do
      context "logging" do
        sequencer_with_canned = ->(canned_result) {
          Class.new do
            include Hubbado::Sequence

            define_singleton_method(:name) { "Seqs::Logged" }

            define_method(:call) do |_ctx|
              canned_result
            end

            define_singleton_method(:build) { new }
          end
        }

        controller = ->() {
          Class.new do
            include Hubbado::Sequence::RunSequence
          end.new
        }

        log_handler = ->() { Hubbado::Log.loggers.first }

        ctx_with_trail = ->(trail) {
          # Bypass strict access via fetch — Result.with_trail keeps the same ctx.
          Hubbado::Sequence::Ctx.new
        }

        context "success" do
          test "logs at info with the trail" do
            result = Hubbado::Sequence::Result.ok(Hubbado::Sequence::Ctx.new, trail: %i[find build])
            seq_class = sequencer_with_canned.(result)

            controller.().run_sequence(seq_class) do |r|
              r.success { |_| nil }
            end

            assert log_handler.().severity == :info
            assert log_handler.().message == "Sequencer Seqs::Logged succeeded: find → build"
          end

          test "logs even when the trail is empty" do
            result = Hubbado::Sequence::Result.ok(Hubbado::Sequence::Ctx.new)
            seq_class = sequencer_with_canned.(result)

            controller.().run_sequence(seq_class) do |r|
              r.success { |_| nil }
            end

            assert log_handler.().message == "Sequencer Seqs::Logged succeeded: (no steps)"
          end
        end

        context "policy_failed" do
          test "logs the failed step and code" do
            result = Hubbado::Sequence::Result.fail(
              Hubbado::Sequence::Ctx.new,
              error: { code: :forbidden, step: :check_policy },
              trail: %i[find_user build_contract]
            )
            seq_class = sequencer_with_canned.(result)

            controller.().run_sequence(seq_class) do |r|
              r.policy_failed { |_| nil }
            end

            assert log_handler.().severity == :info
            assert log_handler.().message == "Sequencer Seqs::Logged policy failed at :check_policy (forbidden): find_user → build_contract"
          end

          test "logs at error level when no handler runs (safety net)" do
            result = Hubbado::Sequence::Result.fail(
              Hubbado::Sequence::Ctx.new,
              error: { code: :forbidden, step: :check_policy },
              trail: %i[find_user]
            )
            seq_class = sequencer_with_canned.(result)

            assert_raises Hubbado::Sequence::Errors::Unauthorized do
              controller.().run_sequence(seq_class) { |r| r.success { |_| nil } }
            end

            assert log_handler.().severity == :error
          end
        end

        context "not_found" do
          test "logs the failed step" do
            result = Hubbado::Sequence::Result.fail(
              Hubbado::Sequence::Ctx.new,
              error: { code: :not_found, step: :find_user },
              trail: []
            )
            seq_class = sequencer_with_canned.(result)

            controller.().run_sequence(seq_class) do |r|
              r.not_found { |_| nil }
            end

            assert log_handler.().message == "Sequencer Seqs::Logged not found at :find_user: (no steps)"
          end
        end

        context "validation_failed" do
          test "logs the failed step" do
            result = Hubbado::Sequence::Result.fail(
              Hubbado::Sequence::Ctx.new,
              error: { code: :validation_failed, step: :validate },
              trail: %i[find_user build_contract check_policy]
            )
            seq_class = sequencer_with_canned.(result)

            controller.().run_sequence(seq_class) do |r|
              r.validation_failed { |_| nil }
            end

            assert log_handler.().message == "Sequencer Seqs::Logged validation failed at :validate: find_user → build_contract → check_policy"
          end
        end

        context "otherwise" do
          test "logs the code that fell through" do
            result = Hubbado::Sequence::Result.fail(
              Hubbado::Sequence::Ctx.new,
              error: { code: :persist_failed, step: :persist },
              trail: %i[find_user build_contract check_policy validate]
            )
            seq_class = sequencer_with_canned.(result)

            controller.().run_sequence(seq_class) do |r|
              r.otherwise { |_| nil }
            end

            assert log_handler.().message == "Sequencer Seqs::Logged failed at :persist (persist_failed): find_user → build_contract → check_policy → validate"
          end
        end
      end
    end
  end
end
