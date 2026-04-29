module Hubbado
  module Sequence
    module Macros
      module Contract
        class Deserialize
          configure :deserialize

          def self.build
            new
          end

          def call(ctx, from:)
            params = Path.resolve(ctx, from, missing: :nil)

            ctx[:contract].deserialize(params) if params

            Result.ok(ctx)
          end

          module Substitute
            include ::RecordInvocation

            def fail_with(**error_attrs)
              @configured_error = error_attrs
              self
            end

            record def call(ctx, from:)
              return Result.fail(ctx, error: @configured_error) if @configured_error

              Result.ok(ctx)
            end

            def deserialized?(**kwargs)
              invoked?(:call, **kwargs)
            end
          end
        end
      end
    end
  end
end
