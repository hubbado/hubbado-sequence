module Hubbado
  module Sequence
    module Macros
      module Model
        class Find
          configure :find

          def self.build
            new
          end

          def call(ctx, model, as:, id_key: :id, from: :params)
            id = read_id(ctx, from, id_key)
            record = model.find_by(id: id)

            if record
              ctx[as] = record
              Result.ok(ctx)
            else
              Result.fail(ctx, error: { code: :not_found })
            end
          end

          private

          def read_id(ctx, from, id_key)
            container = Array(from).reduce(ctx) { |acc, k| acc.fetch(k) }
            container.is_a?(Hash) ? container[id_key] : container
          end

          module Substitute
            include ::RecordInvocation

            def succeed_with(value)
              @return_value = value
              @configured_success = true
              self
            end

            def fail_with(**error_attrs)
              @configured_error = error_attrs
              self
            end

            record def call(ctx, model, as:, id_key: :id, from: :params)
              unless model.respond_to?(:find_by)
                raise ArgumentError,
                  "Macros::Model::Find substitute: #{model} does not respond to :find_by"
              end

              return Result.fail(ctx, error: @configured_error) if @configured_error

              ctx[as] = @return_value if @configured_success
              Result.ok(ctx)
            end

            def fetched?(**kwargs)
              invoked?(:call, **kwargs)
            end
          end
        end
      end
    end
  end
end
