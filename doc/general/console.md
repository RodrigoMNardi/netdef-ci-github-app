# Introduction

This document explains how to access the console (IRB) and perform some basic routines.

# Usage

Access the project root and run the following command:

`bin/console <env>`

By default, the production environment is accessed.

Example: `bin/console`

If you want to access the development environment, just run the command: `bin/console development`

The console loads the application and Delayed Job configuration (`config/setup` and `config/delayed_job`).
It also defines helper commands to manage organizations and GitHub/Slack users (`find_organization`,
`create_organization`, `edit_organization`, `find_github_user`, `add_user_in_organization`,
`remove_user_from_organization`, `add_github_user_slack_user`). They are described in the `Console`
section of the [README](../../README.md).

# Query

After accessing the terminal, you will have access to all database models and can perform queries 
using ActiveRecord terminologies.

Example:

It will search for the PullRequest object with ID 2 on GitHub example: https://github.com/opensourcerouting/frr-ci-test/pull/2
`pr = PullRequest.find_by(github_pr_id: 2)`

The line below can fetch all check_suites for the PR.
`pr.check_suites`

We are looking for the latest test suite for this PR
`check_suite = pr.check_suites.last`

The next command allows you to list the jobs that were executed in the suite
`check_suite.ci_jobs`

The .where command allows you to refine the query to search for a certain value in the case we are looking 
for a test with the name "TopoTests Debian 10 amd64 Part 1"
`check_suite.ci_jobs.where(job_ref: 'TopoTests Debian 10 amd64 Part 1')`

# Require

The console already loads the main project classes (models, `Github::*`, `BambooCi::*`, workers).
If you need a class that is not loaded, require it explicitly, for example:
`require_relative 'lib/github/check.rb'`

This will load the Github::Check class which allows you to send information to GitHub.