require 'spec_helper'

RSpec.describe PlaiTestr::Botrun do
  let(:tmp) { Dir.mktmpdir('botrun_spec_') }

  let(:game_class) do
    Class.new(PlaiTestr::Session::Runner) do
      def setup = data['total'] = 0

      def legal_moves(_player) = [1, 2].map { |n| option("Add #{n}", add: { value: n }) }

      def bot_choice(player, _moves, pick: nil)
        raise 'broken seed' if @seed == 13

        { 'choice' => bot_strategy_for(player)['step'], 'rule' => 'by_persona' }
      end

      def apply_action_effects(player, action)
        data['total'] += action.dig(:add, :value)
        @game_state.apply_changes('status' => { 'game_over' => true, 'winner' => player, 'end_reason' => 'race' }) if data['total'] >= 4
      end

      def botrun_stats = { 'total' => data['total'] }
    end
  end

  let(:game) do
    build_game(game_class, rules: { 'game' => { 'name' => 'Race', 'version' => '1.0' } },
                           personas: "personas:\n  fast:\n    goal: Hurry.\n  slow:\n    goal: Dawdle.\n",
                           bots: "bot_strategy: &defaults\n  step: 1\nbots:\n  fast:\n    <<: *defaults\n    step: 2\n")
  end

  before do
    PlaiTestr.games_dir    = File.join(tmp, 'games')
    PlaiTestr.sessions_dir = File.join(tmp, 'sessions')
    PlaiTestr.reports_dir  = File.join(tmp, 'reports')
  end

  after do
    PlaiTestr.games_dir = nil
    FileUtils.rm_rf(tmp)
  end

  def botrun(seeds, personas) = described_class.new(game: game, players: %w[A B], seeds: seeds, personas: personas)

  it 'plays every seed with the bot rules and writes nothing to disk' do
    results = botrun([1, 2], %w[fast slow]).run

    expect(results.map { |r| r['seed'] }).to eq([1, 2])
    expect(results.first).to include('winner' => 'A', 'end_reason' => 'race', 'personas' => { 'A' => 'fast', 'B' => 'slow' },
                                      'rules' => { 'by_persona' => 3 }, 'stats' => { 'total' => 5 })
    expect(Dir.exist?(PlaiTestr.sessions_dir)).to be false
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

  it 'refuses an unknown persona once, before playing any game' do
    expect(game_class).not_to receive(:new)

    expect { botrun([1, 2], %w[fast quick]).run }.to raise_error(PlaiTestr::PersonaError, /Unknown persona "quick"/)
  end

  it 'reports wins by persona and seat, endings, rules and crashes' do
    results = botrun([12, 13, 14], ['all']).run
    report  = PlaiTestr::Reporter::BotrunReport.new(results, game: 'Race', version: '1.0', seconds: 0.5, personas: ['all']).to_markdown

    expect(report).to include('# Botrun: Race', '| race | 2 | 100% |', '## Wins by persona', '| fast | 2 | 2 | 0 | 100% |',
                              '## Wins by seat', '| by_persona |', 'seed 13: RuntimeError: broken seed')
  end

  it 'says when a botrun was stopped early' do
    results = botrun([1, 2], %w[fast slow]).run
    report  = PlaiTestr::Reporter::BotrunReport.new(results.first(1), game: 'Race', version: '1.0', seconds: 0.5, planned: 2).to_markdown

    expect(report).to include('| **Games** | 1 of 2, stopped early (seeds 1–1) |')
  end
end
