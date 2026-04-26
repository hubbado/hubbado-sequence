ENV["CONSOLE_DEVICE"] ||= "stdout"
ENV["LOG_LEVEL"] ||= "_min"

puts RUBY_DESCRIPTION

puts
puts "TEST_BENCH_DETAIL: #{ENV["TEST_BENCH_DETAIL"].inspect}"
puts

require_relative "../init.rb"
require "hubbado/sequence/controls"
require "hubbado/log/controls"

require "test_bench"; TestBench.activate
require "debug"

I18n.load_path += Dir[File.expand_path("test/locales") + "/*.yml"]

Hubbado::Log.configuration do |config|
  config.loggers = [Hubbado::Log::Controls::LogHandler]
end

include Hubbado::Sequence
