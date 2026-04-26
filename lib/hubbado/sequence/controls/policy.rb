module Hubbado
  module Sequence
    module Controls
      module Policy
        # Minimal stand-in for a hubbado-policy::Result so we don't take a hard
        # dependency on the policy gem from these controls.
        class PolicyResult
          attr_reader :reason

          def initialize(permitted, reason)
            @permitted = permitted
            @reason = reason
          end

          def permitted?; @permitted; end
          def denied?; !@permitted; end
        end

        def self.example(decision: :permit, action: :update)
          klass_for(decision: decision, action: action)
        end

        def self.klass_for(decision:, action:)
          Class.new do
            attr_reader :user, :record

            define_singleton_method(:default_decision) { decision }
            define_singleton_method(:default_action) { action }

            def self.build(user, record)
              new(user, record)
            end

            def initialize(user, record)
              @user = user
              @record = record
            end

            define_method(action) do
              decision = self.class.default_decision
              if decision == :permit
                PolicyResult.new(true, :permitted)
              else
                PolicyResult.new(false, :not_owner)
              end
            end
          end
        end
      end
    end
  end
end
