module PlaiTestr
  Game = Data.define(:name, :runner_class, :game_state_class, :players, :comparison_class, :botrun_report_class, :max_decisions, :model_settings) do
    def root         = File.join(PlaiTestr.games_dir, name)
    def data_dir     = File.join(root, 'data')
    def rules_file   = File.join(data_dir, 'rules.json')
    def sessions_dir = File.join(root, 'sessions')
    def reports_dir  = File.join(root, 'reports')
    def rules        = RulesLoader.load(rules_file)
    def personas     = Personas.load(data_dir)

    def check!
      Dir.glob('**/*.{yml,yaml}', base: data_dir).each do |file|
        YAML.safe_load_file(File.join(data_dir, file), aliases: true)
      rescue Psych::SyntaxError => e
        raise RulesError, "#{File.join(data_dir, file)}: #{e.message}"
      end
      rules
      personas.lint
    end

    def fingerprint
      files = %w[data lib].flat_map { |dir| Dir.glob(File.join(root, dir, '**', '*')) }.select { |path| File.file?(path) }.sort
      digest = Digest::SHA256.new
      digest << VERSION
      files.each { |path| digest << path.delete_prefix(root) << File.binread(path) }
      digest.hexdigest
    end
  end

  def self.register(name, runner_class:, game_state_class:, players: ['Player 1', 'Player 2'], comparison_class: Reporter::ModelComparison,
                    botrun_report_class: Reporter::BotrunReport, max_decisions: nil, model_settings: {})
    registry[name] = Game.new(name:, runner_class:, game_state_class:, players:, comparison_class:, botrun_report_class:, max_decisions:, model_settings:)
  end

  def self.load(name)
    entry = File.join(games_dir, name, 'lib', "#{name}.rb")
    raise UsageError, "Unknown game #{name.inspect}. Available: #{names.join(', ')}" unless File.exist?(entry)

    require entry
    registry.fetch(name)
  end

  def self.names
    Dir.glob('*', base: games_dir).select { |name| File.exist?(File.join(games_dir, name, 'lib', "#{name}.rb")) }.sort
  end

  def self.registry
    @registry ||= {}
  end
end
