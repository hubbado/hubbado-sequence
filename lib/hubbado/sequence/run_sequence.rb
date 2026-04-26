module Hubbado
  module Sequence
    # Mixed into controllers (or other top-level boundaries) to invoke a
    # sequencer and dispatch its Result to outcome blocks. Forgetting to handle
    # a serious failure raises rather than silently swallowing it.
    module RunSequence
      def run_sequence(sequencer_class, **kwargs, &block)
        result = sequencer_class.(**sequencer_arguments(kwargs))

        dispatch = Dispatch.new(sequencer_class, result)
        block.call(dispatch) if block_given?

        enforce_safety_nets(dispatch)

        dispatch.returned
      end

      # Override in the host (controller, job) to inject defaults like
      # current_user without forcing every call site to pass them.
      def sequencer_arguments(kwargs)
        kwargs
      end

      private

      def enforce_safety_nets(dispatch)
        return if dispatch.handled?

        case dispatch.code
        when :forbidden
          dispatch.log_unhandled
          raise Errors::Unauthorized.new(
            "#{dispatch.sequencer_class.name} denied: #{dispatch.result.message}",
            dispatch.result
          )
        when :not_found
          dispatch.log_unhandled
          raise Errors::NotFound, "#{dispatch.sequencer_class.name} reported not_found"
        else
          dispatch.log_unhandled
          raise Errors::Failed, "#{dispatch.sequencer_class.name} failed (#{dispatch.code}): #{dispatch.result.message}"
        end
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
    end
  end
end
