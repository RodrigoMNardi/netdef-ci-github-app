# frozen_string_literal: true

require 'logger'

require_relative '../../database_loader'
require_relative '../bamboo_ci/stop_plan'
require_relative '../bamboo_ci/running_plan'
require_relative '../bamboo_ci/plan_run'
require_relative 'check'

module GitHub
  class BuildPlan
    def initialize(payload_raw, logger_level: Logger::INFO)
      @logger = Logger.new($stdout)
      @logger.level = logger_level

      @github_check = Github::Check.new(@payload)

      @payload = JSON.parse(payload_raw)

      @logger.debug 'This is a Pull Request - proceed with branch check'
    end

    def create
      unless %w[opened synchronize reopened].include? @payload['action']
        @logger.info "Action is \"#{@payload['action']}\" - ignored"

        return [200, "Not dealing with action \"#{@payload['action']}\" for Pull Request"]
      end

      # Fetch for a Pull Request at database
      fetch_pull_request
      # Stop a previous execution - Avoiding CI spam
      stop_previous_execution
      # Create a Check Suite
      create_check_suite

      # Check if could save the Check Suite at database
      unless @check_suite.persisted?
        @logger.error "Failed to save CheckSuite: #{@check_suite.errors.inspect}"
        [422, 'Failed to save Check Suite']
      end

      # Starting a new CI run
      status = start_new_execution

      return [status, 'Failed to create CI Plan'] if status != 200

      # Creating CiJobs at database
      create_ci_jobs
    end

    private

    def fetch_pull_request
      @pull_request = PullRequest.find(github_pr_id: github_pr, repository: @payload.dig('repository', 'full_name'))

      create_pull_request if @pull_request.nil?
    end

    def github_pr
      @payload.dig('number')
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
    end

    def start_new_execution
      @bamboo_plan_run = BambooCi::PlanRun.new(@pull_request, @payload, logger_level: @logger.level)
      @bamboo_plan_run.ci_variables = ci_vars
      @bamboo_plan_run.start_plan
    end

    def stop_previous_execution
      return if @pull_request.new? or @pull_request.finished?

      @pull_request.check_suites.last.ci_jobs.each do |ci_job|
        BambooCi::StopPlan.stop(ci_job.job_ref)
      end
    end

    def create_check_suite
      @check_suite =
        CheckSuite.create(
          pull_request: @pull_request,
          author: @payload.dig('pull_request', 'user', 'login'),
          commit_sha_ref: @payload.dig('pull_request', 'head', 'sha')
        )
    end

    def create_ci_jobs
      @check_suite.update(bamboo_ci_ref: @bamboo_plan_run.bamboo_reference)

      jobs = BambooCi::RunningPlan.fetch(@bamboo_plan_run.bamboo_reference)

      return [422, 'Failed to fetch RunningPlan'] if jobs.nil? or jobs.empty?

      jobs.each do |job|
        ci_job = CiJob.create(check_suite: @check_suite, name: job[:name], job_ref: job[:job_ref])

        next if ci_job.persisted?

        @github_check.create(job[:name])

        @logger.error "CiJob error: #{ci_job.errors.messages.inspect}"
      end

      [200, 'Pull Request created']
    end

    def ci_vars
      ci_vars = []
      ci_vars << { value: @check_suite.id, name: 'check_suite_id_secret' }
      ci_vars << { value: @github_check.app_id, name: 'app_id_secret' }
      ci_vars << { value: @github_check.installation_id, name: 'app_installation_id_secret' }
      ci_vars << { value: Base64.encode64(File.read('private_key.pem')), name: 'app_secret' }

      ci_vars
    end

    def fetch_plan
      plan = Plan.find_by_github_repo_name(@payload.dig('repository', 'full_name'))

      return plan unless plan.nil?

      # Default plan
      'TESTING-FRRCRAS'
    end
  end
end
