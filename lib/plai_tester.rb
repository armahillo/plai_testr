require_relative 'version'
require 'fileutils'
require 'json'
require 'net/http'
require 'securerandom'
require 'time'
require 'uri'

module PlaiTester
  ROOT        = File.expand_path('../..', __FILE__)
  SESSIONS_DIR = File.join(ROOT, 'sessions')
  REPORTS_DIR  = File.join(ROOT, 'reports')
  RULES_DIR    = File.join(ROOT, 'rules')
end

require_relative 'plai_tester/protocol'
require_relative 'plai_tester/agents/ollama_client'
require_relative 'plai_tester/agents/player_agent'
require_relative 'plai_tester/agents/referee_agent'
require_relative 'plai_tester/compiler/rules_loader'
require_relative 'plai_tester/random/engine'
require_relative 'plai_tester/reporter/report_builder'
require_relative 'plai_tester/session/manager'
require_relative 'plai_tester/session/runner'
require_relative 'plai_tester/state/base'
require_relative 'plai_tester/state/player_state'
require_relative 'plai_tester/state/game_state'
