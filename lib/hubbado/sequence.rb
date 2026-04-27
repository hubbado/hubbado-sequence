require "i18n"
require "casing"
require "configure"; Configure.activate
require "dependency"; Dependency.activate
require "hubbado/log"
require "record_invocation"
require "template_method"; TemplateMethod.activate

I18n.load_path += Dir[File.expand_path("../../config/locales", __dir__) + "/*.yml"]
I18n.default_locale = :en if I18n.default_locale.nil?

module Hubbado
  module Sequence
  end
end

require "hubbado/sequence/ctx"
require "hubbado/sequence/result"
require "hubbado/sequence/pipeline"
require "hubbado/sequence/sequencer"
require "hubbado/sequence/macros/model/find"
require "hubbado/sequence/macros/model/build"
require "hubbado/sequence/macros/contract/build"
require "hubbado/sequence/macros/contract/validate"
require "hubbado/sequence/macros/contract/persist"
require "hubbado/sequence/macros/policy/check"
require "hubbado/sequence/errors"
require "hubbado/sequence/run_sequence"
