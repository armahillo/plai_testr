require_relative 'plai_testr/version'
require 'digest'
require 'fileutils'
require 'json'
require 'net/http'
require 'optparse'
require 'socket'
require 'stringio'
require 'time'
require 'uri'

module PlaiTestr
  DECIDER_ICONS = { 'LLM' => '🧠', 'BOT' => '🤖', 'RNG' => '🎲' }.freeze

  class << self
    attr_writer :sessions_dir, :reports_dir

    def sessions_dir
      @sessions_dir || File.join(Dir.pwd, 'sessions')
    end

    def reports_dir
      @reports_dir || File.join(Dir.pwd, 'reports')
    end

    def games_dir
      @games_dir || File.join(Dir.pwd, 'games')
    end

    def games_dir=(dir)
      @games_dir = dir && File.expand_path(dir)
    end
  end
end

require_relative 'plai_testr/errors'
require_relative 'plai_testr/config'
require_relative 'plai_testr/model_settings'
require_relative 'plai_testr/agents/ollama_client'
require_relative 'plai_testr/agents/player_agent'
require_relative 'plai_testr/agents/referee_agent'
require_relative 'plai_testr/rules_loader'
require_relative 'plai_testr/personas'
require_relative 'plai_testr/reporter/think_log'
require_relative 'plai_testr/reporter/report_builder'
require_relative 'plai_testr/reporter/model_comparison'
require_relative 'plai_testr/reporter/botrun_report'
require_relative 'plai_testr/session/manager'
require_relative 'plai_testr/session/frame_queue'
require_relative 'plai_testr/session/runner'
require_relative 'plai_testr/state/base'
require_relative 'plai_testr/state/player_state'
require_relative 'plai_testr/state/game_state'
require_relative 'plai_testr/botrun'
require_relative 'plai_testr/preflight'
require_relative 'plai_testr/game'
require_relative 'plai_testr/deck'
require_relative 'plai_testr/event_log'
require_relative 'plai_testr/names'
require_relative 'plai_testr/generator'
require_relative 'plai_testr/cli'
