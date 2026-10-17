module PlaiTester
  Game = Data.define(:name, :runner_class, :game_state_class, :players, :comparison_class, :botrun_report_class) do
    def root         = File.join(PlaiTester.games_dir, name)
    def rules_file   = File.join(root, 'data', 'rules.json')
    def sessions_dir = File.join(root, 'sessions')
    def reports_dir  = File.join(root, 'reports')
  end

  def self.register(name, runner_class:, game_state_class:, players: ['Player 1', 'Player 2'],
                    comparison_class: Reporter::ModelComparison, botrun_report_class: Reporter::BotrunReport)
    registry[name] = Game.new(name:, runner_class:, game_state_class:, players:, comparison_class:, botrun_report_class:)
  end

  def self.load(name)
    entry = File.join(games_dir, name, 'lib', "#{name}.rb")
    raise ArgumentError, "Unknown game #{name.inspect}. Available: #{names.join(', ')}" unless File.exist?(entry)

    require entry
    registry.fetch(name)
  end

  def self.names
    Dir.children(games_dir).select { |name| File.exist?(File.join(games_dir, name, 'lib', "#{name}.rb")) }.sort
  end

  def self.registry
    @registry ||= {}
  end
end
