module Hubbado
  module Sequence
    # Invokes a sequencer and dispatches its Result to outcome blocks. Forgetting
    # to handle a serious failure raises rather than silently swallowing it.
    # Usable as a configurable dependency wherever a sequencer Result needs
    # branch-style handling.
    class Runner
      configure :run_sequence

      def call(sequencer_class, **kwargs, &block)
        result = sequencer_class.(**kwargs)

        dispatch = Dispatch.new(sequencer_class, result)
        block.call(dispatch) if block_given?

        dispatch.enforce_safety_nets!

        dispatch.returned
      end

      class Dispatch
        include Hubbado::Log::Dependency

        attr_reader :returned, :result, :sequencer_class

        def initialize(sequencer_class, result)
          @sequencer_class = sequencer_class
          @result = result
          @handled = false
        end

        def success
          return unless @result.ok?
          execute { yield(@result.ctx) }
          logger.info("Sequencer #{@sequencer_class.name} succeeded: #{trail_summary}")
        end

        def policy_failed
          return unless code == :forbidden
          execute { yield(@result.ctx) }
          logger.info("Sequencer #{@sequencer_class.name} policy failed at #{step_label} (#{code}): #{trail_summary}")
        end

        def not_found
          return unless code == :not_found
          execute { yield(@result.ctx) }
          logger.info("Sequencer #{@sequencer_class.name} not found at #{step_label}: #{trail_summary}")
        end

        def validation_failed
          return unless code == :validation_failed
          execute { yield(@result.ctx) }
          logger.info("Sequencer #{@sequencer_class.name} validation failed at #{step_label}: #{trail_summary}")
        end

        # otherwise deliberately does not catch policy denials or not_found —
        # those have their own required handlers.
        def otherwise
          return if @result.ok?
          return if code == :forbidden
          return if code == :not_found
          return if @handled

          execute { yield(@result.ctx) }
          logger.info("Sequencer #{@sequencer_class.name} failed at #{step_label} (#{code}): #{trail_summary}")
        end

        def code
          @result.error&.[](:code)
        end

        def handled?
          @result.ok? || @handled
        end

        def enforce_safety_nets!
          return if handled?

          log_unhandled

          case code
          when :forbidden
            raise Errors::Unauthorized.new(
              "#{@sequencer_class.name} denied: #{@result.message}",
              @result
            )
          when :not_found
            raise Errors::NotFound, "#{@sequencer_class.name} reported not_found"
          else
            raise Errors::Failed, "#{@sequencer_class.name} failed (#{code}): #{@result.message}"
          end
        end

        def log_unhandled
          logger.error("Sequencer #{@sequencer_class.name} failed unhandled at #{step_label} (#{code}): #{trail_summary}")
        end

        private

        def execute
          @handled = true
          @returned = yield
        end

        def trail_summary
          @result.trail.empty? ? "(no steps)" : @result.trail.map(&:to_s).join(" → ")
        end

        def step_label
          step = @result.error && @result.error[:step]
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
            error: { code: code, **error_attrs }
          }
          self
        end

        def build_result
          outcome = @configured_outcome || { kind: :success, ctx_writes: {} }
          ctx = Hubbado::Sequence::Ctx.new

          if outcome[:kind] == :success
            outcome[:ctx_writes].each { |key, value| ctx[key] = value }
            Hubbado::Sequence::Result.ok(ctx)
          else
            Hubbado::Sequence::Result.fail(ctx, error: outcome[:error])
          end
        end
      end
    end
  end
end
