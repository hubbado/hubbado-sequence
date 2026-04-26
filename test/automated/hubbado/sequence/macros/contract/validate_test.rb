require_relative "../../../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "Macros" do
      context "Contract::Validate" do
        validate = Hubbado::Sequence::Macros::Contract::Validate.new

        context "valid contract" do
          test "returns ok and passes params to the contract" do
            contract = Hubbado::Sequence::Controls::Contract.example(valid: true)
            ctx = Hubbado::Sequence::Ctx.build(
              contract: contract,
              params: { user: { name: "Alice" } }
            )

            result = validate.(ctx, from: %i[params user])

            assert result.ok?
            assert contract.validated_with == { name: "Alice" }
          end
        end

        context "invalid contract" do
          test "returns failure with code :validation_failed" do
            contract = Hubbado::Sequence::Controls::Contract.example(valid: false)
            ctx = Hubbado::Sequence::Ctx.build(
              contract: contract,
              params: { user: { name: "" } }
            )

            result = validate.(ctx, from: %i[params user])

            assert result.failure?
            assert result.error[:code] == :validation_failed
          end

          test "the contract is still validated (errors populated)" do
            contract = Hubbado::Sequence::Controls::Contract.example(valid: false)
            ctx = Hubbado::Sequence::Ctx.build(
              contract: contract,
              params: { user: { name: "" } }
            )

            validate.(ctx, from: %i[params user])

            refute contract.errors.empty?
          end
        end

        context "from: with a single symbol" do
          test "reads directly from a single ctx key" do
            contract = Hubbado::Sequence::Controls::Contract.example(valid: true)
            ctx = Hubbado::Sequence::Ctx.build(
              contract: contract,
              user_attributes: { name: "Alice" }
            )

            result = validate.(ctx, from: :user_attributes)

            assert result.ok?
            assert contract.validated_with == { name: "Alice" }
          end
        end

        context "Substitute" do
          seq_class = Class.new do
            include Hubbado::Sequence

            def self.name; "Seqs::WithValidate"; end
          end
          seq_class.dependency :validate, Hubbado::Sequence::Macros::Contract::Validate

          test "default behaviour is pass-through ok" do
            seq = seq_class.new

            result = seq.validate.(Hubbado::Sequence::Ctx.new, from: :params)

            assert result.ok?
          end

          test "succeed_with takes no args; validation passes" do
            seq = seq_class.new
            seq.validate.succeed_with

            result = seq.validate.(Hubbado::Sequence::Ctx.new, from: :params)

            assert result.ok?
          end

          test "fail_with(**error) returns a failed result" do
            seq = seq_class.new
            seq.validate.fail_with(code: :validation_failed)

            result = seq.validate.(Hubbado::Sequence::Ctx.new, from: :params)

            assert result.failure?
            assert result.error[:code] == :validation_failed
          end

          test "validated? records the from: argument" do
            seq = seq_class.new
            seq.validate.(Hubbado::Sequence::Ctx.new, from: %i[params user])

            assert seq.validate.validated?
            assert seq.validate.validated?(from: %i[params user])
            refute seq.validate.validated?(from: :other)
          end
        end
      end
    end
  end
end
