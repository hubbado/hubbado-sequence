require_relative "../../../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "Macros" do
      context "Contract::Deserialize" do
        deserialize = Hubbado::Sequence::Macros::Contract::Deserialize.new

        context "from: with a nested path" do
          test "passes the nested params to the contract" do
            contract = Hubbado::Sequence::Controls::Contract.example
            ctx = Hubbado::Sequence::Ctx.build(
              contract: contract,
              params: { user: { name: "Alice" } }
            )

            result = deserialize.(ctx, from: %i[params user])

            assert result.ok?
            assert contract.deserialized_with == { name: "Alice" }
          end
        end

        context "from: with a single symbol" do
          test "passes the value at that ctx key to the contract" do
            contract = Hubbado::Sequence::Controls::Contract.example
            ctx = Hubbado::Sequence::Ctx.build(
              contract: contract,
              user_attributes: { name: "Alice" }
            )

            result = deserialize.(ctx, from: :user_attributes)

            assert result.ok?
            assert contract.deserialized_with == { name: "Alice" }
          end
        end

        context "missing path" do
          test "is a no-op when the path is absent from ctx" do
            contract = Hubbado::Sequence::Controls::Contract.example
            ctx = Hubbado::Sequence::Ctx.build(contract: contract, params: {})

            result = deserialize.(ctx, from: %i[params user])

            assert result.ok?
            assert contract.deserialized_with.nil?
          end
        end

        context ".build" do
          test "constructs an instance" do
            instance = Hubbado::Sequence::Macros::Contract::Deserialize.build

            assert instance.is_a?(Hubbado::Sequence::Macros::Contract::Deserialize)
          end
        end

        context "Substitute" do
          seq_class = Class.new do
            include Hubbado::Sequence::Sequencer

            def self.name; "Seqs::WithDeserialize"; end
          end
          seq_class.dependency :deserialize_to_contract, Hubbado::Sequence::Macros::Contract::Deserialize

          test "default behaviour is pass-through ok" do
            seq = seq_class.new

            result = seq.deserialize_to_contract.(Hubbado::Sequence::Ctx.new, from: :params)

            assert result.ok?
          end

          test "fail_with(**error) returns a failed result" do
            seq = seq_class.new
            seq.deserialize_to_contract.fail_with(code: :something_wrong)

            result = seq.deserialize_to_contract.(Hubbado::Sequence::Ctx.new, from: :params)

            assert result.failure?
            assert result.error[:code] == :something_wrong
          end

          test "deserialized? records the from: argument" do
            seq = seq_class.new
            seq.deserialize_to_contract.(Hubbado::Sequence::Ctx.new, from: %i[params user])

            assert seq.deserialize_to_contract.deserialized?
            assert seq.deserialize_to_contract.deserialized?(from: %i[params user])
            refute seq.deserialize_to_contract.deserialized?(from: :other)
          end
        end
      end
    end
  end
end
