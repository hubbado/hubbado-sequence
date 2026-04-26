module Hubbado
  module Sequence
    def self.included(cls)
      cls.send(:include, ::Dependency)
      cls.send(:include, ::Configure)
      cls.extend(ClassMethods)

      install_default_substitute(cls)
    end

    # Each sequencer gets a default `Substitute` module so it can be used as a
    # dependency without bespoke test scaffolding. The user can reopen the
    # module in their class body to add per-sequencer assertions; the defaults
    # below are always available.
    def self.install_default_substitute(cls)
      return if cls.const_defined?(:Substitute, false)

      cls.const_set(:Substitute, build_default_substitute_module)
    end

    def self.build_default_substitute_module
      Module.new do
        include ::RecordInvocation

        def succeed_with(**ctx_writes)
          @configured_writes = ctx_writes
          self
        end

        def fail_with(**error_attrs)
          @configured_error = error_attrs
          self
        end

        record def call(ctx)
          return ::Hubbado::Sequence::Result.fail(ctx, error: @configured_error) if @configured_error

          if @configured_writes
            @configured_writes.each { |k, v| ctx[k] = v }
          end
          ::Hubbado::Sequence::Result.ok(ctx)
        end

        def called?(**kwargs)
          invoked?(:call, **kwargs)
        end
      end
    end

    module ClassMethods
      # Bridge between the kwargs boundary (controllers and other top-level
      # callers) and the ctx-passing convention used inside the framework.
      # A caller can supply either an existing Ctx (the nested-sequencer case)
      # or keyword arguments that become the initial ctx (the outermost case).
      def call(ctx = nil, **kwargs)
        if ctx.nil?
          ctx = Ctx.build(kwargs)
        elsif !kwargs.empty?
          raise ArgumentError, "#{name}.() takes either a Ctx or keyword arguments, not both"
        elsif !ctx.is_a?(Ctx)
          ctx = Ctx.build(ctx)
        end

        build.call(ctx)
      end

      # Default factory: a sequencer with no configurable dependencies needs
      # nothing more than `new`. Sequencers that have dependencies override
      # `self.build` to run the corresponding `Macro.configure(instance, …)`
      # calls.
      def build
        new
      end

      def i18n_scope
        @i18n_scope ||= ::Casing::Underscore::String.(name).gsub('/', '.')
      end
    end

    def i18n_scope
      self.class.i18n_scope
    end

    def failure(ctx, **error_attrs)
      Result.fail(ctx, error: error_attrs, i18n_scope: i18n_scope)
    end

    # Builds a Pipeline that auto-dispatches blockless `step(:foo)` calls to
    # `self.foo(ctx)`. Use this inside a sequencer's `call` body in place of
    # `Pipeline.(ctx)` whenever steps are local methods.
    #
    # Block form (`pipeline(ctx) { |p| ... }`) yields the pipeline, runs the
    # block, and returns the final Result — no trailing `.result` needed. The
    # non-block form returns the Pipeline so chained `.step(...)...result`
    # calls still work.
    def pipeline(ctx, &block)
      pipe = Pipeline.new(ctx, dispatcher: self)

      if block
        block.call(pipe)
        pipe.result
      else
        pipe
      end
    end
  end
end
