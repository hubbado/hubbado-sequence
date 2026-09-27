module Hubbado
  module Sequence
    module Sequencer
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
            return ::Hubbado::Sequence::Result.failure(ctx, **@configured_error) if @configured_error

            if @configured_writes
              @configured_writes.each { |k, v| ctx[k] = v }
            end
            ::Hubbado::Sequence::Result.success(ctx)
          end

          def called?(**kwargs)
            invoked?(:call, **kwargs)
          end
        end
      end

      module ClassMethods
        def call(ctx = nil, **)
          build.(ctx, **)
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

      # Bridge between the kwargs boundary (controllers, specs and other
      # callers) and the ctx-passing convention used inside the framework.
      # A caller can supply either an existing Ctx (the nested-sequencer case)
      # or keyword arguments that become the initial ctx (the outermost case).
      # Either way the sequencer's `sequence(ctx)` sees a Ctx from its first
      # line, so its pipeline block and its steps share one object. The
      # Result is tagged here, at the one boundary every caller crosses, so a
      # hand-built Result gets the sequencer's i18n scope too (innermost wins).
      def call(ctx = nil, **kwargs)
        if ctx.nil?
          ctx = Ctx.build(kwargs)
        elsif !kwargs.empty?
          raise ArgumentError,
            "#{self.class.name}#call takes either a Ctx or keyword arguments, not both"
        elsif !ctx.is_a?(Ctx)
          ctx = Ctx.build(ctx)
        end

        sequence(ctx).with_i18n_scope(i18n_scope)
      end

      def i18n_scope
        self.class.i18n_scope
      end

      def failure(ctx, **error_attrs)
        error_attrs[:i18n_scope] ||= i18n_scope
        Result.failure(ctx, **error_attrs)
      end

      # Builds a Pipeline that auto-dispatches blockless `step(:foo)` calls to
      # `self.foo(ctx)`. Use this inside a sequencer's `sequence` body in place
      # of `Pipeline.(ctx)` whenever steps are local methods.
      #
      # Block form (`pipeline(ctx) { |p| ... }`) yields the pipeline, runs the
      # block, and returns the final Result — no trailing `.result` needed. The
      # non-block form returns the Pipeline so chained `.step(...)...result`
      # calls still work.
      #
      # Anything but a Ctx means the sequencer defined `call` and so bypassed
      # the Ctx that `Sequencer#call` builds.
      def pipeline(ctx, &block)
        unless ctx.is_a?(Ctx)
          raise ArgumentError,
            "#{self.class.name}#pipeline expects a Hubbado::Sequence::Ctx; " \
            "define the steps in sequence(ctx), not call(ctx)"
        end

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
end
