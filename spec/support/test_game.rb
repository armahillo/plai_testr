module TestGame
  def build_game(runner_class, name: 'counting', rules: { 'game' => { 'name' => 'Counting Game', 'version' => '1.0' } },
                 personas: nil, bots: nil, **options)
    data = File.join(PlaiTestr.games_dir, name, 'data')
    FileUtils.mkdir_p(data)
    File.write(File.join(data, 'rules.json'), JSON.generate(rules))
    File.write(File.join(data, 'personas.yml'), personas) if personas
    File.write(File.join(data, 'bots.yml'), bots) if bots

    PlaiTestr::Game.new(name: name, runner_class: runner_class, game_state_class: PlaiTestr::State::GameState, players: ['Alice', 'Bob'],
                        comparison_class: PlaiTestr::Reporter::ModelComparison, botrun_report_class: PlaiTestr::Reporter::BotrunReport,
                        max_decisions: nil, model_settings: {}, **options)
  end
end
