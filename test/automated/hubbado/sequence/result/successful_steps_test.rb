require_relative "../../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "Result" do
      context "#successful_steps" do
        test "is captured when supplied" do
          result = Hubbado::Sequence::Result.success({}, successful_steps: %i[find_user check_policy])

          assert result.successful_steps == %i[find_user check_policy]
        end

        test "is captured for failed results" do
          result = Hubbado::Sequence::Result.failure(
            {},
            code: :forbidden,
            successful_steps: %i[find_user]
          )

          assert result.successful_steps == %i[find_user]
        end

        test "with_successful_steps returns a new result with successful_steps set" do
          result = Hubbado::Sequence::Result.success({})

          updated = result.with_successful_steps(%i[find_user check_policy])

          assert result.successful_steps == []
          assert updated.successful_steps == %i[find_user check_policy]
          assert updated.ctx.equal?(result.ctx)
        end

        test "with_successful_steps preserves the failure status and code on a failed result" do
          result = Hubbado::Sequence::Result.failure({}, code: :forbidden)

          updated = result.with_successful_steps(%i[find_user])

          assert updated.failure?
          assert updated.code == :forbidden
          assert updated.successful_steps == %i[find_user]
        end
      end
    end
  end
end
