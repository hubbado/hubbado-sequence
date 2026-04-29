module Hubbado
  module Sequence
    # Resolves a ctx path expressed as a single Symbol (one-key shorthand) or
    # an Array of Symbols (nested fetch). Used by macros that need to read a
    # value out of ctx at a configurable location.
    #
    # `missing:` selects how an absent key is reported:
    #   :raise (default) — propagate KeyError. Right for Find/Validate/Build,
    #                      where a missing path is a wiring bug or a not-found.
    #   :nil             — return nil. Right for Deserialize, which runs ahead
    #                      of validation and may legitimately encounter absent
    #                      params (e.g. a fresh GET before the form is posted).
    module Path
      def self.resolve(ctx, path, missing: :raise)
        unless %i[raise nil].include?(missing)
          raise ArgumentError, "unknown missing policy: #{missing.inspect}"
        end

        if path.is_a?(Array) && path.empty?
          raise ArgumentError, "path cannot be empty"
        end

        Array(path).reduce(ctx) do |acc, key|
          if missing == :nil
            acc.fetch(key) { return nil }
          else
            acc.fetch(key)
          end
        end
      end
    end
  end
end
