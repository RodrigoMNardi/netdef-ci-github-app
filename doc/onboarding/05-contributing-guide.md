# 05 — Contributing guide

Complements [`AGENTS.md`](../../AGENTS.md), which is the reference for conventions.

## Essential conventions

- **Required header** in every Ruby file (SPDX, file name, copyright with the year, `frozen_string_literal: true`).
- Methods ≤ 20 lines, classes ≤ 200 lines (Rubocop). Extract private helpers or submodules.
- Namespaces by domain (`BambooCi::`, `Github::`, `SlackBot`); `snake_case` file mirroring the class name.
- Routes in `app/github_app.rb` only instantiate and delegate; slow external calls go to a worker.
- Workers are plain classes in `workers/`, enqueued with `.delay(queue:, run_at:)`, and delegate to `lib/`.
- Configuration only through `GitHubApp::Configuration.instance`; logs through `GithubLogger`; no `puts`/`p` in new code.
- Always use the symbol form for statuses (`ci_job.success?`, `where(status: :failure)`).

## Recipes

### New GitHub event type
1. Add a `when` in `POST /*` (`app/github_app.rb`) that delegates to a class in `lib/github/`.
2. Implement the class returning `[http_status, message]`.
3. Add a spec in `spec/lib/github/...` and, if you touch the route, in `spec/app/github_app_spec.rb`.

### New comment command (e.g. `ci:foo`)
1. Add `when /ci:foo/` to the `issue_comment` `case`.
2. Create `Github::Foo::Comment` following `Retry::Base`/`ReRun::Base` (👍/👎 reaction through `Github::Check`).

### New column / table
1. Create a migration in `db/migrate/` (numbered timestamp). **Do not edit `db/schema.rb` by hand.**
2. Declare associations at the top of the model, then enum/validations/scopes.
3. Create/update the factory in `spec/factories/` and run `rake db:migrate:reset`.

### New CI stage
Stages are data, not code: create a `StageConfiguration` record
(`bamboo_stage_name`, `github_check_run_name`, `position`, `mandatory`, `can_retry`, `start_in_progress`).
A `mandatory` stage that fails cancels the stages with a higher `position`.

### New worker
File in `workers/`, `require` it in `lib/github_ci_app.rb`, enqueue it with `.delay`. Use queues 0–9
(or the existing named ones — see the warning in [01](01-overview.md#delayed-job-queues)).
Max 5 attempts, 5 min timeout per job.

### New metric
Look in `lib/helpers/prometheus_metrics/metrics_definitions.rb` first; only then define a new one.

## Debugging — where to start

| Symptom | Where to look |
|---------|---------------|
| Check stuck on "in progress" | `logs/pr<N>.log`, `github_plan_execution_finished.log`; run `Github::PlanExecution::Finished.new({'bamboo_ref' => ref}).finished` in `bin/console` |
| Webhook returns 401/404 | `auth_signature.password` in `config.yml`; the `X-Hub-Signature-256` header |
| Plan does not trigger | `github_plan_run.log`; Bamboo response (429 = concurrent build limit reached) |
| Job does not run | `delayed_jobs` table (`last_error`, `attempts`), `delayed_job.log`, correct queue |
| Retry refused (406) | suite still `running?`; see `Github::Retry::Base#start` |
| Missing test failures | `CiJobFetchTopotestFailures` reschedules up to 4 times (5/10/15/20 min) |

## Known pitfalls

- The Bamboo URL for REST calls is hardcoded to `https://127.0.0.1` in `lib/bamboo_ci/*` and
  `Github::PlanExecution::Finished` (assumes a local tunnel/proxy); only the link shown to users uses `ci_url` from the configuration.
- `Github::Build::Summary` and `PlanExecution::Finished` reference each other (the former calls
  `Finished#fetch_build_status`; the latter calls `Summary#build_summary`). Beware of recursion when changing them.
- `CheckSuite`, `CiJob` and `Stage` use a `default_scope` ordered by `id`; `.last` and `.first` depend on it.
- `PullRequest#plans` is reassigned on every event from `Plan.github_repo_name`.
- Multi-plan: check names get a ` - <plan>` suffix when `multi_plan?` is enabled and the PR has more than one plan
  (`Build::Action#stage_name`, `Stage#suffix`).
- `workers/single_sync.rb` cannot load (missing `workers/base.rb`) and `PrBambooSync#process_pr` references an undefined
  `pr` variable. Fix them before relying on those scripts.
- Do not stub `Time.now` globally; do not use ActiveJob; do not create queues outside 0–9 without updating `config.ru`.

## Checklist before opening a PR

```bash
bundle exec rubocop        # zero offenses
bundle exec rspec          # ≥ 90% branch coverage
rake db:migrate:reset      # migrations apply from scratch
```

- [ ] Header + `frozen_string_literal` on new files
- [ ] Logic in `lib/`, not in `app/`, `workers/` or models
- [ ] Specs mirroring the path, with WebMock for every HTTP call
- [ ] No manual changes to `db/schema.rb`
