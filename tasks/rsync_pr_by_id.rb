#   SPDX-License-Identifier: BSD-2-Clause
#
#   rsync_pr_by_id.rb
#   Part of NetDEF CI System
#
#   Copyright (c) 2025 by
#   Network Device Education Foundation, Inc. ("NetDEF")
#
#   frozen_string_literal: true

require_relative 'sync_pr_outdated'

sync = SyncPROutdated.new()

if ARGV.size != 1
  puts 'Usage: ruby tasks/rsync_pr_by_id.rb <github_pr_id>'
  exit 1
end

sync.single_pr(ARGV[0])
