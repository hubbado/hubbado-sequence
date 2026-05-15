module Hubbado
  module Sequence
    # Railway-style step runner that backs the Sequencer mixin's
    # `pipeline(ctx)` helper. Not part of the public API — sequencers reach
    # it through the helper.
    class Pipeline
      def initialize(ctx, dispatcher:)
        @ctx = ctx
        @successful_steps = []
        @failed_result = nil
        @dispatcher = dispatcher
      end

      # `step(:name)` dispatches to `dispatcher.send(name, ctx)`. The method
      # is treated as successful unless it explicitly returns a failed
      # `Result`; any other return value (nil, false, a model, `Result.success`)
      # continues the pipeline with the same ctx. Only `Result.failure(...)` /
      # `failure(ctx, code: ...)` short-circuits.
      def step(name)
        return self if @failed_result

        record(name, invoke_step(name))
        self
      end

      # `invoke(:name, *args, **kwargs)` calls a declared dependency on the
      # dispatcher: gets it via `dispatcher.send(name)` (the reader), then
      # invokes it with `(ctx, *args, **kwargs)`. Same trail recording,
      # failure short-circuiting, and lenient return convention as `step`.
      #
      # Use this for any declared dependency — macros
      # (`Macros::Model::Find`) and nested sequencers (`Seqs::Present`)
      # alike. Use `step` for local instance methods like
      # `def deserialize_contract(ctx)`.
      def invoke(name, *args, **kwargs)
        return self if @failed_result

        record(name, invoke_dependency(name, args, kwargs))
        self
      end

      def transaction
        return self if @failed_result

        if defined?(::ActiveRecord::Base)
          ::ActiveRecord::Base.transaction do
            yield(self)
            raise ::ActiveRecord::Rollback if @failed_result
          end
        else
          yield(self)
        end

        self
      end

      def result
        if @failed_result
          @failed_result
        else
          Result.success(@ctx, successful_steps: @successful_steps.dup)
        end
      end

      private

      def invoke_step(name)
        unless @dispatcher.respond_to?(name, true)
          raise NoMethodError,
            "Pipeline step :#{name} expects #{@dispatcher.class.name} to define ##{name}, but it does not"
        end

        @dispatcher.send(name, @ctx)
      end

      def invoke_dependency(name, args, kwargs)
        unless @dispatcher.respond_to?(name, true)
          raise NoMethodError,
            "Pipeline#invoke :#{name} expects #{@dispatcher.class.name} to declare a `dependency :#{name}, ...`"
        end

        @dispatcher.send(name).(@ctx, *args, **kwargs)
      end

      def record(name, return_value)
        if return_value.is_a?(Result) && return_value.failure?
          @failed_result = tag_failure(return_value, name)
        else
          @successful_steps << name
        end
      end

      def tag_failure(result, step_name)
        tagged_error = result.error.merge(step: step_name)
        Result.failure(result.ctx, error: tagged_error, successful_steps: @successful_steps.dup, i18n_scope: result.i18n_scope)
      end
    end
  end
end
