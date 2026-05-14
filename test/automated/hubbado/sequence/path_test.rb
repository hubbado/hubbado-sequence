require_relative "../../../test_init"

context "Hubbado" do
  context "Sequence" do
    context "Path" do
      ctx = Hubbado::Sequence::Ctx.build(
        params: { company: { id: 42 }, name: 'Acme' },
        user_id: 7
      )

      context "single Symbol" do
        test "resolves to ctx[key]" do
          assert Hubbado::Sequence::Path.resolve(ctx, :user_id) == 7
        end
      end

      context "Array path" do
        test "walks the nested keys" do
          assert Hubbado::Sequence::Path.resolve(ctx, %i[params name]) == 'Acme'
          assert Hubbado::Sequence::Path.resolve(ctx, %i[params company id]) == 42
        end
      end

      context "missing path with default policy (:raise)" do
        test "raises KeyError when the leaf key is absent" do
          captured = nil
          begin
            Hubbado::Sequence::Path.resolve(ctx, %i[params missing])
          rescue KeyError => e
            captured = e
          end

          refute captured.nil?
        end

        test "raises KeyError when the top-level key is absent" do
          captured = nil
          begin
            Hubbado::Sequence::Path.resolve(ctx, :nope)
          rescue KeyError => e
            captured = e
          end

          refute captured.nil?
        end
      end

      context "missing path with missing: :nil" do
        test "returns nil when the leaf key is absent" do
          assert Hubbado::Sequence::Path.resolve(ctx, %i[params missing], missing: :nil).nil?
        end

        test "returns nil when an intermediate key is absent" do
          assert Hubbado::Sequence::Path.resolve(ctx, %i[nope deeper], missing: :nil).nil?
        end

        test "still resolves a present path normally" do
          assert Hubbado::Sequence::Path.resolve(ctx, %i[params name], missing: :nil) == 'Acme'
        end
      end

      context "empty array path" do
        test "raises ArgumentError" do
          captured = nil
          begin
            Hubbado::Sequence::Path.resolve(ctx, [])
          rescue ArgumentError => e
            captured = e
          end

          refute captured.nil?
          assert captured.message.include?('empty')
        end
      end

      context "unknown missing policy" do
        test "raises ArgumentError" do
          captured = nil
          begin
            Hubbado::Sequence::Path.resolve(ctx, :user_id, missing: :wat)
          rescue ArgumentError => e
            captured = e
          end

          refute captured.nil?
        end
      end
    end
  end
end
