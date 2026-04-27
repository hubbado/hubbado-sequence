require_relative "../../../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "Macros" do
      context "Model::Find" do
        model = Hubbado::Sequence::Controls::Model.example

        context "successful find" do
          model.reset
          model.put(1, :a_user)

          find = Hubbado::Sequence::Macros::Model::Find.new

          test "writes the found record to ctx at the given attr name" do
            ctx = Hubbado::Sequence::Ctx.build(params: { id: 1 })
            result = find.(ctx, model, as: :user)

            assert result.ok?
            assert ctx[:user] == :a_user
          end

          test "the result wraps the same ctx" do
            ctx = Hubbado::Sequence::Ctx.build(params: { id: 1 })
            result = find.(ctx, model, as: :user)

            assert result.ctx.equal?(ctx)
          end
        end

        context "not found" do
          model.reset

          find = Hubbado::Sequence::Macros::Model::Find.new

          test "returns a failed result with code :not_found" do
            ctx = Hubbado::Sequence::Ctx.build(params: { id: 999 })
            result = find.(ctx, model, as: :user)

            assert result.failure?
            assert result.error[:code] == :not_found
          end

          test "ctx is unchanged on not found" do
            ctx = Hubbado::Sequence::Ctx.build(params: { id: 999 })
            find.(ctx, model, as: :user)

            refute ctx.key?(:user)
          end
        end

        context "id_key:" do
          model.reset
          model.put(42, :a_user)

          find = Hubbado::Sequence::Macros::Model::Find.new

          test "reads the id from a different params key" do
            ctx = Hubbado::Sequence::Ctx.build(params: { user_id: 42 })
            result = find.(ctx, model, as: :user, id_key: :user_id)

            assert result.ok?
            assert ctx[:user] == :a_user
          end
        end

        context "from:" do
          model.reset
          model.put(7, :a_user)

          find = Hubbado::Sequence::Macros::Model::Find.new

          test "reads from a nested ctx path" do
            ctx = Hubbado::Sequence::Ctx.build(request: { payload: { id: 7 } })
            result = find.(ctx, model, as: :user, from: %i[request payload])

            assert result.ok?
            assert ctx[:user] == :a_user
          end
        end

        context ".build" do
          test "constructs an instance" do
            find = Hubbado::Sequence::Macros::Model::Find.build

            assert find.is_a?(Hubbado::Sequence::Macros::Model::Find)
          end
        end

        context "Substitute (via .new on a sequencer that uses Find as a dependency)" do
          seq_class = Class.new do
            include Hubbado::Sequence::Sequencer

            def self.name; "Seqs::WithFind"; end
          end
          seq_class.dependency :find, Hubbado::Sequence::Macros::Model::Find

          test "default behaviour is pass-through ok with no ctx mutation" do
            seq = seq_class.new

            ctx = Hubbado::Sequence::Ctx.new
            result = seq.find.(ctx, model, as: :user)

            assert result.ok?
            refute ctx.key?(:user)
          end

          test "succeed_with(value) writes the value to ctx and returns ok" do
            seq = seq_class.new
            seq.find.succeed_with(:fake_user)

            ctx = Hubbado::Sequence::Ctx.new
            result = seq.find.(ctx, model, as: :user)

            assert result.ok?
            assert ctx[:user] == :fake_user
          end

          test "fail_with(**error) returns a failed result" do
            seq = seq_class.new
            seq.find.fail_with(code: :not_found)

            result = seq.find.(Hubbado::Sequence::Ctx.new, model, as: :user)

            assert result.failure?
            assert result.error[:code] == :not_found
          end

          test "fetched? records calls and matches partial kwargs" do
            seq = seq_class.new
            seq.find.(Hubbado::Sequence::Ctx.new, model, as: :user, id_key: :user_id)

            assert seq.find.fetched?
            assert seq.find.fetched?(as: :user)
            assert seq.find.fetched?(id_key: :user_id)
            refute seq.find.fetched?(as: :other)
          end

          test "raises ArgumentError when the configured model does not respond to :find_by" do
            seq = seq_class.new

            captured = nil
            begin
              seq.find.(Hubbado::Sequence::Ctx.new, Object.new, as: :user)
            rescue ArgumentError => e
              captured = e
            end

            refute captured.nil?
            assert captured.message.include?("does not respond to :find_by")
          end
        end
      end
    end
  end
end
