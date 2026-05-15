# Works with Reform contracts. Wraps a model in a contract class and writes the instance to ctx[:contract].
module Hubbado
  module Sequence
    module Macros
      module Contract
        class Build
          configure :build_contract

          def self.build
            new
          end

          def call(ctx, contract_class, attr_name = nil)
            model = attr_name && Path.resolve(ctx, attr_name)
            ctx[:contract] = contract_class.new(model)
            Result.success(ctx)
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

            record def call(ctx, contract_class, attr_name = nil)
              return Result.failure(ctx, error: @configured_error) if @configured_error

              ctx[:contract] = @return_value if @configured_success
              Result.success(ctx)
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
