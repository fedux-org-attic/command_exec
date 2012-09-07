#encoding: utf-8

$LOAD_PATH << File.expand_path('../lib' , File.dirname(__FILE__))

unless ENV['TRAVIS_CI'] == 'true'
  require 'pry'
  require 'debugger'
end
require 'stringio'
require 'ap'

require 'tempfile'

require 'simplecov'
SimpleCov.start

require 'command_exec'
require 'command_exec/spec_helper_module'

include CommandExec
include CommandExec::Exceptions

RSpec.configure do |c|
  c.include CommandExec::SpecHelper
end

