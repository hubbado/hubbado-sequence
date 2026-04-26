module Hubbado
  module Sequence
    class Pipeline
      # `Pipeline.(ctx) { |p| ... }` is the block form: yields the pipeline,
      # runs the block (so steps can be added in statement form), and returns
      # the final Result. The non-block form returns the Pipeline so chained
      # `.step(...)...result` calls still work.
      def self.call(ctx = nil, **kwargs, &block)
        if ctx.nil?
          ctx = Ctx.build(kwargs)
        elsif !kwargs.empty?
          raise ArgumentError, "Pipeline.() takes either a Ctx or keyword arguments, not both"
        elsif !ctx.is_a?(Ctx)
          ctx = Ctx.build(ctx)
        end

        pipe = new(ctx)

        if block
          block.call(pipe)
          pipe.result
        else
          pipe
        end
      end

      def initialize(ctx, dispatcher: nil)
        @ctx = ctx
        @trail = []
        @failed_result = nil
        @dispatcher = dispatcher
      end

      # `step(:name) { |ctx| ... }` runs the block. `step(:name)` with no
      # block dispatches to `dispatcher.send(name, ctx)` on the sequencer
      # that built this pipeline (via the mixin's `pipeline(ctx)` helper).
      # Block beats dispatch when both are available; raises if neither.
      #
      # Lenient return convention: a step is treated as successful unless it
      # explicitly returns a failed `Result`. Any other return value (nil,
      # false, a model, a hash, `Result.ok(...)`) is taken as success and the
      # pipeline continues with the same `@ctx`. Only `Result.fail(...)` /
      # `failure(ctx, code: ...)` short-circuits the pipeline.
      def step(name, &block)
        return self if @failed_result

        return_value = invoke_step(name, block)

        if return_value.is_a?(Result) && return_value.failure?
          @failed_result = tag_failure(return_value, name)
        else
          @trail << name
        end

        self
      end

      # `invoke(:name, *args, **kwargs)` calls a declared dependency on the
      # sequencer: gets the dependency via `dispatcher.send(name)` (the
      # reader), then invokes it with `(ctx, *args, **kwargs)`. Same trail
      # recording, failure short-circuiting, and lenient return convention as
      # `step`.
      #
      # Use this for any declared dependency — macros (`Macros::Model::Find`)
      # and nested sequencers (`Seqs::Present`) alike. Use `step` for local
      # instance methods like `def deserialize_contract(ctx)`.
      def invoke(name, *args, **kwargs)
        return self if @failed_result

        return_value = invoke_dependency(name, args, kwargs)

        if return_value.is_a?(Result) && return_value.failure?
          @failed_result = tag_failure(return_value, name)
        else
          @trail << name
        end

        self
      end

      def transaction(&block)
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
          Result.ok(@ctx, trail: @trail.dup)
        end
      end

      private

      def invoke_step(name, block)
        if block
          block.call(@ctx)
        elsif @dispatcher
          unless @dispatcher.respond_to?(name, true)
            raise NoMethodError,
              "Pipeline step :#{name} expects #{@dispatcher.class.name} to define ##{name}, but it does not"
          end
          @dispatcher.send(name, @ctx)
        else
          raise ArgumentError,
            "Pipeline step :#{name} needs either a block or a dispatcher (use the sequencer's `pipeline(ctx)` helper to enable auto-dispatch)"
        end
      end

      def invoke_dependency(name, args, kwargs)
        unless @dispatcher
          raise ArgumentError,
            "Pipeline#invoke :#{name} requires a dispatcher (use the sequencer's `pipeline(ctx)` helper)"
        end

        unless @dispatcher.respond_to?(name, true)
          raise NoMethodError,
            "Pipeline#invoke :#{name} expects #{@dispatcher.class.name} to declare a `dependency :#{name}, ...`"
        end

        @dispatcher.send(name).(@ctx, *args, **kwargs)
      end

      def tag_failure(result, step_name)
        tagged_error = result.error.merge(step: step_name)
        Result.fail(result.ctx, error: tagged_error, trail: @trail.dup, i18n_scope: result.i18n_scope)
      end
    end
  end
end
