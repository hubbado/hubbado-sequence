module Hubbado
  module Sequence
    module Macros
      module Contract
        class Validate
          configure :validate

          def self.build
            new
          end

          def call(ctx, from:)
            contract = ctx[:contract]
            params = Array(from).reduce(ctx) { |acc, k| acc.fetch(k) }

            contract.validate(params)

            if contract.errors.empty?
              Result.ok(ctx)
            else
              Result.fail(ctx, error: { code: :validation_failed })
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

            record def call(ctx, from:)
              return Result.fail(ctx, error: @configured_error) if @configured_error

              Result.ok(ctx)
            end

            def validated?(**kwargs)
              invoked?(:call, **kwargs)
            end
          end
        end
      end
    end
  end
end
