#   SPDX-License-Identifier: BSD-2-Clause
#
#   rsync_prs_by_date.rb
#   Part of NetDEF CI System
#
#   Copyright (c) 2025 by
#   Network Device Education Foundation, Inc. ("NetDEF")
#
#   frozen_string_literal: true

require_relative 'sync_pr_outdated'

sync = SyncPROutdated.new(last_days: ARGV[0] || 5)
sync.run
