#   SPDX-License-Identifier: BSD-2-Clause
#
#   sync_pr_outdated.rb
#   Part of NetDEF CI System
#
#   Copyright (c) 2025 by
#   Network Device Education Foundation, Inc. ("NetDEF")
#
#   frozen_string_literal: true

require_relative '../config/setup'

#
# == Class: SyncPROutdated
#
# This class is responsible for synchronizing outdated pull request (PR) check suites
# with the current build status from Bamboo CI. It queries recent CheckSuite records,
# fetches their build status from Bamboo, and updates the corresponding CI job statuses
# and summaries in the system.
#
# === Usage
#   sync = SyncPROutdated.new(last_days: 5)
#   sync.run
#
# === Methods
#
# - initialize(last_days: 5)::
#     Initializes the SyncPROutdated instance, setting the number of days in the past
#     to look for CheckSuite records. Default is 5 days.
#
# - run::
#     Main entry point. Iterates over CheckSuite records created within the last N days
#     that are still running, fetches their build status, and processes the results.
#
# - process_json(data, check_suite)::
#     Processes the build status JSON data for a given CheckSuite. Iterates through
#     each stage and its jobs, updating job statuses and generating build summaries.
#     Params:
#       +data+:: Hash containing build status data from Bamboo
#       +check_suite+:: The CheckSuite object being processed
#
# - fetch_job_execution(stage_name, results, check)::
#     Iterates through all jobs in a given stage, printing job details, updating job
#     statuses if needed, and returning the last processed CI job.
#     Params:
#       +stage_name+:: String name of the current stage
#       +results+:: Array of job result hashes
#       +check+:: Github::Check instance for updating job status
#     Returns::
#       The last processed CiJob instance or nil
#
# - update_job_status_if_needed(producer_job_key, state, check)::
#     Finds the CiJob by its reference key and updates its status based on the state
#     from Bamboo. Handles 'Successful' and 'Failed' states, and prints job info.
#     Params:
#       +producer_job_key+:: String job reference key
#       +state+:: String state from Bamboo ('Successful', 'Failed', etc.)
#       +check+:: Github::Check instance for updating job status
#     Returns::
#       The updated CiJob instance
#
# - fetch_build_status(check_suite)::
#     Fetches the build status from Bamboo for the given CheckSuite.
#     Params:
#       +check_suite+:: The CheckSuite object
#     Returns::
#       Hash containing the build status data
class SyncPROutdated
  include BambooCi::Api

  # Initializes the SyncPROutdated instance.
  # @param last_days [Integer] Number of days in the past to look for CheckSuite records (default: 5)
  def initialize(last_days: 5)
    @last_days = last_days
  end

  # Main entry point. Iterates over recent running CheckSuite records and processes them.
  def run
    CheckSuite
      .where(created_at: @last_days.days.ago.beginning_of_day..Time.current.end_of_day)
      .each do |check_suite|
      next unless check_suite.running?

      process_json(fetch_build_status(check_suite), check_suite)
    end
  end

  def single_pr(pr_id)
    last_check_suite = PullRequest.find_by(github_pr_id: pr_id)&.check_suites&.last

    if last_check_suite.nil?
      puts "No CheckSuite found for PR ID: #{pr_id}"
      return
    end

    process_json(fetch_build_status(last_check_suite), last_check_suite)
  end

  private

  # Processes the build status JSON data for a given CheckSuite.
  # @param data [Hash] Build status data from Bamboo
  # @param check_suite [CheckSuite] The CheckSuite being processed
  def process_json(data, check_suite)
    stages = data.dig('stages', 'stage') || []

    check = Github::Check.new(check_suite)

    stages.each do |stage|
      stage_name = stage['name']
      results = stage.dig('results', 'result') || []

      ci_job_last = fetch_job_execution(stage_name, results, check)

      next if ci_job_last.nil?

      summary = Github::Build::Summary.new(ci_job_last)
      summary.build_summary
    end
  end

  # Iterates through all jobs in a given stage, printing job details and updating job statuses.
  # @param stage_name [String] Name of the current stage
  # @param results [Array<Hash>] Array of job result hashes
  # @param check [Github::Check] Check instance for updating job status
  # @return [CiJob, nil] The last processed CiJob instance or nil
  def fetch_job_execution(stage_name, results, check)
    ci_job_last = nil

    results.each do |job|
      producer_job_key = job.dig('planResultKey', 'key')
      job_name = job['planName']
      state = job['state']
      build_state = job['buildState']

      puts "Stage: #{stage_name}"
      puts "ProducerJobKey: #{producer_job_key}"
      puts "Job Name: #{job_name}"
      puts "State: #{state}"
      puts "Build State: #{build_state}"

      ci_job_last = update_job_status_if_needed(producer_job_key, state, check)

      puts '-' * 50
    end

    ci_job_last
  end

  # Finds the CiJob by its reference key and updates its status if needed.
  # @param producer_job_key [String] Job reference key
  # @param state [String] State from Bamboo ('Successful', 'Failed', etc.)
  # @param check [Github::Check] Check instance for updating job status
  # @return [CiJob, nil] The updated CiJob instance or nil if not found
  def update_job_status_if_needed(producer_job_key, state, check)
    ci_job = CiJob.find_by(job_ref: producer_job_key)
    puts ci_job.inspect

    return nil if ci_job.nil?

    case state
    when 'Successful'
      ci_job.success(check) unless ci_job.success?
    when 'Failed'
      ci_job.failure(check) unless ci_job.failure?
    else
      puts 'Job is still in progress or in an unknown state.'
    end

    ci_job
  end

  # Fetches the build status from Bamboo for the given CheckSuite.
  # @param check_suite [CheckSuite] The CheckSuite object
  # @return [Hash] Build status data
  def fetch_build_status(check_suite)
    get_status(check_suite.bamboo_ci_ref)
  end
end
