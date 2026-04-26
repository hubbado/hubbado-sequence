module Hubbado
  module Sequence
    module Controls
      module Model
        def self.example
          Class.new do
            def self.records
              @records ||= {}
            end

            def self.put(id, value)
              records[id] = value
            end

            def self.find_by(id:)
              records[id]
            end

            def self.reset
              @records = {}
            end

            attr_reader :init_attributes

            def initialize(attributes = {})
              @init_attributes = attributes
            end
          end
        end
      end
    end
  end
end
