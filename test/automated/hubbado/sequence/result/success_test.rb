require_relative "../../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "Result" do
      context ".success" do
        test "wraps the given ctx as a successful result" do
          ctx = { user: :a_user }
          result = Hubbado::Sequence::Result.success(ctx)

          assert result.success?
          refute result.failure?
          assert result.ctx == ctx
        end

        test "has no error" do
          result = Hubbado::Sequence::Result.success({})

          assert result.error.nil?
        end

        test "has empty successful_steps by default" do
          result = Hubbado::Sequence::Result.success({})

          assert result.successful_steps == []
        end
      end

      context ".failure" do
        test "wraps the given ctx as a failed result" do
          ctx = { user: :a_user }
          result = Hubbado::Sequence::Result.failure(ctx, error: { code: :forbidden })

          refute result.success?
          assert result.failure?
          assert result.ctx == ctx
        end

        test "captures the error payload" do
          result = Hubbado::Sequence::Result.failure({}, error: { code: :forbidden, message: "nope" })

          assert result.error[:code] == :forbidden
          assert result.error[:message] == "nope"
        end

        test "raises when no code is given" do
          assert_raises ArgumentError do
            Hubbado::Sequence::Result.failure({}, error: {})
          end
        end
      end
    end
  end
end
