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

          def call(ctx, contract_class, model = nil)
            resolved_model = model && Path.resolve(ctx, model)
            ctx[:contract] = contract_class.new(resolved_model)
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

            record def call(ctx, contract_class, model = nil)
              return Result.failure(ctx, **@configured_error) if @configured_error

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
