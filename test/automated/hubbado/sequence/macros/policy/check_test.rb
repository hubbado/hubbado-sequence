require_relative "../../../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "Macros" do
      context "Policy::Check" do
        context "permitted action" do
          test "returns success" do
            policy_class = Hubbado::Sequence::Controls::Policy.example_class(decision: :permit, action: :update)

            check_policy = Hubbado::Sequence::Macros::Policy::Check.new

            ctx = Hubbado::Sequence::Ctx.build(current_user: :alice, user: :a_record)
            result = check_policy.(ctx, policy_class, :user, :update)

            assert result.success?
          end
        end

        context "denied action" do
          test "returns failure with code :forbidden" do
            policy_class = Hubbado::Sequence::Controls::Policy.example_class(decision: :deny, action: :update)

            check_policy = Hubbado::Sequence::Macros::Policy::Check.new

            ctx = Hubbado::Sequence::Ctx.build(current_user: :alice, user: :a_record)
            result = check_policy.(ctx, policy_class, :user, :update)

            assert result.failure?
            assert result.code == :forbidden
          end

          test "carries the policy and its result on data" do
            policy_class = Hubbado::Sequence::Controls::Policy.example_class(decision: :deny, action: :update)

            check_policy = Hubbado::Sequence::Macros::Policy::Check.new

            ctx = Hubbado::Sequence::Ctx.build(current_user: :alice, user: :a_record)
            result = check_policy.(ctx, policy_class, :user, :update)

            assert result.data[:policy].is_a?(policy_class)
            assert result.data[:policy_result].denied?
          end
        end

        context "Substitute" do
          policy_class = Hubbado::Sequence::Controls::Policy.example_class(decision: :permit, action: :update)

          seq_class = Class.new do
            include Hubbado::Sequence::Sequencer

            def self.name; "Seqs::WithCheckPolicy"; end
          end
          seq_class.dependency :check_policy, Hubbado::Sequence::Macros::Policy::Check

          test "default behaviour is pass-through success" do
            seq = seq_class.new

            result = seq.check_policy.(Hubbado::Sequence::Ctx.new, policy_class, :user, :update)

            assert result.success?
          end

          test "succeed_with takes no args; policy passes" do
            seq = seq_class.new
            seq.check_policy.succeed_with

            result = seq.check_policy.(Hubbado::Sequence::Ctx.new, policy_class, :user, :update)

            assert result.success?
          end

          test "fail_with(**error) returns a failed result" do
            seq = seq_class.new
            seq.check_policy.fail_with(code: :forbidden, data: { reason: :not_owner })

            result = seq.check_policy.(Hubbado::Sequence::Ctx.new, policy_class, :user, :update)

            assert result.failure?
            assert result.code == :forbidden
            assert result.data == { reason: :not_owner }
          end

          test "checked? records calls" do
            seq = seq_class.new
            seq.check_policy.(Hubbado::Sequence::Ctx.new, policy_class, :user, :update)

            assert seq.check_policy.checked?
          end

          test "raises ArgumentError when the configured policy does not declare the action" do
            seq = seq_class.new

            captured = nil
            begin
              seq.check_policy.(Hubbado::Sequence::Ctx.new, policy_class, :user, :unknown_action)
            rescue ArgumentError => e
              captured = e
            end

            refute captured.nil?
            assert captured.message.include?("does not declare action :unknown_action")
          end
        end
      end
    end
  end
end
