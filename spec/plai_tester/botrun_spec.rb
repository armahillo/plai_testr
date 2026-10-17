require 'spec_helper'

RSpec.describe PlaiTester::Botrun do
  let(:tmp) { Dir.mktmpdir('botrun_spec_') }
  let(:rules) do
    path = File.join(tmp, 'rules.json')
    File.write(path, JSON.generate('game' => { 'name' => 'Race', 'version' => '1.0' }))
    PlaiTester::Compiler::RulesLoader.load(path)
  end

  let(:game_class) do
    Class.new(PlaiTester::Session::Runner) do
      def self.persona_names = %w[fast slow]

      private

      def setup
        @game_state.apply_changes('custom' => { 'personas' => @game_state.players.zip(Array(@persona_request).cycle).to_h, 'total' => 0 })
      end

      def legal_moves(_player) = [1, 2].map { |n| { 'label' => "Add #{n}", 'action' => { 'action' => 'add', 'parameters' => { 'n' => n } } } }

      def scripted_choice(player, _moves, pick: nil)
        raise 'broken seed' if @seed == 13

        { 'choice' => @game_state.custom.dig('personas', player) == 'fast' ? 2 : 1, 'rule' => 'by_persona' }
      end

      def apply_action_effects(player, action)
        @game_state.custom['total'] += action.dig('parameters', 'n')
        @game_state.apply_changes('flags' => { 'game_over' => true, 'winner' => player, 'end_reason' => 'race' }) if @game_state.custom['total'] >= 4
      end

      def botrun_stats = { 'total' => @game_state.custom['total'] }
    end
  end

  before do
    PlaiTester.sessions_dir = File.join(tmp, 'sessions')
    PlaiTester.reports_dir  = File.join(tmp, 'reports')
  end

  after { FileUtils.rm_rf(tmp) }

  def botrun(seeds, personas) = described_class.new(runner_class: game_class, game_state_class: PlaiTester::State::GameState, rules: rules,
                                                    players: %w[A B], seeds: seeds, personas: personas)

  it 'plays every seed with the bot rules and writes nothing to disk' do
    results = botrun([1, 2], %w[fast slow]).run

    expect(results.map { |r| r['seed'] }).to eq([1, 2])
    expect(results.first).to include('winner' => 'A', 'end_reason' => 'race', 'personas' => { 'A' => 'fast', 'B' => 'slow' },
                                      'rules' => { 'by_persona' => 3 }, 'stats' => { 'total' => 5 })
    expect(Dir.exist?(PlaiTester.sessions_dir)).to be false
  end

  it 'cycles every persona pairing, both seats, with --personas all' do
    personas = botrun([1, 2, 3], ['all']).run.map { |r| r['personas'].values }

    expect(personas).to eq([%w[fast slow], %w[slow fast], %w[fast slow]])
  end

  it 'records a crashed game and carries on' do
    results = botrun([12, 13, 14], %w[fast slow]).run

    expect(results[1]).to include('seed' => 13, 'error' => 'RuntimeError: broken seed')
    expect(results[2]).to include('winner' => 'A')
  end

  it 'reports wins by persona and seat, endings, rules and crashes' do
    results = botrun([12, 13, 14], ['all']).run
    report  = PlaiTester::Reporter::BotrunReport.new(results, game: 'Race', version: '1.0', seconds: 0.5, personas: ['all']).to_markdown

    expect(report).to include('# Botrun: Race', '| race | 2 | 100% |', '## Wins by persona', '| fast | 2 | 2 | 0 | 100% |',
                              '## Wins by seat', '| by_persona |', 'seed 13: RuntimeError: broken seed')
  end
end
