module Hubbado
  module Sequence
    module Macros
      module Policy
        class Check
          configure :check_policy

          def self.build
            new
          end

          def call(ctx, policy, record_key, action)
            current_user = ctx[:current_user]
            record = ctx[record_key]

            policy_instance = policy.build(current_user, record)
            policy_result = policy_instance.public_send(action)

            if policy_result.permitted?
              Result.ok(ctx)
            else
              Result.fail(
                ctx,
                error: {
                  code: :forbidden,
                  data: { policy: policy_instance, policy_result: policy_result }
                }
              )
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

            record def call(ctx, policy, record_key, action)
              unless policy.method_defined?(action)
                raise ArgumentError,
                  "Macros::Policy::Check substitute: #{policy} does not declare action :#{action}"
              end

              return Result.fail(ctx, error: @configured_error) if @configured_error

              Result.ok(ctx)
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
