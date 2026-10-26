# 03 — Class diagrams

## 1. Data model (ER)

Based on `db/schema.rb` and the associations in `lib/models/`.

```mermaid
erDiagram
    ORGANIZATION ||--o{ GITHUB_USER : has
    GITHUB_USER ||--o{ PULL_REQUEST : authors
    GITHUB_USER ||--o{ CHECK_SUITE : triggers
    GITHUB_USER ||--o{ AUDIT_RETRY : requests
    PULL_REQUEST ||--o{ CHECK_SUITE : has
    PULL_REQUEST ||--o{ PLAN : "plans (per repository)"
    PULL_REQUEST ||--o{ PULL_REQUEST_SUBSCRIPTION : has
    PLAN ||--o{ CHECK_SUITE : executions
    CHECK_SUITE ||--o{ STAGE : has
    CHECK_SUITE ||--o{ CI_JOB : has
    CHECK_SUITE ||--o{ AUDIT_RETRY : has
    CHECK_SUITE }o--o| CHECK_SUITE : cancelled_previous_check_suite
    CHECK_SUITE }o--o| STAGE : stopped_in_stage
    STAGE_CONFIGURATION ||--o{ STAGE : configures
    STAGE ||--o{ CI_JOB : has
    CI_JOB ||--o{ TOPOTEST_FAILURE : has
    CI_JOB }o--o{ AUDIT_RETRY : "audit_retries_ci_jobs"
    CI_JOB ||--o{ AUDIT_STATUS : "auditable (polymorphic)"
    STAGE ||--o{ AUDIT_STATUS : "auditable (polymorphic)"

    PULL_REQUEST {
        int github_pr_id
        string repository
        string branch_name
        string author
    }
    CHECK_SUITE {
        string commit_sha_ref
        string base_sha_ref
        string bamboo_ci_ref
        string merge_branch
        int retry
        bool re_run
    }
    STAGE {
        string name
        int status
        string check_ref
        int execution_time
    }
    STAGE_CONFIGURATION {
        string bamboo_stage_name
        string github_check_run_name
        int position
        bool mandatory
        bool can_retry
        bool start_in_progress
    }
    CI_JOB {
        string name
        string job_ref
        string check_ref
        int status
        int retry
        string summary
    }
    PLAN {
        string bamboo_ci_plan_name
        string github_repo_name
        string name
    }
```

> `Plan` has `pull_request_id`/`check_suite_id` foreign keys, but the PR ↔ Plan link is rebuilt on every
> event from `github_repo_name` (`Github::BuildPlan#add_plans`).

## 2. Models (ActiveRecord)

```mermaid
classDiagram
    class PullRequest {
        +finished?() bool
        +current_execution?(check_suite) bool
        +current_execution_by_plan(plan) CheckSuite
        +unique_repository_names()$ Array
    }
    class Plan
    class CheckSuite {
        +running?() bool
        +finished?() bool
        +in_progress?() bool
        +running_jobs()
        +stages_failure() Array
        +execution_started?() bool
        +last_job_updated_at_timer() Time
    }
    class Stage {
        <<enumeration>>
        +suffix() String
        +previous_stage() Stage
        +running?() bool
        +finished?() bool
        +enqueue(github, output, agent)
        +in_progress(github, output, agent)
        +success(github, output, agent)
        +failure(github, output, agent)
        +cancelled(github, output, agent)
        +update_execution_time()
    }
    class StageConfiguration
    class CiJob {
        <<enumeration>>
        +finished?() bool
        +checkout_code?() bool
        +create_check_run(agent)
        +enqueue(github, output, agent)
        +in_progress(github, output, agent)
        +success(github, output, agent)
        +failure(github, output, agent)
        +cancelled(github, output, agent)
        +skipped(github, output, agent)
        +update_execution_time()
    }
    class TopotestFailure {
        +to_h() Hash
    }
    class AuditStatus {
        <<enumeration>>
    }
    class AuditRetry
    class GithubUser
    class Organization
    class PullRequestSubscription

    PullRequest "1" --> "*" CheckSuite
    PullRequest "1" --> "*" Plan
    PullRequest "1" --> "*" PullRequestSubscription
    Plan "1" --> "*" CheckSuite
    CheckSuite "1" --> "*" Stage
    CheckSuite "1" --> "*" CiJob
    CheckSuite "1" --> "*" AuditRetry
    Stage "1" --> "*" CiJob : jobs
    Stage --> StageConfiguration : configuration
    CiJob "1" --> "*" TopotestFailure
    CiJob "*" --> "*" AuditRetry
    CiJob ..> AuditStatus : auditable
    Stage ..> AuditStatus : auditable
    GithubUser --> Organization
    GithubUser "1" --> "*" PullRequest
    GithubUser "1" --> "*" CheckSuite
```

The transition methods (`in_progress`, `success`, `failure`, `cancelled`, `skipped`, `enqueue`) on
`CiJob` and `Stage` do three things: update the GitHub Check Run (through `Github::Check`),
record an `AuditStatus`, and update the local `status`.

## 3. GitHub / orchestration layer

```mermaid
classDiagram
    class GithubApp {
        <<Sinatra::Base>>
        +routes()
    }
    class BuildPlan {
        +create()
    }
    class Build_PlanRun["Build::PlanRun"] {
        +build()
    }
    class Build_Action["Build::Action"] {
        +create_summary(rerun)
    }
    class Build_Retry["Build::Retry"] {
        +enqueued_stages()
        +enqueued_failure_tests()
    }
    class Build_Summary["Build::Summary"] {
        +build_summary()
    }
    class MessageFormatter {
        +summary_with_footer(stage, url)
        +generate_message(name, job)
    }
    class SkipOldTests {
        +skip_old_tests()
    }
    class UnavailableJobs {
        +update(new_check_suite)
    }
    class UpdateStatus {
        +update()
    }
    class PlanExecution_Finished["PlanExecution::Finished"] {
        +finished()
        +fetch_build_status()
    }
    class Retry_Base["Retry::Base"] {
        +start()
    }
    class Retry_Command["Retry::Command"]
    class Retry_Comment["Retry::Comment"]
    class ReRun_Base["ReRun::Base"]
    class ReRun_Command["ReRun::Command"] {
        +start()
    }
    class ReRun_Comment["ReRun::Comment"] {
        +start()
    }
    class Check {
        +create(name)
        +queued(ref, output)
        +in_progress(ref, output)
        +success(ref, output)
        +failure(ref, output)
        +cancelled(ref, output)
        +skipped(ref, output)
        +check_runs_for_ref(repo, sha)
        +comment_reaction_thumb_up(repo, id)
        +signature()
    }
    class UserInfo
    class RetrieveError["TopotestFailures::RetrieveError"] {
        +retrieve()
    }

    GithubApp ..> BuildPlan
    GithubApp ..> UpdateStatus
    GithubApp ..> PlanExecution_Finished
    GithubApp ..> Retry_Command
    GithubApp ..> Retry_Comment
    GithubApp ..> ReRun_Command
    GithubApp ..> ReRun_Comment
    BuildPlan ..> Build_PlanRun
    Retry_Command --|> Retry_Base
    Retry_Comment --|> Retry_Base
    ReRun_Command --|> ReRun_Base
    ReRun_Comment --|> ReRun_Base
    Retry_Base ..> Build_Retry
    Retry_Base ..> UnavailableJobs
    ReRun_Base ..> Build_Action
    ReRun_Base ..> UnavailableJobs
    Build_Action ..> SkipOldTests
    Build_Summary ..> MessageFormatter
    Build_Summary ..> PlanExecution_Finished
    PlanExecution_Finished ..> Build_Summary
    UpdateStatus ..> Check
    UpdateStatus ..> RetrieveError
    Build_Action ..> Check
    Build_Summary ..> Check
    PlanExecution_Finished ..> Check
    Retry_Base ..> UserInfo
    ReRun_Base ..> UserInfo
```

## 4. Bamboo client

```mermaid
classDiagram
    class Api {
        <<module>>
        +fetch_executions(plan)
        +get_status(id)
        +submit_pr_to_ci(check_suite, plan, vars)
        +add_comment_to_ci(key, comment)
    }
    class Request {
        <<module GitHubApp::Request>>
        +get_request(uri)
        +post_request(uri)
        +put_request(uri)
        +delete_request(uri)
    }
    class PlanRun {
        +start_plan() Integer
        +ci_variables
        +ci_key
    }
    class RunningPlan {
        +fetch(plan_key)$ Array
    }
    class StopPlan {
        +build(bamboo_ci_ref)$
        +stop(job_key)$
        +comment(check_suite, new)$
    }
    class Retry_B["BambooCi::Retry"] {
        +restart(plan_key)$
        +rerun(plan_key)$
    }
    class Result
    class Download

    Api ..> Request : include
    PlanRun ..> Api : include
    RunningPlan ..> Api : extend
    StopPlan ..> Api : extend
    Retry_B ..> Api : extend
    Result ..> Api
    Download ..> Api
```

Every call goes through `PrometheusMetrics.track_bamboo(...)`.

## 5. Workers, Slack and helpers

```mermaid
classDiagram
    class CreateExecutionByPlan {
        +create(pr_id, payload, plan_id)$
    }
    class CreateExecutionByComment {
        +create(pr_id, payload, plan)$
    }
    class CreateExecutionByCommand {
        +create(plan_id, check_suite_id, payload)$
    }
    class CiJobStatus {
        +update(bamboo_ci_ref, ci_job_id)$
    }
    class CiJobFetchTopotestFailures {
        +update(ci_job_id, count)$
    }
    class TimeoutExecution {
        +timeout(check_suite_id)$
        +watchdog(check_suite)$
    }
    class WatchDog {
        +perform()
    }
    class PrBambooSync {
        +perform()
    }
    class SlackUsername2Id {
        +fetch_id(username, slack_name)$
    }
    class SlackBot {
        <<Singleton>>
        +execution_started_notification(suite)
        +execution_finished_notification(suite)
        +stage_finished_notification(stage)
        +notify_errors(job)
        +notify_success(job)
        +notify_cancelled(job)
        +invalid_rerun_group(stage)
        +invalid_rerun_dm(stage, sub)
    }
    class Slack_Running["Slack::Running"]
    class Slack_Subscribe["Slack::Subscribe"]
    class Slack_Settings["Slack::Settings"]
    class Configuration {
        <<Singleton GitHubApp::Configuration>>
        +reload()
        +debug?()
        +multi_plan?()
        +ci_url()
    }
    class GithubLogger {
        <<Singleton>>
        +create(name, level)
    }
    class PrometheusMetrics {
        <<module>>
        +refresh!()
        +track_bamboo(name)
    }
    class Telemetry {
        <<Singleton>>
        +stats()
    }
    class ReRun_Base2["Github::ReRun::Base"]
    class Summary2["Build::Summary"]
    class Finished2["PlanExecution::Finished"]

    CreateExecutionByComment --|> ReRun_Base2
    CreateExecutionByCommand --|> ReRun_Base2
    CiJobStatus ..> Summary2
    CiJobStatus ..> Finished2
    TimeoutExecution ..> Finished2
    WatchDog ..> Finished2
    CiJobFetchTopotestFailures ..> TopotestFailure
    SlackUsername2Id ..> SlackBot
    Finished2 ..> SlackBot
    Slack_Subscribe ..> PullRequestSubscription
```

> `CreateExecutionByComment` and `CreateExecutionByCommand` inherit from `Github::ReRun::Base`
> (they cancel the previous execution and start a new suite); `CreateExecutionByPlan` is standalone
> (new/updated PR flow) and duplicates part of that logic.
