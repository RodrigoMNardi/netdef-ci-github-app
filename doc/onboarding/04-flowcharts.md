# 04 — Flowcharts and sequences

## 1. Webhook routing (`POST /*`)

```mermaid
flowchart TD
    A([GitHub webhook]) --> B[Validate HMAC<br/>authenticate_request]
    B -- invalid --> X1[401 / 404]
    B -- ok --> C{X-GitHub-Event}
    C -- ping --> P[200 PONG!]
    C -- pull_request --> D[Github::BuildPlan#create]
    C -- check_run --> E{action = rerequested?}
    E -- no --> OK1[200 OK]
    E -- yes --> F[Github::Retry::Command#start]
    C -- issue_comment --> G{comment body}
    G -- "ci:retry" --> H[Github::Retry::Comment#start]
    G -- "ci:rerun" --> I[Github::ReRun::Comment#start]
    G -- other --> OK2[200 Just a comment]
    C -- check_suite --> J{action = rerequested?}
    J -- no --> OK3[200 OK]
    J -- yes --> K[Github::ReRun::Command#start]
    C -- installation --> L[202 Updated]
    C -- unknown --> X2[401 Invalid request]
```

## 2. PR opened / updated → Bamboo execution

```mermaid
flowchart TD
    A([pull_request: opened / synchronize / reopened]) --> B[BuildPlan: find_or_create PullRequest<br/>+ UserInfo, attach the repository's Plans]
    B --> C{PR has Plans?}
    C -- no --> X[422 No Plans associated]
    C -- yes --> D["For each Plan: enqueue CreateExecutionByPlan<br/>(+5 s, queue create_execution_by_plan)"]
    D --> R[[200 Scheduled Plan Runs]]
    D --> W

    subgraph W [CreateExecutionByPlan worker]
        W1[Find last CheckSuite for PR/plan] --> W2[Create CheckSuite + Github::Check]
        W2 --> W3{Previous suite still running?}
        W3 -- yes --> W4[Cancel pending jobs/stages<br/>StopPlan.build + comment in Bamboo]
        W3 -- no --> W5
        W4 --> W5[BambooCi::PlanRun#start_plan<br/>queue with github_* variables]
        W5 --> W6{HTTP 200/201?}
        W6 -- no --> WE["Status 4xx/429/418 → 'Failed to create CI Plan'"]
        W6 -- yes --> W7[Save bamboo_ci_ref + comment in Bamboo]
        W7 --> W8[Slack: execution started]
        W8 --> W9[RunningPlan.fetch → job list]
        W9 --> W10["Build::Action#create_summary<br/>SkipOldTests → one Stage per StageConfiguration (queued)<br/>→ CiJob + Check Run → TimeoutExecution in 30 min"]
    end
```

## 3. Bamboo status callback (`POST /update/status`)

```mermaid
flowchart TD
    A([Bamboo: job status]) --> B[Validate HMAC]
    B --> C{status == finished?}
    C -- yes --> F[PlanExecution::Finished#finished]
    C -- no --> D[UpdateStatus#update]
    D --> E{CiJob exists?}
    E -- no --> E404[404 CI JOB not found]
    E -- yes --> G{Valid transition?}
    G -- "queued without in_progress<br/>or in_progress without success/failure" --> G304[304 Not Modified]
    G -- yes --> H{status}
    H -- in_progress --> H1[CiJob#in_progress → Check Run]
    H -- success --> H2[CiJob#success + execution time]
    H -- failure/other --> H3[CiJob#failure + Topotest failures<br/>or schedule CiJobFetchTopotestFailures in 5 min]
    H1 & H2 & H3 --> I{Suite is the PR's current execution?}
    I -- no --> OK[200 Success]
    I -- yes --> J["Remove pending CiJobStatus (queue pr_id % 10)<br/>and schedule a new one in 30 s (debounce)"]
    J --> OK
```

The *debounce* avoids recomputing the stage summary for every job: only the last callback within 30 s runs
`CiJobStatus.update`.

## 4. Stage summary update (`Build::Summary#build_summary`)

```mermaid
flowchart TD
    A([CiJobStatus.update]) --> B[Summary#build_summary]
    B --> C{Current stage cancelled?}
    C -- yes --> END([end])
    C -- no --> D["update_summary:<br/>stage → in_progress + formatted output (MessageFormatter)"]
    D --> E{Job still in_progress<br/>or stage running?}
    E -- yes --> G
    E -- no --> F{Any job failure/cancelled/skipped?}
    F -- yes --> F1[Stage failure + time]
    F -- no --> F2[Stage success + time]
    F1 & F2 --> G
    G{Stage failed and mandatory?} -- yes --> G1[Cancel following stages<br/>and their jobs]
    G -- no --> H
    G1 --> H
    H{Stage finished successfully?} -- yes --> H1[Update next stage summary]
    H -- no --> I
    H1 --> I
    I[must_update_previous_stage:<br/>finalize earlier stages stuck in queued/in_progress]
    I --> J{CiJob.finished?}
    J -- yes --> K[PlanExecution::Finished#finished]
    J -- no --> END
```

## 5. End-of-execution reconciliation (`PlanExecution::Finished`)

Called by `CiJobStatus`, the `finished` callback, `WatchDog` and `TimeoutExecution`.

```mermaid
flowchart TD
    A([Finished#finished]) --> B{CheckSuite found?}
    B -- no --> X[404]
    B -- yes --> C[GET result + status from Bamboo]
    C --> D{Still running?<br/>currentStage ≠ Final}
    D -- "yes and not 'hanged'" --> S[200 Still running]
    D -- "no / stopped / hanged / progress ≥ 2.0" --> E[check_stages: for each Bamboo job<br/>still open in the DB, apply Successful/Failed/Unknown<br/>agent = WatchDog + Slack notification]
    E --> F[clear_deleted_jobs:<br/>remaining queued/in_progress → skipped]
    F --> G[update_all_stages:<br/>Summary starting from the last stage]
    G --> H{PR's current execution and suite finished?}
    H -- yes --> I[Slack: execution finished]
    H -- no --> J
    I --> J[200 Finished]
```

## 6. Timeout and WatchDog

```mermaid
flowchart TD
    subgraph TimeoutExecution
      T0([+30 min after suite creation]) --> T1{Suite finished?}
      T1 -- yes --> T9([end])
      T1 -- no --> T2{Last job update > 2 h ago?}
      T2 -- yes --> T3[CI_TIMEOUTS++ and Finished hanged=true]
      T2 -- no --> T4[Reschedule in +30 min]
    end
    subgraph WatchDog [WatchDog — cron]
      W0([cron]) --> W1[Suites with queued/in_progress stages]
      W1 --> W2[Finished#finished for each one]
    end
```

## 7. Stage / CiJob state machine

(Summary — full version in [`doc/ci/ci.md`](../ci/ci.md).)

```mermaid
stateDiagram-v2
    [*] --> queued
    queued --> in_progress: Bamboo started
    queued --> skipped: prerequisite failed / job removed
    in_progress --> success
    in_progress --> failure
    in_progress --> cancelled: new execution / previous stage failed
    queued --> cancelled
    failure --> queued: retry or re-run
    success --> queued: rerun
    cancelled --> queued: rerun
    skipped --> queued: rerun
```

## 8. `ci:retry` vs. `ci:rerun`

```mermaid
flowchart TD
    subgraph RETRY [Retry — same CheckSuite]
      R0([ci:retry or check_run re-request]) --> R1{Stage found?}
      R1 -- no --> R404[404]
      R1 -- yes --> R2{Stage queued/in_progress?}
      R2 -- yes --> R406[406 already enqueued]
      R2 -- no --> R3{Suite running?}
      R3 -- yes --> R4[406 + Slack 'invalid rerun'<br/>stage goes back to failure]
      R3 -- no --> R5[retry += 1, partial AuditRetry<br/>enqueue non-success stages/jobs that can retry]
      R5 --> R6[BambooCi::Retry.restart<br/>+ UnavailableJobs + Slack started]
    end
    subgraph RERUN [Rerun — new CheckSuite]
      U0([ci:rerun or check_suite re-request]) --> U1[Resolve PR / suite and plans]
      U1 --> U2[Enqueue CreateExecutionByComment / ByCommand<br/>per Plan, +1 s]
      U2 --> U3[Stop previous execution<br/>StopPlan.build + cancel jobs]
      U3 --> U4[New CheckSuite + BambooCi::PlanRun<br/>full AuditRetry]
      U4 --> U5[Build::Action#create_summary rerun: true<br/>+ UnavailableJobs → skipped on old ones]
    end
```

## 9. Full sequence — a PR's happy path

```mermaid
sequenceDiagram
    autonumber
    participant GH as GitHub
    participant APP as GithubApp (Sinatra)
    participant DJ as Delayed Job
    participant DB as PostgreSQL
    participant B as Bamboo
    participant SL as Slack

    GH->>APP: pull_request (opened/synchronize)
    APP->>DB: find_or_create PullRequest, Plans
    APP->>DJ: CreateExecutionByPlan (+5 s)
    APP-->>GH: 200 Scheduled Plan Runs
    DJ->>DB: CheckSuite
    DJ->>B: queue plan (github_* variables)
    B-->>DJ: buildResultKey
    DJ->>SL: execution started
    DJ->>B: RunningPlan.fetch
    DJ->>GH: create Check Runs (stages and jobs)
    DJ->>DB: Stage, CiJob, TimeoutExecution (+30 min)

    loop for each job
        B->>APP: POST /update/status (in_progress / success / failure)
        APP->>GH: update the job's Check Run
        APP->>DB: status + AuditStatus
        APP->>DJ: CiJobStatus (+30 s, debounce)
    end

    DJ->>GH: Summary: update the stage's Check Run
    DJ->>B: Finished: plan status
    DJ->>GH: final stages
    DJ->>SL: execution finished
```
