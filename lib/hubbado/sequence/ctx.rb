module Hubbado
  module Sequence
    class Ctx < Hash
      def self.build(initial = {})
        ctx = new
        ctx.merge!(initial)
        ctx
      end

      def [](key)
        unless key?(key)
          raise KeyError, "key not found: #{key.inspect}"
        end

        super
      end
    end
  end
end
