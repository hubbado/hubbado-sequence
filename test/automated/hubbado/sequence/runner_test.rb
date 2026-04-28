require_relative "../../../test_init"

context "Hubbado" do
  context "Sequence" do
    context "Runner" do
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

      ctx = ->() { Hubbado::Sequence::Ctx.new }

      context "successful result" do
        result = Hubbado::Sequence::Result.ok(ctx.())
        seq_class = sequencer_with_canned.(result)

        test "fires only the success block" do
          ran = []
          Hubbado::Sequence::Runner.new.(seq_class) do |r|
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
          Hubbado::Sequence::Runner.new.(seq_class) do |r|
            r.success { |c| received_ctx = c }
          end

          assert received_ctx.is_a?(Hubbado::Sequence::Ctx)
        end

        test "returns the success block's value" do
          returned = Hubbado::Sequence::Runner.new.(seq_class) do |r|
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
          Hubbado::Sequence::Runner.new.(seq_class) do |r|
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
            Hubbado::Sequence::Runner.new.(seq_class) do |r|
              r.success { |_| :unused }
            end
          end
        end

        test "otherwise does not catch policy failures" do
          assert_raises Hubbado::Sequence::Errors::Unauthorized do
            Hubbado::Sequence::Runner.new.(seq_class) do |r|
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
          Hubbado::Sequence::Runner.new.(seq_class) do |r|
            r.not_found { |_| ran << :not_found }
            r.otherwise { |_| ran << :otherwise }
          end

          assert ran == [:not_found]
        end

        test "raises Errors::NotFound when no not_found block is given" do
          assert_raises Hubbado::Sequence::Errors::NotFound do
            Hubbado::Sequence::Runner.new.(seq_class) do |r|
              r.success { |_| :unused }
            end
          end
        end
      end

      context "validation failed" do
        result = Hubbado::Sequence::Result.fail(ctx.(), error: { code: :validation_failed })
        seq_class = sequencer_with_canned.(result)

        test "fires only the validation_failed block" do
          ran = []
          Hubbado::Sequence::Runner.new.(seq_class) do |r|
            r.validation_failed { |_| ran << :validation_failed }
            r.otherwise         { |_| ran << :otherwise }
          end

          assert ran == [:validation_failed]
        end

        test "falls through to otherwise when no validation_failed block is given" do
          ran = []
          Hubbado::Sequence::Runner.new.(seq_class) do |r|
            r.otherwise { |_| ran << :otherwise }
          end

          assert ran == [:otherwise]
        end

        test "raises Errors::Failed when no specific handler and no otherwise" do
          assert_raises Hubbado::Sequence::Errors::Failed do
            Hubbado::Sequence::Runner.new.(seq_class) do |r|
              r.success { |_| :unused }
            end
          end
        end
      end

      context "kwargs are forwarded to the sequencer's ctx" do
        test "supplied kwargs become initial ctx keys" do
          klass = Class.new do
            include Hubbado::Sequence::Sequencer
            define_singleton_method(:name) { "Seqs::WithKwargs" }
            define_singleton_method(:build) { new }
          end

          captured = nil
          klass.define_method(:call) do |c|
            captured = c
            Hubbado::Sequence::Result.ok(c)
          end

          Hubbado::Sequence::Runner.new.(klass, params: { id: 1 }, current_user: :alice) do |r|
            r.success { |_| nil }
          end

          assert captured.is_a?(Hubbado::Sequence::Ctx)
          assert captured[:params] == { id: 1 }
          assert captured[:current_user] == :alice
        end
      end

      context "block is optional" do
        test "still executes the sequencer when no block is given for a successful result" do
          result = Hubbado::Sequence::Result.ok(ctx.())
          seq_class = sequencer_with_canned.(result)

          # No block: success path means nothing to dispatch, no safety net trigger.
          returned = Hubbado::Sequence::Runner.new.(seq_class)

          assert returned.nil?
        end
      end
    end
  end
end
