module Hubbado
  module Sequence
    module Macros
      module Contract
        class Persist
          configure :persist

          def self.build
            new
          end

          def call(ctx)
            contract = ctx[:contract]

            if contract.save
              Result.ok(ctx)
            else
              Result.fail(ctx, error: { code: :persist_failed })
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

            record def call(ctx)
              return Result.fail(ctx, error: @configured_error) if @configured_error

              Result.ok(ctx)
            end

            def persisted?(**kwargs)
              invoked?(:call, **kwargs)
            end
          end
        end
      end
    end
  end
end
