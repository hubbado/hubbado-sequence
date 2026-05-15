module Hubbado
  module Sequence
    class Result
      FRAMEWORK_I18N_SCOPE = "sequence.errors".freeze

      attr_reader :ctx
      attr_reader :error
      attr_reader :successful_steps
      attr_reader :i18n_scope

      def self.success(ctx, successful_steps: [], i18n_scope: nil)
        new(:success, ctx, error: nil, successful_steps: successful_steps, i18n_scope: i18n_scope)
      end

      def self.failure(ctx, error:, successful_steps: [], i18n_scope: nil)
        unless error.is_a?(Hash) && error[:code]
          raise ArgumentError, "Result.failure requires error: { code: ... }"
        end

        new(:failure, ctx, error: error, successful_steps: successful_steps, i18n_scope: i18n_scope)
      end

      def initialize(status, ctx, error:, successful_steps:, i18n_scope:)
        @status = status
        @ctx = ctx
        @error = error
        @successful_steps = successful_steps
        @i18n_scope = i18n_scope
      end

      def success?
        @status == :success
      end

      def failure?
        @status == :failure
      end

      def with_successful_steps(successful_steps)
        self.class.new(@status, @ctx, error: @error, successful_steps: successful_steps, i18n_scope: @i18n_scope)
      end

      def with_i18n_scope(scope)
        return self unless @i18n_scope.nil?

        self.class.new(@status, @ctx, error: @error, successful_steps: @successful_steps, i18n_scope: scope)
      end

      def message
        return nil if success?

        translation = translate_with_chain
        return translation if translation

        @error[:message] || humanize_code
      end

      private

      def translate_with_chain
        scopes = []
        scopes << @error[:i18n_scope] if @error[:i18n_scope]
        scopes << @i18n_scope if @i18n_scope
        scopes << FRAMEWORK_I18N_SCOPE
        scopes.uniq!

        key = @error[:i18n_key] || @error[:code]
        args = @error[:i18n_args] || {}

        scopes.each do |scope|
          translated = ::I18n.t("#{scope}.#{key}", default: nil, **args)
          return translated unless translated.nil?
        end

        nil
      end

      def humanize_code
        @error[:code].to_s.tr("_", " ").capitalize
      end
    end
  end
end
