#  SPDX-License-Identifier: BSD-2-Clause
#
#  config.ru
#  Part of NetDEF CI System
#
#  Copyright (c) 2023 by
#  Network Device Education Foundation, Inc. ("NetDEF")
#
#  frozen_string_literal: true

require 'rack'
require 'rackup'
require 'rack/handler/puma'
require 'rack/session/cookie'
require 'securerandom'

require 'yabeda/prometheus'
require 'yabeda/puma/plugin'
require 'yabeda/delayed_job'
require 'yabeda/http_requests'

require_relative 'app/github_app'
require_relative 'config/delayed_job'

File.write('.session.key', SecureRandom.hex(32))

pids = []
pids << spawn("RACK_ENV=#{ENV.fetch('RACK_ENV', 'development')} rake jobs:work QUEUES=0,1,2,3")
pids << spawn("RACK_ENV=#{ENV.fetch('RACK_ENV', 'development')} rake jobs:work QUEUES=4,5,6")
pids << spawn("RACK_ENV=#{ENV.fetch('RACK_ENV', 'development')} rake jobs:work QUEUES=7,8,9")

use Rack::Session::Cookie, secret: File.read('.session.key'), same_site: true, max_age: 86_400

Yabeda.configure!

if defined?(Rack::Lint) && respond_to?(:middleware)
  begin
    middleware.reject! { |m, *_| m == Rack::Lint }
  rescue StandardError
    nil
  end
end

module Yabeda
  module Prometheus
    class Exporter
      alias orig_call call
      def call(env)
        status, headers, body = orig_call(env)
        # Corrige o header para minúsculo se necessário
        headers['content-type'] = headers.delete('Content-Type') if headers.key?('Content-Type')
        [status, headers, body]
      end
    end
  end
end

run Rack::URLMap.new(
  '/' => GithubApp,
  '/metrics' => Yabeda::Prometheus::Exporter
)
