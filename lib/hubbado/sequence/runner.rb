module Hubbado
  module Sequence
    # Invokes a sequencer and dispatches its Result to outcome blocks. Forgetting
    # to handle a serious failure raises rather than silently swallowing it.
    # Usable as a configurable dependency wherever a sequencer Result needs
    # branch-style handling.
    class Runner
      configure :run_sequence

      def self.build
        new
      end

      def call(sequencer_class, **kwargs, &block)
        result = sequencer_class.(**kwargs)

        dispatch = Dispatch.new(sequencer_class, result)
        block.call(dispatch) if block_given?

        dispatch.enforce_safety_nets!

        dispatch.returned
      end

      class Dispatch
        include Hubbado::Log::Dependency

        attr_reader :returned, :sequencer_class

        def initialize(sequencer_class, result)
          @sequencer_class = sequencer_class
          @result = result
          @handled = false
        end

        # Read-throughs to the wrapped Result. Outcome blocks read these on
        # the Dispatch object (the block argument) without hopping through
        # an inner Result reference.
        def code             = @result.code
        def data             = @result.data
        def step             = @result.step
        def message          = @result.message
        def successful_steps = @result.successful_steps
        def ctx              = @result.ctx

        def success
          return unless @result.success?
          execute { yield(@result.ctx) }
          logger.info("Sequencer #{@sequencer_class.name} succeeded: #{steps_summary}")
        end

        def policy_failed
          return unless code == :forbidden
          execute { yield(@result.ctx) }
          logger.info("Sequencer #{@sequencer_class.name} policy failed at #{step_label} (#{code}): #{steps_summary}")
        end

        def not_found
          return unless code == :not_found
          execute { yield(@result.ctx) }
          logger.info("Sequencer #{@sequencer_class.name} not found at #{step_label}: #{steps_summary}")
        end

        def validation_failed
          return unless code == :validation_failed
          execute { yield(@result.ctx) }
          logger.info("Sequencer #{@sequencer_class.name} validation failed at #{step_label}: #{steps_summary}")
        end

        # otherwise deliberately does not catch policy denials or not_found —
        # those have their own required handlers.
        def otherwise
          return if @result.success?
          return if code == :forbidden
          return if code == :not_found
          return if @handled

          execute { yield(@result.ctx) }
          logger.info("Sequencer #{@sequencer_class.name} failed at #{step_label} (#{code}): #{steps_summary}")
        end

        def handled?
          @result.success? || @handled
        end

        # Raise the standard policy-denial exception. Available inside an
        # outcome block (e.g. for callers that handle some policy reasons
        # inline and want the framework's standard escalation for the rest)
        # and used internally by enforce_safety_nets! when no handler ran.
        def raise_policy_failed
          raise Errors::Unauthorized.new(
            "#{@sequencer_class.name} denied: #{@result.message}",
            @result
          )
        end

        def raise_not_found
          raise Errors::NotFound, "#{@sequencer_class.name} reported not_found"
        end

        def raise_failed
          raise Errors::Failed, "#{@sequencer_class.name} failed (#{code}): #{@result.message}"
        end

        def enforce_safety_nets!
          return if handled?

          log_unhandled

          case code
          when :forbidden then raise_policy_failed
          when :not_found then raise_not_found
          else raise_failed
          end
        end

        def log_unhandled
          logger.error("Sequencer #{@sequencer_class.name} failed unhandled at #{step_label} (#{code}): #{steps_summary}")
        end

        private

        def execute
          @handled = true
          @returned = yield
        end

        def steps_summary
          successful_steps.empty? ? "(no steps)" : successful_steps.map(&:to_s).join(" → ")
        end

        def step_label
          step ? step.inspect : "(unknown step)"
        end
      end

      module Substitute
        include RecordInvocation

        def succeed_with(**ctx_writes)
          @configured_outcome = { kind: :success, ctx_writes: ctx_writes }
          self
        end

        def policy_failure(**error_attrs)
          configure_failure(:forbidden, error_attrs)
        end

        def not_found(**error_attrs)
          configure_failure(:not_found, error_attrs)
        end

        def validation_failure(**error_attrs)
          configure_failure(:validation_failed, error_attrs)
        end

        def other_error(code:, **error_attrs)
          configure_failure(code, error_attrs)
        end

        def ran_with?(sequencer_class, **expected_kwargs)
          records.any? do |invocation|
            next false unless invocation.method_name == :call
            next false unless invocation.arguments[:sequencer_class] == sequencer_class

            captured = invocation.arguments[:kwargs] || {}
            expected_kwargs.all? { |key, value| captured[key] == value }
          end
        end

        record def call(sequencer_class, **kwargs, &block)
          dispatch = Dispatch.new(sequencer_class, build_result)
          block.call(dispatch) if block_given?
          dispatch.enforce_safety_nets!
          dispatch.returned
        end

        private

        def configure_failure(code, error_attrs)
          @configured_outcome = {
            kind: :failure,
            code: code,
            error_attrs: error_attrs
          }
          self
        end

        def build_result
          outcome = @configured_outcome || { kind: :success, ctx_writes: {} }
          ctx = Hubbado::Sequence::Ctx.new

          if outcome[:kind] == :success
            outcome[:ctx_writes].each { |key, value| ctx[key] = value }
            Hubbado::Sequence::Result.success(ctx)
          else
            Hubbado::Sequence::Result.failure(ctx, code: outcome[:code], **outcome[:error_attrs])
          end
        end
      end
    end
  end
end
