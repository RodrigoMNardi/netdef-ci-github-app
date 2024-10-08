#  SPDX-License-Identifier: BSD-2-Clause
#
#  spec_helper.rb
#  Part of NetDEF CI System
#
#  Copyright (c) 2023 by
#  Network Device Education Foundation, Inc. ("NetDEF")
#
#  frozen_string_literal: true

ENV['RACK_ENV'] = 'test'
ENV['RAILS_ENV'] = 'test'

require 'database_cleaner'
require 'factory_bot'
require 'faker'
require 'rspec'
require 'rack/test'
require 'webmock/rspec'
require 'fileutils'

Dir["#{__dir__}/support/*.rb"].each { |file| require file }
Dir["#{__dir__}/factories/*.rb"].each { |file| load file }

require 'simplecov'
SimpleCov.start

require_relative '../app/github_app'
require_relative '../config/delayed_job'

def app
  GithubApp
end

DatabaseCleaner.strategy = :truncation

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.include FactoryBot::Syntax::Methods
  config.include WebMock::API

  config.add_formatter('json', 'tmp/rspec_results.json')

  pid = nil

  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before(:all) do
    pid = Thread.new do
      Delayed::Worker.new(
        min_priority: 0,
        max_priority: 10,
        quiet: true
      ).start
    end
  end

  config.after(:all) do
    pid&.exit
  end

  config.before(:each) do
    allow_any_instance_of(Object).to receive(:sleep)
    Delayed::Worker.delay_jobs = false
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.warnings = true
  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed
end
