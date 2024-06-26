#  SPDX-License-Identifier: BSD-2-Clause
#
#  comment_spec.rb
#  Part of NetDEF CI System
#
#  Copyright (c) 2024 by
#  Network Device Education Foundation, Inc. ("NetDEF")
#
#  frozen_string_literal: true

describe Github::Retry::Comment do
  let(:github_retry) { described_class.new(payload) }
  let(:fake_client) { Octokit::Client.new }
  let(:fake_github_check) { Github::Check.new(nil) }
  let(:fake_plan_run) { BambooCi::PlanRun.new(nil) }
  let(:fake_unavailable) { Github::Build::UnavailableJobs.new(nil) }

  before do
    allow(File).to receive(:read).and_return('')
    allow(OpenSSL::PKey::RSA).to receive(:new).and_return(OpenSSL::PKey::RSA.new(2048))
    allow(Github::Build::UnavailableJobs).to receive(:new).and_return(fake_unavailable)
  end

  describe 'Valid payload' do
    let(:fake_client) { Octokit::Client.new }
    let(:fake_github_check) { Github::Check.new(nil) }
    let(:fake_translation) { create(:stage_configuration) }

    before do
      allow(Octokit::Client).to receive(:new).and_return(fake_client)
      allow(fake_client).to receive(:find_app_installations).and_return([{ 'id' => 1 }])
      allow(fake_client).to receive(:create_app_installation_access_token).and_return({ 'token' => 1 })

      allow(Github::Check).to receive(:new).and_return(fake_github_check)
      allow(fake_github_check).to receive(:create).and_return(check_suite)
      allow(fake_github_check).to receive(:add_comment)
      allow(fake_github_check).to receive(:cancelled)
      allow(fake_github_check).to receive(:in_progress)
      allow(fake_github_check).to receive(:queued)
      allow(fake_github_check).to receive(:comment_reaction_thumb_up)
      allow(fake_github_check).to receive(:comment_reaction_thumb_down)
      allow(fake_github_check).to receive(:fetch_username).and_return({})

      allow(BambooCi::PlanRun).to receive(:new).and_return(fake_plan_run)
      allow(fake_plan_run).to receive(:start_plan).and_return(200)
      allow(fake_plan_run).to receive(:bamboo_reference).and_return('UNIT-TEST-1')
      allow(fake_plan_run).to receive(:bamboo_reference).and_return('CHK-01')

      allow(BambooCi::Retry).to receive(:restart)

      allow(BambooCi::StopPlan).to receive(:build)
      allow(BambooCi::RunningPlan).to receive(:fetch).with(fake_plan_run.bamboo_reference).and_return(ci_jobs)
    end

    context 'when receives a valid command' do
      let(:check_suite) { create(:check_suite, :with_running_ci_jobs) }
      let(:ci_jobs) do
        [
          { name: 'First Test', job_ref: 'UNIT-TEST-FIRST-1', stage: fake_translation.bamboo_stage_name },
          { name: 'Checkout', job_ref: 'CHK-01', stage: fake_translation.bamboo_stage_name }
        ]
      end
      let(:payload) do
        {
          'action' => 'created',
          'comment' => { 'body' => "ci:retry ##{check_suite.commit_sha_ref}", 'id' => 1 },
          'repository' => { 'full_name' => check_suite.pull_request.repository },
          'issue' => { 'number' => check_suite.pull_request.github_pr_id }
        }
      end

      before do
        check_suite.stages.last.update(status: :failure)
        check_suite.stages.last.jobs.each { |job| job.update(status: :failure) }
      end

      it 'must returns success' do
        expect(github_retry.start).to eq([200, 'Retrying failure jobs'])
        expect(check_suite.stages.last.reload.status).to eq('queued')
      end
    end

    context 'when receives a valid command - but still running' do
      let(:check_suite) { create(:check_suite, :with_running_ci_jobs) }
      let(:ci_jobs) do
        [
          { name: 'First Test', job_ref: 'UNIT-TEST-FIRST-1', stage: fake_translation.bamboo_stage_name },
          { name: 'Checkout', job_ref: 'CHK-01', stage: fake_translation.bamboo_stage_name }
        ]
      end
      let(:payload) do
        {
          'action' => 'created',
          'comment' => { 'body' => "ci:retry ##{check_suite.commit_sha_ref}", 'id' => 1 },
          'repository' => { 'full_name' => check_suite.pull_request.repository },
          'issue' => { 'number' => check_suite.pull_request.github_pr_id }
        }
      end

      it 'must returns stage not found' do
        expect(github_retry.start).to eq([404, 'Stage not found'])
        expect(check_suite.stages.last.reload.status).to eq('in_progress')
      end
    end
  end

  describe 'Invalid payload' do
    let(:fake_client) { Octokit::Client.new }
    let(:fake_github_check) { Github::Check.new(nil) }
    let(:fake_translation) { create(:stage_configuration) }

    before do
      allow(Octokit::Client).to receive(:new).and_return(fake_client)
      allow(fake_client).to receive(:find_app_installations).and_return([{ 'id' => 1 }])
      allow(fake_client).to receive(:create_app_installation_access_token).and_return({ 'token' => 1 })
    end

    context 'when receives an invalid PR' do
      let(:payload) do
        {
          'action' => 'created',
          'comment' => { 'body' => 'ci:retry', 'id' => 1 },
          'repository' => { 'full_name' => 'test' },
          'issue' => { 'number' => 0 }
        }
      end

      it 'must returns stage not found' do
        expect(github_retry.start).to eq([404, 'Stage not found'])
      end
    end
  end
end
