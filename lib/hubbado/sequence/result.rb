module Hubbado
  module Sequence
    class Result
      FRAMEWORK_I18N_SCOPE = "sequence.errors".freeze

      attr_reader :ctx
      attr_reader :code
      attr_reader :data
      attr_reader :step
      attr_reader :successful_steps
      attr_reader :i18n_scope
      attr_reader :i18n_key
      attr_reader :i18n_args

      def self.success(ctx, successful_steps: [], i18n_scope: nil)
        new(
          :success,
          ctx: ctx,
          successful_steps: successful_steps,
          i18n_scope: i18n_scope
        )
      end

      def self.failure(ctx, code:, data: nil, step: nil,
        i18n_scope: nil, i18n_key: nil, i18n_args: nil, successful_steps: [])
        raise ArgumentError, "Result.failure requires code:" unless code

        new(
          :failure,
          ctx: ctx,
          code: code,
          data: data,
          step: step,
          successful_steps: successful_steps,
          i18n_scope: i18n_scope,
          i18n_key: i18n_key,
          i18n_args: i18n_args
        )
      end

      def initialize(status, ctx:, successful_steps:, i18n_scope:,
        code: nil, data: nil, step: nil,
        i18n_key: nil, i18n_args: nil)
        @status = status
        @ctx = ctx
        @code = code
        @data = data
        @step = step
        @successful_steps = successful_steps
        @i18n_scope = i18n_scope
        @i18n_key = i18n_key
        @i18n_args = i18n_args
      end

      def success?
        @status == :success
      end

      def failure?
        @status == :failure
      end

      def with_successful_steps(successful_steps)
        copy(successful_steps: successful_steps)
      end

      def with_i18n_scope(scope)
        return self unless @i18n_scope.nil?

        copy(i18n_scope: scope)
      end

      def with_step(step)
        copy(step: step)
      end

      def message
        return nil if success?

        translate_with_chain || humanize_code
      end

      private

      def copy(**overrides)
        self.class.new(
          @status,
          ctx: @ctx,
          code: @code,
          data: @data,
          step: @step,
          successful_steps: @successful_steps,
          i18n_scope: @i18n_scope,
          i18n_key: @i18n_key,
          i18n_args: @i18n_args,
          **overrides
        )
      end

      def translate_with_chain
        scopes = []
        scopes << @i18n_scope if @i18n_scope
        scopes << FRAMEWORK_I18N_SCOPE
        scopes.uniq!

        key = @i18n_key || @code
        args = @i18n_args || {}

        scopes.each do |scope|
          translated = ::I18n.t("#{scope}.#{key}", default: nil, **args)
          return translated unless translated.nil?
        end

        nil
      end

      def humanize_code
        @code.to_s.tr("_", " ").capitalize
      end
    end
  end
end
