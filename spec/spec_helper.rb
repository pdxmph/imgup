# spec/spec_helper.rb
require "bundler/setup"
require "imgup-cli"
require "webmock/rspec"
WebMock.disable_net_connect!(allow_localhost: true)
