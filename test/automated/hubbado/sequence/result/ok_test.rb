require_relative "../../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "Result" do
      context ".ok" do
        test "wraps the given ctx as a successful result" do
          ctx = { user: :a_user }
          result = Hubbado::Sequence::Result.ok(ctx)

          assert result.ok?
          refute result.failure?
          assert result.ctx == ctx
        end

        test "has no error" do
          result = Hubbado::Sequence::Result.ok({})

          assert result.error.nil?
        end

        test "has an empty trail by default" do
          result = Hubbado::Sequence::Result.ok({})

          assert result.trail == []
        end
      end

      context ".fail" do
        test "wraps the given ctx as a failed result" do
          ctx = { user: :a_user }
          result = Hubbado::Sequence::Result.fail(ctx, error: { code: :forbidden })

          refute result.ok?
          assert result.failure?
          assert result.ctx == ctx
        end

        test "captures the error payload" do
          result = Hubbado::Sequence::Result.fail({}, error: { code: :forbidden, message: "nope" })

          assert result.error[:code] == :forbidden
          assert result.error[:message] == "nope"
        end

        test "raises when no code is given" do
          assert_raises ArgumentError do
            Hubbado::Sequence::Result.fail({}, error: {})
          end
        end
      end
    end
  end
end
