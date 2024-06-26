#  SPDX-License-Identifier: BSD-2-Clause
#
#  rerun_report.rb
#  Part of NetDEF CI System
#
#  Copyright (c) 2024 by
#  Network Device Education Foundation, Inc. ("NetDEF")
#
#  frozen_string_literal: true

require 'json'
require_relative '../database_loader'

module Reports
  class ReRunReportByUser
    def report(begin_date, end_date, user, output: 'print', filename: 'rerun_report.json')
      @result = {}

      audit_retries = AuditRetry.where(github_username: user).order(:created_at)
      audit_retries = audit_retries.where(created_at: [begin_date..end_date]) unless begin_date.nil? or end_date.nil?

      audit_retries
        .each do |audit_retry|
        puts audit_retry.inspect
        generate_result(audit_retry)
      end

      save_rerun_info(@result, output, filename)
    end

    private

    def generate_result(audit_retry)
      report_initializer(audit_retry)

      @result[audit_retry.check_suite.pull_request.github_pr_id][:total] += 1

      check_suite_detail(audit_retry)
    end

    def report_initializer(audit_retry)
      @result[audit_retry.check_suite.pull_request.github_pr_id] ||=
        { total: 0, check_suites: [] }
    end

    def check_suite_detail(audit_retry)
      @result[audit_retry.check_suite.pull_request.github_pr_id][:check_suites] <<
        {
          check_suite_id: audit_retry.check_suite.id,
          bamboo_job: audit_retry.check_suite.bamboo_ci_ref,
          github_username: audit_retry.github_username,
          tests_or_builds: audit_retry.ci_jobs.map(&:name),
          requested_at: audit_retry.created_at,
          type: audit_retry.retry_type
        }
    end

    def save_rerun_info(result, output, filename)
      case output
      when 'json'
        File.write(filename, result.to_json)
      when 'csv'
        create_csv(filename)
      when 'file'
        File.open(filename, 'a') do |f|
          raw_output(result, file_descriptor: f)
        end
      else
        raw_output(result)
      end
    end

    def create_csv(filename)
      CSV.open(filename, 'wb') do |csv_input|
        csv_input << %w[PullRequest CheckSuiteId BambooJob GithubUsername RequestedAt Type TestsOrBuilds]
        @result.each_pair do |pull_requst, info|
          info[:check_suites].each do |cs|
            csv_input << [pull_requst,
                          cs[:check_suite_id], cs[:bamboo_job], cs[:requested_at],
                          cs[:github_username], cs[:type], cs[:tests_or_builds].join(',')]
          end
        end
      end
    end

    def raw_output(result, file_descriptor: nil)
      result.each_pair do |pull_request, info|
        print("\nPull Request: ##{pull_request} - Reruns: #{info[:total]}", file_descriptor)

        info[:check_suites].each do |cs|
          print("  - [#{cs[:type]}] Check Suite: #{cs[:check_suite_id]} - Requested at: #{cs[:requested_at]}",
                file_descriptor)
          print("    - Bamboo Job: #{cs[:bamboo_job]}", file_descriptor)
          print("    - Github Username: #{cs[:github_username]}", file_descriptor)

          print_test_build_retry(cs, file_descriptor)
        end
      end
    end

    def print_test_build_retry(info, file_descriptor)
      return if info[:tests_or_builds].nil? or info[:tests_or_builds].empty?

      print('    - Retried tests', file_descriptor)

      info[:tests_or_builds].each do |entry|
        print("      - #{entry}", file_descriptor)
      end
    end

    def print(line, file_descriptor)
      puts line
      file_descriptor&.write line
    end
  end
end

return unless __FILE__ == $PROGRAM_NAME

begin_date = ARGV[1]
end_date = ARGV[2]

Reports::ReRunReportByUser.new.report(begin_date, end_date, ARGV[0], output: ARGV[3], filename: ARGV[4])
