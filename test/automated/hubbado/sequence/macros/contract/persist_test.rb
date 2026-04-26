require_relative "../../../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "Macros" do
      context "Contract::Persist" do
        persist = Hubbado::Sequence::Macros::Contract::Persist.new

        context "successful save" do
          test "returns ok" do
            contract = Hubbado::Sequence::Controls::Contract.example(save_result: true)
            ctx = Hubbado::Sequence::Ctx.build(contract: contract)

            result = persist.(ctx)

            assert result.ok?
            assert contract.saved
          end
        end

        context "failed save" do
          test "returns failure with code :persist_failed" do
            contract = Hubbado::Sequence::Controls::Contract.example(save_result: false)
            ctx = Hubbado::Sequence::Ctx.build(contract: contract)

            result = persist.(ctx)

            assert result.failure?
            assert result.error[:code] == :persist_failed
          end
        end

        context "Substitute" do
          seq_class = Class.new do
            include Hubbado::Sequence

            def self.name; "Seqs::WithPersist"; end
          end
          seq_class.dependency :persist, Hubbado::Sequence::Macros::Contract::Persist

          test "default behaviour is pass-through ok" do
            seq = seq_class.new

            result = seq.persist.(Hubbado::Sequence::Ctx.new)

            assert result.ok?
          end

          test "succeed_with takes no args; persistence passes" do
            seq = seq_class.new
            seq.persist.succeed_with

            result = seq.persist.(Hubbado::Sequence::Ctx.new)

            assert result.ok?
          end

          test "fail_with(**error) returns a failed result" do
            seq = seq_class.new
            seq.persist.fail_with(code: :persist_failed)

            result = seq.persist.(Hubbado::Sequence::Ctx.new)

            assert result.failure?
            assert result.error[:code] == :persist_failed
          end

          test "persisted? records calls" do
            seq = seq_class.new
            seq.persist.(Hubbado::Sequence::Ctx.new)

            assert seq.persist.persisted?
          end
        end
      end
    end
  end
end
