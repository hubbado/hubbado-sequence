require_relative "../../../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "Macros" do
      context "Contract::Build" do
        contract_class = Hubbado::Sequence::Controls::Contract.klass

        build_contract = Hubbado::Sequence::Macros::Contract::Build.new

        context "wraps the model in a contract" do
          test "writes the contract to ctx[:contract]" do
            ctx = Hubbado::Sequence::Ctx.build(user: :a_user)
            result = build_contract.(ctx, contract_class, :user)

            assert result.ok?
            assert ctx[:contract].is_a?(contract_class)
            assert ctx[:contract].model == :a_user
          end
        end

        context ".build" do
          test "constructs an instance" do
            instance = Hubbado::Sequence::Macros::Contract::Build.build

            assert instance.is_a?(Hubbado::Sequence::Macros::Contract::Build)
          end
        end

        context "Substitute" do
          seq_class = Class.new do
            include Hubbado::Sequence

            def self.name; "Seqs::WithBuildContract"; end
          end
          seq_class.dependency :build_contract, Hubbado::Sequence::Macros::Contract::Build

          test "default behaviour is pass-through ok with no ctx mutation" do
            seq = seq_class.new

            ctx = Hubbado::Sequence::Ctx.new
            result = seq.build_contract.(ctx, contract_class, :user)

            assert result.ok?
            refute ctx.key?(:contract)
          end

          test "succeed_with(contract) writes the contract to ctx" do
            seq = seq_class.new
            contract = contract_class.new(:something)
            seq.build_contract.succeed_with(contract)

            ctx = Hubbado::Sequence::Ctx.new
            result = seq.build_contract.(ctx, contract_class, :user)

            assert result.ok?
            assert ctx[:contract].equal?(contract)
          end

          test "fail_with(**error) returns a failed result" do
            seq = seq_class.new
            seq.build_contract.fail_with(code: :something_wrong)

            result = seq.build_contract.(Hubbado::Sequence::Ctx.new, contract_class, :user)

            assert result.failure?
            assert result.error[:code] == :something_wrong
          end

          test "built? records calls" do
            seq = seq_class.new
            seq.build_contract.(Hubbado::Sequence::Ctx.new, contract_class, :user)

            assert seq.build_contract.built?
          end
        end
      end
    end
  end
end
