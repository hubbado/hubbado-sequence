module Hubbado
  module Sequence
    module Controls
      module Contract
        def self.example(model: nil, valid: true, save_result: true)
          klass = klass_for(valid: valid, save_result: save_result)
          klass.new(model)
        end

        # Returns a contract class that can be passed to Contract::Build as
        # `contract_class:`. The class wraps whatever model is passed to .new.
        def self.klass(valid: true, save_result: true)
          klass_for(valid: valid, save_result: save_result)
        end

        def self.klass_for(valid:, save_result:)
          Class.new do
            attr_reader :model, :validated_with, :saved
            attr_accessor :errors

            define_singleton_method(:default_valid) { valid }
            define_singleton_method(:default_save_result) { save_result }

            def initialize(model = nil)
              @model = model
              @valid = self.class.default_valid
              @save_result = self.class.default_save_result
              @errors = @valid ? [] : [:something_invalid]
            end

            def validate(params)
              @validated_with = params
              @valid
            end

            def save
              @saved = true
              @save_result
            end
          end
        end
      end
    end
  end
end
