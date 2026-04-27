module Hubbado
  module Sequence
    # Mixed into controllers (or other top-level boundaries that cannot take
    # injected dependencies because their lifecycle is owned by the framework).
    # Wraps Runner so the calling site reads `run_sequence SomeSeq do |r| ... end`
    # while a single `sequencer_arguments` override handles per-host kwargs
    # injection (current_user, params, etc.).
    module RunSequence
      def run_sequence(sequencer_class, **kwargs, &block)
        sequence_runner.(sequencer_class, **sequencer_arguments(kwargs), &block)
      end

      # Override in the host (controller, job) to inject defaults like
      # current_user without forcing every call site to pass them.
      def sequencer_arguments(kwargs)
        kwargs
      end

      private

      def sequence_runner
        @sequence_runner ||= Runner.new
      end
    end
  end
end
