#  SPDX-License-Identifier: BSD-2-Clause
#
#  base.rb
#  Part of NetDEF CI System
#
#  Copyright (c) 2023 by
#  Network Device Education Foundation, Inc. ("NetDEF")
#
#  frozen_string_literal: true

require 'logger'
require_relative '../database_loader'
require_relative '../lib/bamboo_ci/api'
require_relative '../lib/github/check'
require_relative '../lib/helpers/configuration'

class Base
  include BambooCi::Api

  def fetch_ci_execution(check_suite)
    @result = get_status(check_suite.bamboo_ci_ref)
  end

  def check_stages(&block)
    @result.dig('stages', 'stage').each do |stage|
      stage.dig('results', 'result').each do |result|
        yield result if block_given?
      end
    end
  end
end
