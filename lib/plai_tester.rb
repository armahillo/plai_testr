require_relative 'version'
require 'fileutils'
require 'json'
require 'net/http'
require 'optparse'
require 'socket'
require 'stringio'
require 'time'
require 'uri'

module PlaiTester
  class << self
    attr_writer :sessions_dir, :reports_dir, :rules_dir, :games_dir

    def sessions_dir
      @sessions_dir || File.join(Dir.pwd, 'sessions')
    end

    def reports_dir
      @reports_dir || File.join(Dir.pwd, 'reports')
    end

    def rules_dir
      @rules_dir || File.join(Dir.pwd, 'rules')
    end

    def games_dir
      @games_dir || File.join(Dir.pwd, 'games')
    end
  end
end

require_relative 'plai_tester/agents/ollama_client'
require_relative 'plai_tester/agents/player_agent'
require_relative 'plai_tester/agents/referee_agent'
require_relative 'plai_tester/compiler/rules_loader'
require_relative 'plai_tester/reporter/think_log'
require_relative 'plai_tester/reporter/report_builder'
require_relative 'plai_tester/reporter/model_comparison'
require_relative 'plai_tester/reporter/botrun_report'
require_relative 'plai_tester/session/manager'
require_relative 'plai_tester/session/frame_queue'
require_relative 'plai_tester/session/runner'
require_relative 'plai_tester/state/base'
require_relative 'plai_tester/state/player_state'
require_relative 'plai_tester/state/game_state'
require_relative 'plai_tester/botrun'
require_relative 'plai_tester/game'
require_relative 'plai_tester/deck'
require_relative 'plai_tester/event_log'
require_relative 'plai_tester/names'
require_relative 'plai_tester/cli'
