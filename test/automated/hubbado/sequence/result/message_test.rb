require_relative "../../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "Result" do
      context "#message" do
        test "is nil when the result is successful" do
          result = Hubbado::Sequence::Result.ok({})

          assert result.message.nil?
        end

        test "uses the inline message field as a fallback" do
          result = Hubbado::Sequence::Result.fail(
            {},
            error: { code: :something_unknown, message: "Inline fallback" }
          )

          assert result.message == "Inline fallback"
        end

        test "humanizes the code when no translation or message is given" do
          result = Hubbado::Sequence::Result.fail(
            {},
            error: { code: :not_shippable }
          )

          assert result.message == "Not shippable"
        end

        test "translates with the framework default scope when present" do
          result = Hubbado::Sequence::Result.fail(
            {},
            error: { code: :forbidden }
          )

          # Framework ships translations under sequence.errors.<code>
          assert result.message == I18n.t("sequence.errors.forbidden")
        end

        test "prefers the sequencer's i18n scope over the framework default" do
          I18n.backend.store_translations(:en, seqs: { update_user: { forbidden: "Sequencer-specific message" } })

          result = Hubbado::Sequence::Result.fail(
            {},
            error: { code: :forbidden },
            i18n_scope: "seqs.update_user"
          )

          assert result.message == "Sequencer-specific message"
        end

        test "prefers the per-error i18n_scope over the result's scope" do
          I18n.backend.store_translations(:en, seqs: { other: { forbidden: "Per-error scope" } })

          result = Hubbado::Sequence::Result.fail(
            {},
            error: { code: :forbidden, i18n_scope: "seqs.other" },
            i18n_scope: "seqs.update_user"
          )

          assert result.message == "Per-error scope"
        end

        test "uses the per-error i18n_key override when supplied" do
          I18n.backend.store_translations(:en, seqs: { update_user: { custom_key: "Custom keyed message" } })

          result = Hubbado::Sequence::Result.fail(
            {},
            error: { code: :forbidden, i18n_key: :custom_key },
            i18n_scope: "seqs.update_user"
          )

          assert result.message == "Custom keyed message"
        end

        test "interpolates i18n_args into the translated message" do
          I18n.backend.store_translations(
            :en,
            seqs: { orders: { not_shippable: "Already shipped at %{shipped_at}" } }
          )

          result = Hubbado::Sequence::Result.fail(
            {},
            error: { code: :not_shippable, i18n_args: { shipped_at: "yesterday" } },
            i18n_scope: "seqs.orders"
          )

          assert result.message == "Already shipped at yesterday"
        end
      end
    end
  end
end
