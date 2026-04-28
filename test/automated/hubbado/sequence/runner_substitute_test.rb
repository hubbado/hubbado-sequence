require_relative "../../../test_init"

context "Hubbado" do
  context "Sequence" do
    context "Runner::Substitute" do
      build_substitute = ->() {
        SubstAttr::Substitute.build(Hubbado::Sequence::Runner)
      }

      seq_class = ->(name) {
        Class.new do
          include Hubbado::Sequence::Sequencer
          define_singleton_method(:name) { name }
          define_singleton_method(:build) { new }
          define_method(:call) { |ctx| Hubbado::Sequence::Result.ok(ctx) }
        end
      }

      context "succeed_with" do
        test "fires the success block with the configured ctx writes" do
          sub = build_substitute.()
          sub.succeed_with(view_model: :the_vm)

          received_ctx = nil
          sub.(seq_class.("Seqs::A")) do |r|
            r.success { |ctx| received_ctx = ctx }
          end

          assert received_ctx[:view_model] == :the_vm
        end

        test "with no arguments produces a success that fires the success block" do
          sub = build_substitute.()
          sub.succeed_with

          ran = []
          sub.(seq_class.("Seqs::A")) do |r|
            r.success { |_| ran << :success }
            r.otherwise { |_| ran << :otherwise }
          end

          assert ran == [:success]
        end

        test "default outcome (no staging) is success" do
          sub = build_substitute.()

          ran = []
          sub.(seq_class.("Seqs::A")) do |r|
            r.success { |_| ran << :success }
          end

          assert ran == [:success]
        end

        test "is fluent (returns self)" do
          sub = build_substitute.()
          assert sub.succeed_with(x: 1).equal?(sub)
        end
      end

      context "policy_failure" do
        test "fires the policy_failed block" do
          sub = build_substitute.()
          sub.policy_failure

          ran = []
          sub.(seq_class.("Seqs::A")) do |r|
            r.success       { |_| ran << :success }
            r.policy_failed { |_| ran << :policy_failed }
            r.otherwise     { |_| ran << :otherwise }
          end

          assert ran == [:policy_failed]
        end

        test "raises Errors::Unauthorized when no policy_failed block is given" do
          sub = build_substitute.()
          sub.policy_failure

          assert_raises Hubbado::Sequence::Errors::Unauthorized do
            sub.(seq_class.("Seqs::A")) { |r| r.success { |_| nil } }
          end
        end

        test "passes additional error attributes through" do
          sub = build_substitute.()
          sub.policy_failure(message: "blocked")

          received_error = nil
          sub.(seq_class.("Seqs::A")) do |r|
            r.policy_failed { |ctx| received_error = ctx }
          end

          assert received_error.is_a?(Hubbado::Sequence::Ctx)
        end
      end

      context "not_found" do
        test "fires the not_found block" do
          sub = build_substitute.()
          sub.not_found

          ran = []
          sub.(seq_class.("Seqs::A")) do |r|
            r.not_found { |_| ran << :not_found }
            r.otherwise { |_| ran << :otherwise }
          end

          assert ran == [:not_found]
        end

        test "raises Errors::NotFound when no not_found block is given" do
          sub = build_substitute.()
          sub.not_found

          assert_raises Hubbado::Sequence::Errors::NotFound do
            sub.(seq_class.("Seqs::A")) { |r| r.success { |_| nil } }
          end
        end
      end

      context "validation_failure" do
        test "fires the validation_failed block" do
          sub = build_substitute.()
          sub.validation_failure

          ran = []
          sub.(seq_class.("Seqs::A")) do |r|
            r.validation_failed { |_| ran << :validation_failed }
            r.otherwise         { |_| ran << :otherwise }
          end

          assert ran == [:validation_failed]
        end

        test "falls through to otherwise when no validation_failed block is given" do
          sub = build_substitute.()
          sub.validation_failure

          ran = []
          sub.(seq_class.("Seqs::A")) do |r|
            r.otherwise { |_| ran << :otherwise }
          end

          assert ran == [:otherwise]
        end
      end

      context "other_error" do
        test "fires the otherwise block for the configured code" do
          sub = build_substitute.()
          sub.other_error(code: :payment_failed)

          ran = []
          sub.(seq_class.("Seqs::A")) do |r|
            r.otherwise { |_| ran << :otherwise }
          end

          assert ran == [:otherwise]
        end

        test "requires an explicit code" do
          sub = build_substitute.()
          assert_raises ArgumentError do
            sub.other_error
          end
        end

        test "raises Errors::Failed when there is no otherwise block" do
          sub = build_substitute.()
          sub.other_error(code: :payment_failed)

          assert_raises Hubbado::Sequence::Errors::Failed do
            sub.(seq_class.("Seqs::A")) { |r| r.success { |_| nil } }
          end
        end
      end

      context "ran_with?" do
        test "true when invoked with the given sequencer class" do
          sub = build_substitute.()
          klass = seq_class.("Seqs::Membership")

          sub.(klass, current_user: :alice) { |r| r.success { |_| nil } }

          assert sub.ran_with?(klass)
        end

        test "false when not invoked" do
          sub = build_substitute.()
          assert !sub.ran_with?(seq_class.("Seqs::Anything"))
        end

        test "matches when supplied kwargs subset matches" do
          sub = build_substitute.()
          klass = seq_class.("Seqs::Membership")

          sub.(klass, current_user: :alice, params: { id: 7 }) { |r| r.success { |_| nil } }

          assert sub.ran_with?(klass, current_user: :alice)
          assert sub.ran_with?(klass, params: { id: 7 })
          assert sub.ran_with?(klass, current_user: :alice, params: { id: 7 })
        end

        test "false when sequencer matches but kwargs differ" do
          sub = build_substitute.()
          klass = seq_class.("Seqs::Membership")

          sub.(klass, current_user: :alice) { |r| r.success { |_| nil } }

          assert !sub.ran_with?(klass, current_user: :bob)
        end

        test "differentiates between sequencer classes" do
          sub = build_substitute.()
          membership = seq_class.("Seqs::Membership")
          create     = seq_class.("Seqs::Create")

          sub.(membership) { |r| r.success { |_| nil } }

          assert sub.ran_with?(membership)
          assert !sub.ran_with?(create)
        end
      end

      context "as a dependency" do
        test "is automatically installed for a class with dependency :run_sequence, Runner" do
          host_class = Class.new do
            include ::Dependency
            dependency :run_sequence, Hubbado::Sequence::Runner
          end

          host = host_class.new

          assert host.run_sequence.respond_to?(:succeed_with)
          assert host.run_sequence.respond_to?(:ran_with?)
        end
      end

      context "outcome staging across multiple invocations" do
        test "the most-recent staged outcome wins" do
          sub = build_substitute.()
          sub.succeed_with(x: 1)
          sub.policy_failure

          ran = []
          sub.(seq_class.("Seqs::A")) do |r|
            r.success       { |_| ran << :success }
            r.policy_failed { |_| ran << :policy_failed }
          end

          assert ran == [:policy_failed]
        end

        test "all invocations through the substitute produce the same staged outcome" do
          sub = build_substitute.()
          sub.policy_failure

          ran = []
          klass = seq_class.("Seqs::A")
          2.times do
            sub.(klass) do |r|
              r.policy_failed { |_| ran << :policy_failed }
            end
          end

          assert ran == [:policy_failed, :policy_failed]
        end
      end
    end
  end
end
