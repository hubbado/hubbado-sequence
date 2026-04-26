require_relative "../../../test_init"

# Regression test: when the framework is loaded into an app that defines
# Hubbado::I18n, Hubbado::Casing, etc., bare references like `I18n.t` resolve
# inside the Hubbado:: namespace first and shadow the top-level gems. Each
# top-level gem reference inside the framework must be qualified with `::`.
#
# This test installs empty modules at those names and exercises the code paths
# that hit each constant. If a `::` is dropped, the test blows up with a
# NoMethodError or similar — exactly what the production app saw.

context "Hubbado" do
  context "Sequencer" do
    context "Constant shadowing" do
      # Install shadowing modules. We define them once at file-load time and
      # leave them in place; the rest of the suite is unaffected because every
      # framework-side reference is `::`-prefixed.
      Hubbado.const_set(:I18n,            Module.new) unless Hubbado.const_defined?(:I18n)
      Hubbado.const_set(:Casing,          Module.new) unless Hubbado.const_defined?(:Casing)
      Hubbado.const_set(:RecordInvocation, Module.new) unless Hubbado.const_defined?(:RecordInvocation)

      context "Result#message under shadowing" do
        test "translates failures via the top-level ::I18n" do
          result = Hubbado::Sequence::Result.fail({}, error: { code: :forbidden })

          # Would raise `undefined method 't' for module Hubbado::I18n` if the
          # `::` prefix was missing.
          assert result.message == ::I18n.t("sequence.errors.forbidden")
        end
      end

      context "Sequencer#i18n_scope under shadowing" do
        test "derives the scope via the top-level ::Casing" do
          klass = Class.new do
            include Hubbado::Sequence
            def self.name; "Seqs::CheckShadowing"; end
          end

          # Would raise NoMethodError on Hubbado::Casing::Underscore if the
          # `::` prefix was missing.
          assert klass.i18n_scope == "seqs.check_shadowing"
        end
      end

      context "macro Substitute under shadowing" do
        test "defaults to pass-through ok using top-level ::RecordInvocation" do
          model = Hubbado::Sequence::Controls::Model.example

          seq_class = Class.new do
            include Hubbado::Sequence
            def self.name; "Seqs::CheckMacroShadowing"; end
          end
          seq_class.dependency :find, Hubbado::Sequence::Macros::Model::Find
          seq = seq_class.new

          ctx = Hubbado::Sequence::Ctx.new
          result = seq.find.(ctx, model, as: :user)

          assert result.ok?
        end
      end
    end
  end
end
