require_relative "../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "RunSequence" do
      # A canned-result sequencer: returns whatever Result the test set up.
      sequencer_with_canned = ->(canned_result) {
        Class.new do
          include Hubbado::Sequence::Sequencer

          define_singleton_method(:name) { "Seqs::Canned" }

          define_method(:call) do |_ctx|
            canned_result
          end

          define_singleton_method(:build) { new }
        end
      }

      controller_with_run = ->() {
        Class.new do
          include Hubbado::Sequence::RunSequence
        end.new
      }

      ctx = ->() { Hubbado::Sequence::Ctx.new }

      context "successful result" do
        result = Hubbado::Sequence::Result.ok(ctx.())
        seq_class = sequencer_with_canned.(result)

        test "fires only the success block" do
          ran = []
          controller_with_run.().run_sequence(seq_class) do |r|
            r.success           { |_| ran << :success }
            r.policy_failed     { |_| ran << :policy_failed }
            r.not_found         { |_| ran << :not_found }
            r.validation_failed { |_| ran << :validation_failed }
            r.otherwise         { |_| ran << :otherwise }
          end

          assert ran == [:success]
        end

        test "yields the ctx to the success block" do
          received_ctx = nil
          controller_with_run.().run_sequence(seq_class) do |r|
            r.success { |c| received_ctx = c }
          end

          assert received_ctx.is_a?(Hubbado::Sequence::Ctx)
        end

        test "returns the success block's value" do
          returned = controller_with_run.().run_sequence(seq_class) do |r|
            r.success { |_| :all_good }
          end

          assert returned == :all_good
        end
      end

      context "policy failed (:forbidden)" do
        result = Hubbado::Sequence::Result.fail(ctx.(), error: { code: :forbidden })
        seq_class = sequencer_with_canned.(result)

        test "fires only the policy_failed block" do
          ran = []
          controller_with_run.().run_sequence(seq_class) do |r|
            r.success           { |_| ran << :success }
            r.policy_failed     { |_| ran << :policy_failed }
            r.not_found         { |_| ran << :not_found }
            r.validation_failed { |_| ran << :validation_failed }
            r.otherwise         { |_| ran << :otherwise }
          end

          assert ran == [:policy_failed]
        end

        test "raises Errors::Unauthorized when no policy_failed block is given" do
          assert_raises Hubbado::Sequence::Errors::Unauthorized do
            controller_with_run.().run_sequence(seq_class) do |r|
              r.success { |_| :unused }
            end
          end
        end

        test "otherwise does not catch policy failures" do
          assert_raises Hubbado::Sequence::Errors::Unauthorized do
            controller_with_run.().run_sequence(seq_class) do |r|
              r.otherwise { |_| :should_not_run }
            end
          end
        end
      end

      context "not found" do
        result = Hubbado::Sequence::Result.fail(ctx.(), error: { code: :not_found })
        seq_class = sequencer_with_canned.(result)

        test "fires only the not_found block" do
          ran = []
          controller_with_run.().run_sequence(seq_class) do |r|
            r.success           { |_| ran << :success }
            r.policy_failed     { |_| ran << :policy_failed }
            r.not_found         { |_| ran << :not_found }
            r.validation_failed { |_| ran << :validation_failed }
            r.otherwise         { |_| ran << :otherwise }
          end

          assert ran == [:not_found]
        end

        test "raises Errors::NotFound when no not_found block is given" do
          assert_raises Hubbado::Sequence::Errors::NotFound do
            controller_with_run.().run_sequence(seq_class) do |r|
              r.success { |_| :unused }
            end
          end
        end

        test "otherwise does not catch not_found" do
          assert_raises Hubbado::Sequence::Errors::NotFound do
            controller_with_run.().run_sequence(seq_class) do |r|
              r.otherwise { |_| :should_not_run }
            end
          end
        end
      end

      context "validation failed" do
        result = Hubbado::Sequence::Result.fail(ctx.(), error: { code: :validation_failed })
        seq_class = sequencer_with_canned.(result)

        test "fires only the validation_failed block" do
          ran = []
          controller_with_run.().run_sequence(seq_class) do |r|
            r.success           { |_| ran << :success }
            r.validation_failed { |_| ran << :validation_failed }
            r.otherwise         { |_| ran << :otherwise }
          end

          assert ran == [:validation_failed]
        end

        test "falls through to otherwise when no validation_failed block is given" do
          ran = []
          controller_with_run.().run_sequence(seq_class) do |r|
            r.otherwise { |_| ran << :otherwise }
          end

          assert ran == [:otherwise]
        end

        test "raises Errors::Failed when no specific handler and no otherwise" do
          assert_raises Hubbado::Sequence::Errors::Failed do
            controller_with_run.().run_sequence(seq_class) do |r|
              r.success { |_| :unused }
            end
          end
        end
      end

      context "unknown error code" do
        result = Hubbado::Sequence::Result.fail(ctx.(), error: { code: :something_strange })
        seq_class = sequencer_with_canned.(result)

        test "falls through to otherwise" do
          ran = []
          controller_with_run.().run_sequence(seq_class) do |r|
            r.otherwise { |_| ran << :otherwise }
          end

          assert ran == [:otherwise]
        end

        test "raises Errors::Failed when there is no otherwise block" do
          assert_raises Hubbado::Sequence::Errors::Failed do
            controller_with_run.().run_sequence(seq_class) do |r|
              r.success { |_| :unused }
            end
          end
        end
      end

      context "kwargs are forwarded to the sequencer's ctx" do
        test "controller-supplied kwargs become initial ctx keys" do
          klass = Class.new do
            include Hubbado::Sequence::Sequencer
            define_singleton_method(:name) { "Seqs::WithKwargs" }
            define_singleton_method(:build) { new }
          end

          captured = nil
          klass.define_method(:call) do |ctx|
            captured = ctx
            Hubbado::Sequence::Result.ok(ctx)
          end

          controller_with_run.().run_sequence(klass, params: { id: 1 }, current_user: :alice) do |r|
            r.success { |_| nil }
          end

          assert captured.is_a?(Hubbado::Sequence::Ctx)
          assert captured[:params] == { id: 1 }
          assert captured[:current_user] == :alice
        end
      end
    end
  end
end
