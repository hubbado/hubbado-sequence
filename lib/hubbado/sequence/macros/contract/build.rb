module Hubbado
  module Sequence
    module Macros
      module Contract
        class Build
          configure :build_contract

          def self.build
            new
          end

          def call(ctx, contract_class, attr_name)
            ctx[:contract] = contract_class.new(ctx[attr_name])
            Result.ok(ctx)
          end

          module Substitute
            include ::RecordInvocation

            def succeed_with(contract)
              @return_value = contract
              @configured_success = true
              self
            end

            def fail_with(**error_attrs)
              @configured_error = error_attrs
              self
            end

            record def call(ctx, contract_class, attr_name)
              return Result.fail(ctx, error: @configured_error) if @configured_error

              ctx[:contract] = @return_value if @configured_success
              Result.ok(ctx)
            end

            def built?(**kwargs)
              invoked?(:call, **kwargs)
            end
          end
        end
      end
    end
  end
end
