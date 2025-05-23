#  SPDX-License-Identifier: BSD-2-Clause
#
#  build_plan.rb
#  Part of NetDEF CI System
#
#  Copyright (c) 2023 by
#  Network Device Education Foundation, Inc. ("NetDEF")
#
#  frozen_string_literal: true

require 'logger'

require_relative '../../database_loader'
require_relative '../bamboo_ci/stop_plan'
require_relative '../bamboo_ci/running_plan'
require_relative '../bamboo_ci/plan_run'
require_relative 'check'
require_relative 'build/action'
require_relative 'user_info'

module Github
  class BuildPlan
    def initialize(payload, logger_level: Logger::INFO)
      @logger = Logger.new($stdout)
      @logger.level = logger_level
      @has_previous_exec = false

      @payload = payload

      raise "Invalid payload:\n#{payload}" if @payload.nil? or @payload.empty?

      @logger.debug 'This is a Pull Request - proceed with branch check'
    end

    def create
      unless %w[opened synchronize reopened].include? @payload['action']
        @logger.warn "Action is \"#{@payload['action']}\" - ignored"

        return [405, "Not dealing with action \"#{@payload['action']}\" for Pull Request"]
      end

      # Fetch for a Pull Request at database
      @logger.info 'Fetching / Creating a pull request'
      fetch_pull_request

      # Fetch last Check Suite
      fetch_last_check_suite

      # Create a Check Suite
      create_check_suite

      # Check if could save the Check Suite at database
      unless @check_suite.persisted?
        @logger.error "Failed to save CheckSuite: #{@check_suite.errors.inspect}"
        return [422, 'Failed to save Check Suite']
      end

      # Stop a previous execution - Avoiding CI spam
      stop_previous_execution

      # Starting a new CI run
      status = start_new_execution

      return [status, 'Failed to create CI Plan'] if status != 200

      # Creating CiJobs at database
      ci_jobs
    end

    private

    def fetch_pull_request
      @pull_request = PullRequest.find_by(github_pr_id: github_pr, repository: @payload.dig('repository', 'full_name'))

      return create_pull_request if @pull_request.nil?

      @logger.info "Updating plan: #{fetch_plan}"

      @pull_request.update(plan: fetch_plan, branch_name: @payload.dig('pull_request', 'head', 'ref'))
    end

    def github_pr
      @payload['number']
    end

    def create_pull_request
      @pull_request =
        PullRequest.create(
          author: @payload.dig('pull_request', 'user', 'login'),
          github_pr_id: github_pr,
          branch_name: @payload.dig('pull_request', 'head', 'ref'),
          repository: @payload.dig('repository', 'full_name'),
          plan: fetch_plan
        )

      Github::UserInfo.new(@payload.dig('pull_request', 'user', 'id'), pull_request: @pull_request)
    end

    def start_new_execution
      create_pull_request if @pull_request.nil?

      @check_suite.pull_request = @pull_request

      Github::UserInfo.new(@payload.dig('pull_request', 'user', 'id'), check_suite: @check_suite)

      @bamboo_plan_run = BambooCi::PlanRun.new(@check_suite, logger_level: @logger.level)
      @bamboo_plan_run.ci_variables = ci_vars
      @bamboo_plan_run.start_plan
    end

    def stop_previous_execution
      return if @last_check_suite.nil? or @last_check_suite.finished?

      @logger.info 'Stopping previous execution'
      @logger.info @last_check_suite.inspect
      @logger.info @check_suite.inspect

      cancel_previous_ci_jobs
    end

    def cancel_previous_ci_jobs
      @last_check_suite.ci_jobs.where(status: %w[queued in_progress]).each do |ci_job|
        @logger.warn("Cancelling Job #{ci_job.inspect}")
        ci_job.cancelled(@github_check)
      end

      @last_check_suite.update(stopped_in_stage: @last_check_suite.stages.where(status: :in_progress).last)

      @last_check_suite.stages.where(status: %w[queued in_progress]).each do |stage|
        stage.cancelled(@github_check)
      end

      @has_previous_exec = true
      BambooCi::StopPlan.build(@last_check_suite.bamboo_ci_ref)
    end

    def create_check_suite
      @logger.info 'Creating a check suite'
      @check_suite =
        CheckSuite.create(
          pull_request: @pull_request,
          author: @payload.dig('pull_request', 'user', 'login'),
          commit_sha_ref: @payload.dig('pull_request', 'head', 'sha'),
          work_branch: @payload.dig('pull_request', 'head', 'ref'),
          base_sha_ref: @payload.dig('pull_request', 'base', 'sha'),
          merge_branch: @payload.dig('pull_request', 'base', 'ref')
        )

      @logger.info 'Creating GitHub Check API'
      @github_check = Github::Check.new(@check_suite)
    end

    def fetch_last_check_suite
      @last_check_suite = @pull_request.check_suites.last
    end

    def ci_jobs
      @logger.info 'Creating GitHub Check'

      SlackBot.instance.execution_started_notification(@check_suite)

      @check_suite.update(bamboo_ci_ref: @bamboo_plan_run.bamboo_reference)

      jobs = BambooCi::RunningPlan.fetch(@bamboo_plan_run.bamboo_reference)

      return [422, 'Failed to fetch RunningPlan'] if jobs.nil? or jobs.empty?

      action = Github::Build::Action.new(@check_suite, @github_check, jobs)
      action.create_summary

      @logger.info ">>> @has_previous_exec: #{@has_previous_exec}"
      stop_execution_message if @has_previous_exec

      [200, 'Pull Request created']
    end

    def stop_execution_message
      @check_suite.update(cancelled_previous_check_suite_id: @last_check_suite.id)
      BambooCi::StopPlan.comment(@last_check_suite, @check_suite)
    end

    def ci_vars
      ci_vars = []
      ci_vars << { value: @github_check.signature, name: 'signature_secret' }

      ci_vars
    end

    def fetch_plan
      plan = Plan.find_by(github_repo_name: @payload.dig('repository', 'full_name'))

      return plan.bamboo_ci_plan_name unless plan.nil?

      # Default plan
      'TESTING-FRRCRAS'
    end
  end
end
