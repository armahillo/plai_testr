require 'fileutils'
require 'json'
require 'net/http'
require 'securerandom'
require 'time'
require 'uri'

module Testr
  ROOT        = File.expand_path('../..', __FILE__)
  SESSIONS_DIR = File.join(ROOT, 'sessions')
  REPORTS_DIR  = File.join(ROOT, 'reports')
  RULES_DIR    = File.join(ROOT, 'rules')
end

require_relative 'testr/agents/ollama_client'
require_relative 'testr/agents/player_agent'
require_relative 'testr/agents/referee_agent'
require_relative 'testr/compiler/rules_loader'
require_relative 'testr/random/engine'
require_relative 'testr/reporter/report_builder'
require_relative 'testr/session/manager'
require_relative 'testr/session/runner'
require_relative 'testr/state/game_state'
