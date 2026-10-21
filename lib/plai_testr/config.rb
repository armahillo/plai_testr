module PlaiTestr
  class Config
    MODEL_SETTINGS = {
      context_size:      8192,
      long_context_size: 16_384,
      menu_budget:       512,
      think_budget:      8192,
      debrief_budget:    1024,
      referee_budget:    2048,
      temperature:       0.6
    }.freeze

    attr_accessor :max_decisions, :ollama_host, :ollama_port, :player_model, :referee_model
    attr_reader :model_settings

    def initialize
      @max_decisions  = 100_000
      @ollama_host    = ENV.fetch('PLAI_TESTR_OLLAMA_HOST', 'localhost')
      @ollama_port    = Integer(ENV.fetch('PLAI_TESTR_OLLAMA_PORT', '11434'))
      @player_model   = ENV.fetch('PLAI_TESTR_PLAYER_MODEL', 'qwen3:8b')
      @referee_model  = ENV['PLAI_TESTR_REFEREE_MODEL']
      @model_settings = MODEL_SETTINGS.dup
    end

    def model_settings=(settings)
      @model_settings = MODEL_SETTINGS.merge(settings)
    end
  end

  def self.config = @config ||= Config.new

  def self.configure = yield(config)

  def self.reset_config! = @config = nil

  def self.load_config(path = File.join(Dir.pwd, 'config', 'plai_testr.rb'))
    Kernel.load(path) if File.exist?(path)
  end
end
