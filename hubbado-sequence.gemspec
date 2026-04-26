# -*- encoding: utf-8 -*-
Gem::Specification.new do |s|
  s.name = "hubbado-sequence"
  s.version = "0.1.0"
  s.summary = "A small framework for orchestrating units of business behaviour"
  s.description = "Sequencer takes input, runs a sequence of steps, and returns a Result indicating success or failure plus the working context that was built up during execution."

  s.authors = ["Hubbado Devs"]
  s.email = ["devs@hubbado.com"]
  s.homepage = "https://github.com/hubbado/hubbado-sequence"

  s.metadata["allowed_push_host"] = "https://rubygems.pkg.github.com/hubbado"
  s.metadata["github_repo"] = s.homepage
  s.metadata["homepage_uri"] = s.homepage

  s.require_paths = ["lib"]
  s.files = Dir.glob(%w[
    lib/**/*.rb
    config/**/*.yml
    *.gemspec
    LICENSE*
    README*
    CHANGELOG*
  ])
  s.platform = Gem::Platform::RUBY
  s.required_ruby_version = ">= 3.3"

  s.add_runtime_dependency "evt-casing"
  s.add_runtime_dependency "evt-configure"
  s.add_runtime_dependency "evt-dependency"
  s.add_runtime_dependency "evt-record_invocation"
  s.add_runtime_dependency "evt-template_method"
  s.add_runtime_dependency "hubbado-log"
  s.add_runtime_dependency "i18n"

  s.add_development_dependency "debug"
  s.add_development_dependency "hubbado-style"
  s.add_development_dependency "test_bench"
end
