# Works with hubbado-policy. Builds a policy instance and calls the action; fails with :forbidden when denied.
module Hubbado
  module Sequence
    module Macros
      module Policy
        class Check
          configure :check_policy

          def self.build
            new
          end

          def self.failure(ctx, policy, policy_result)
            Result.failure(
              ctx,
              code: :forbidden,
              data: { policy: policy, policy_result: policy_result }
            )
          end

          def call(ctx, policy, action, record_key = nil)
            current_user = ctx[:current_user]
            record = record_key && ctx[record_key]

            policy_instance = policy.build(current_user, record)
            policy_result = policy_instance.public_send(action)

            if policy_result.permitted?
              Result.success(ctx)
            else
              self.class.failure(ctx, policy_instance, policy_result)
            end
          end

          module Substitute
            include ::RecordInvocation

            def succeed_with
              @configured_success = true
              self
            end

            def fail_with(**error_attrs)
              @configured_error = error_attrs
              self
            end

            record def call(ctx, policy, action, record_key = nil)
              unless policy.method_defined?(action)
                raise ArgumentError,
                  "Macros::Policy::Check substitute: #{policy} does not declare action :#{action}"
              end

              return Result.failure(ctx, **@configured_error) if @configured_error

              Result.success(ctx)
            end

            def checked?(**kwargs)
              invoked?(:call, **kwargs)
            end
          end
        end
      end
    end
  end
end
