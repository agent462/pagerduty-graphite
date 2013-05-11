#!/usr/bin/env ruby
#
# PagerDuty-Graphite
# Send Pager Duty Incident Metrics to Graphite
#
# Copyright 2013, Bryan Brandau <agent462@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'json'
require 'socket'
require 'timeout'
require 'net/https'
require 'fileutils'
require 'logger'

class PagerDuty

  def initialize
    @m = String.new
    @time = Time.new.to_i
    @opts = {
      :org => "pager_duty_org",
      :auth_token => "super_secret_auth_token",
      :carbon_host => "127.0.0.1",
      :carbon_port => 2003,
      :log_dir => "/var/log/to_graphite/log/"
    }
  end

  def logger
    dir = File.join(@opts[:log_dir])
    file = File.join(dir, "pagerduty.log")
    FileUtils.mkdir_p(dir) if !File.directory?(dir)
    log_file = File.open(file, "a+")
    @logger || @logger = Logger.new(log_file)
    @logger
  end

  def do_it
    logger
    incident_count = get_incident_count
    build_metrics("alerts.pagerduty.aggregate #{incident_count["total"]} #{@time}\n")
    process_incidents(get_incidents)
    send_metrics
  end

  def process_incidents(incidents)
    h = Hash.new(0)
    incidents["incidents"].each do |i|
      h["#{i["service"]["name"]}"] += 1 if i["status"] == "triggered" || i["status"] == "acknowledged"
    end
    h.each do |k,v|
      service = k.gsub(/\s+/, '_').gsub(/\./, '_').gsub(/[\(\)]/, '')
      build_metrics("alerts.pagerduty.#{service} #{v} #{@time}\n".downcase)
    end
  end

  def get_incident_count
    response = http_request(
        :uri  => "https://#{@opts[:org]}.pagerduty.com/api/v1/incidents/count?status=triggered,acknowledged"
      )
    JSON.parse(response.body)
  end

  def get_incidents
    response = http_request(
        :uri  => "https://#{@opts[:org]}.pagerduty.com/api/v1/incidents/"
      )
    JSON.parse(response.body)
  end

  def http_request(options={})
    uri = URI.parse(options[:uri])
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 15
    http.open_timeout = 5
    http.use_ssl = true
    req = Net::HTTP::Get.new(uri.request_uri)
    req['Authorization'] = "Token token=#{@opts[:auth_token]}"
    http.request(req)
  end

  def build_metrics(m)
    @m << m
  end

  def send_metrics
    carbon = {
      :host => @opts[:carbon_host],
      :port => @opts[:carbon_port]
    }
    begin
      timeout(2) do #the graphite server has two seconds to respond
        s = TCPSocket.new(carbon[:host], carbon[:port])
        s.write(@m)
        s.close
        @logger.info("Metrics sent to Graphite #{@time}")
        @logger.info(@m)
      end
    rescue Exception => e
      @logger.info(e)
    end
  end

end
t = PagerDuty.new
t.do_it
