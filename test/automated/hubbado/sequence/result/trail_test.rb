require_relative "../../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "Result" do
      context "#trail" do
        test "is captured when supplied" do
          result = Hubbado::Sequence::Result.ok({}, trail: %i[find_user check_policy])

          assert result.trail == %i[find_user check_policy]
        end

        test "is captured for failed results" do
          result = Hubbado::Sequence::Result.fail(
            {},
            error: { code: :forbidden },
            trail: %i[find_user]
          )

          assert result.trail == %i[find_user]
        end

        test "with_trail returns a new result with the trail set" do
          result = Hubbado::Sequence::Result.ok({})

          updated = result.with_trail(%i[find_user check_policy])

          assert result.trail == []
          assert updated.trail == %i[find_user check_policy]
          assert updated.ctx.equal?(result.ctx)
        end
      end
    end
  end
end
