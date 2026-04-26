require_relative "../../../test_init"

context "Hubbado" do
  context "Sequencer" do
    context "Ctx" do
      test "is a Hash subclass" do
        assert Hubbado::Sequence::Ctx.new.is_a?(Hash)
      end

      test "stores and retrieves values like a hash" do
        ctx = Hubbado::Sequence::Ctx.new
        ctx[:user] = :a_user

        assert ctx[:user] == :a_user
      end

      context "[] (strict access)" do
        test "raises KeyError on missing keys" do
          ctx = Hubbado::Sequence::Ctx.new

          assert_raises KeyError do
            ctx[:missing]
          end
        end

        test "does not raise for keys with nil values" do
          ctx = Hubbado::Sequence::Ctx.new
          ctx[:explicit_nil] = nil

          assert ctx[:explicit_nil].nil?
        end
      end

      context "fetch" do
        test "preserves Ruby's standard fetch behaviour" do
          ctx = Hubbado::Sequence::Ctx.new
          ctx[:user] = :a_user

          assert ctx.fetch(:user) == :a_user
          assert ctx.fetch(:locale, :en) == :en
          assert ctx.fetch(:nothing) { :computed } == :computed
        end
      end

      context "construction" do
        test "accepts an initial hash via .build" do
          ctx = Hubbado::Sequence::Ctx.build(user: :a_user, params: { id: 1 })

          assert ctx[:user] == :a_user
          assert ctx[:params] == { id: 1 }
        end
      end
    end
  end
end
