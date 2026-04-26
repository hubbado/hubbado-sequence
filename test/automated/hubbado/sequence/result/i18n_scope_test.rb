require_relative "../../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "Result" do
      context "#i18n_scope" do
        test "defaults to nil for a result with no scope" do
          result = Hubbado::Sequence::Result.ok({})

          assert result.i18n_scope.nil?
        end

        test "carries the supplied scope" do
          result = Hubbado::Sequence::Result.ok({}, i18n_scope: "seqs.update_user")

          assert result.i18n_scope == "seqs.update_user"
        end

        context "#with_i18n_scope" do
          test "returns a new result with the scope set" do
            result = Hubbado::Sequence::Result.ok({})

            updated = result.with_i18n_scope("seqs.update_user")

            assert result.i18n_scope.nil?
            assert updated.i18n_scope == "seqs.update_user"
          end

          test "is a no-op when the result already has a scope (innermost wins)" do
            result = Hubbado::Sequence::Result.ok({}, i18n_scope: "seqs.present")

            updated = result.with_i18n_scope("seqs.update_user")

            assert updated.i18n_scope == "seqs.present"
          end
        end
      end
    end
  end
end
