module Hubbado
  module Sequence
    module Errors
      Failed = Class.new(StandardError)
      NotFound = Class.new(StandardError)
      Unauthorized = Class.new(StandardError) do
        attr_reader :result

        def initialize(message = nil, result = nil)
          super(message)
          @result = result
        end
      end
    end
  end
end
