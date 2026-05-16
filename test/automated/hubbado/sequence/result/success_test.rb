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

        test "has no failure payload" do
          result = Hubbado::Sequence::Result.success({})

          assert result.code.nil?
          assert result.data.nil?
        end

        test "has empty successful_steps by default" do
          result = Hubbado::Sequence::Result.success({})

          assert result.successful_steps == []
        end
      end

      context ".failure" do
        test "wraps the given ctx as a failed result" do
          ctx = { user: :a_user }
          result = Hubbado::Sequence::Result.failure(ctx, code: :forbidden)

          refute result.success?
          assert result.failure?
          assert result.ctx == ctx
        end

        test "captures the failure payload" do
          result = Hubbado::Sequence::Result.failure(
            {},
            code: :forbidden,
            data: { reason: :not_owner }
          )

          assert result.code == :forbidden
          assert result.data == { reason: :not_owner }
        end

        test "raises when no code is given" do
          assert_raises ArgumentError do
            Hubbado::Sequence::Result.failure({})
          end
        end
      end
    end
  end
end
