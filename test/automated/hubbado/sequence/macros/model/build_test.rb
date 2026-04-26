require_relative "../../../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "Macros" do
      context "Model::Build" do
        model = Hubbado::Sequence::Controls::Model.example

        context "with no initial attributes" do
          build_macro = Hubbado::Sequence::Macros::Model::Build.new

          test "instantiates a new record and writes it to ctx" do
            ctx = Hubbado::Sequence::Ctx.new
            result = build_macro.(ctx, model, as: :user)

            assert result.ok?
            assert ctx[:user].is_a?(model)
            assert ctx[:user].init_attributes == {}
          end
        end

        context "with attributes:" do
          build_macro = Hubbado::Sequence::Macros::Model::Build.new

          test "passes attributes to the constructor" do
            ctx = Hubbado::Sequence::Ctx.new
            attrs = { name: "Alice", email: "alice@example.com" }

            result = build_macro.(ctx, model, as: :user, attributes: attrs)

            assert result.ok?
            assert ctx[:user].init_attributes == attrs
          end
        end

        context ".build" do
          test "constructs an instance" do
            build_macro = Hubbado::Sequence::Macros::Model::Build.build

            assert build_macro.is_a?(Hubbado::Sequence::Macros::Model::Build)
          end
        end

        context "Substitute" do
          seq_class = Class.new do
            include Hubbado::Sequence

            def self.name; "Seqs::WithBuild"; end
          end
          seq_class.dependency :build_record, Hubbado::Sequence::Macros::Model::Build

          test "default behaviour is pass-through ok with no ctx mutation" do
            seq = seq_class.new

            ctx = Hubbado::Sequence::Ctx.new
            result = seq.build_record.(ctx, model, as: :user)

            assert result.ok?
            refute ctx.key?(:user)
          end

          test "succeed_with(value) writes the value to ctx" do
            seq = seq_class.new
            seq.build_record.succeed_with(:fake_record)

            ctx = Hubbado::Sequence::Ctx.new
            result = seq.build_record.(ctx, model, as: :user)

            assert result.ok?
            assert ctx[:user] == :fake_record
          end

          test "fail_with(**error) returns a failed result" do
            seq = seq_class.new
            seq.build_record.fail_with(code: :invalid_state)

            result = seq.build_record.(Hubbado::Sequence::Ctx.new, model, as: :user)

            assert result.failure?
            assert result.error[:code] == :invalid_state
          end

          test "built? records calls and matches partial kwargs" do
            seq = seq_class.new
            seq.build_record.(Hubbado::Sequence::Ctx.new, model, as: :user, attributes: { name: "Alice" })

            assert seq.build_record.built?
            assert seq.build_record.built?(as: :user)
            assert seq.build_record.built?(attributes: { name: "Alice" })
            refute seq.build_record.built?(as: :other)
          end

          test "raises ArgumentError when the configured model does not respond to :new" do
            seq = seq_class.new
            opaque = Object.new

            captured = nil
            begin
              seq.build_record.(Hubbado::Sequence::Ctx.new, opaque, as: :user)
            rescue ArgumentError => e
              captured = e
            end

            refute captured.nil?
            assert captured.message.include?("does not respond to :new")
          end
        end
      end
    end
  end
end
