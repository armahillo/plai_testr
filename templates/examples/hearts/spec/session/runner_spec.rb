require 'spec_helper'
require 'stringio'

RSpec.describe Hearts::Session::Runner do
  let(:game)    { PlaiTester.load('hearts') }
  let(:rules)   { PlaiTester::Compiler::RulesLoader.load(game.rules_file) }
  let(:runner)  { described_class.new(rules: rules, players: game.players, models: {}, game_state_class: game.game_state_class, seed: 1, mode: 'bot', persist: false) }
  let(:state)   { runner.instance_variable_get(:@game_state) }
  let(:deck)    { PlaiTester::Deck.build(rules) }

  def quietly
    original = $stdout
    $stdout  = StringIO.new
    yield
  ensure
    $stdout = original
  end

  def cards(*names) = names.map { |name| deck.find { |c| c['name'] == name } }

  def give(player, *names) = state.player_state(player).hand.replace(cards(*names))

  def labels(player) = runner.send(:legal_moves, player).map { |m| m['label'] }

  before { quietly { runner.send(:setup) } }

  it 'deals the whole deck, 13 cards each' do
    hands = game.players.map { |p| state.player_state(p).hand }

    expect(hands.map(&:length)).to all(eq(13))
    expect(hands.flatten.map { |c| c['uid'] }.uniq.length).to eq(52)
  end

  it 'passes 3 cards to the left on the first hand, then starts with the 2♣' do
    passed = game.players.to_h { |p| [p, state.player_state(p).hand.first(3)] }
    game.players.each { |p| runner.send(:apply_action_effects, p, { 'action' => 'pass', 'parameters' => { 'values' => passed[p].map { |c| c['uid'] } } }) }

    expect(state.player_state('Player 2').hand).to include(*passed['Player 1'])
    expect(state.player_state(state.active).hand.map { |c| c['name'] }).to include('2♣')
    expect(labels(state.active)).to eq(['Play 2♣'])
  end

  context 'during tricks' do
    before { state.custom.merge!('step' => 'play', 'tricks' => 1, 'trick' => [], 'active' => 'Player 1') }

    it 'does not lead hearts until they are broken' do
      give('Player 1', '5♥', '9♣')

      expect(labels('Player 1')).to eq(['Play 9♣'])
    end

    it 'follows the suit led when it can' do
      give('Player 2', '5♥', '9♣', 'K♣')
      state.custom['trick'] = [{ 'player' => 'Player 1', 'card' => cards('2♣').first }]

      expect(labels('Player 2')).to eq(['Play 9♣', 'Play K♣'])
    end

    it 'keeps points off the first trick unless there is nothing else' do
      state.custom.merge!('tricks' => 0, 'trick' => [{ 'player' => 'Player 1', 'card' => cards('2♣').first }])
      give('Player 2', 'Q♠', '5♥', '9♦')

      expect(labels('Player 2')).to eq(['Play 9♦'])
    end
  end

  it 'scores 26 to everyone else when a player shoots the moon' do
    state.custom['taken'] = { 'Player 1' => deck.select { |c| Hearts.points(c).positive? }, 'Player 2' => [], 'Player 3' => [], 'Player 4' => [] }
    quietly { runner.send(:score_hand) }

    expect(state.scores).to eq('Player 1' => 0, 'Player 2' => 26, 'Player 3' => 26, 'Player 4' => 26)
  end

  it 'counts hearts, the Q♠ and moons in the session report' do
    state.custom['taken'] = { 'Player 1' => cards('Q♠', '5♥'), 'Player 2' => cards('2♥'), 'Player 3' => [], 'Player 4' => [] }
    quietly { runner.send(:score_hand) }

    expect(runner.send(:report_sections).first).to include('| Player 1 | 14 | 1 | 1 | 0 |', '| Player 2 | 1 | 1 | 0 | 0 |')
  end

  it 'plays whole games with its bot rules and reports penalties by seat' do
    results = PlaiTester::Botrun.new(runner_class: described_class, game_state_class: game.game_state_class, rules: rules,
                                     players: game.players, seeds: (1..20).to_a).run
    report  = game.botrun_report_class.new(results, game: 'Hearts', version: '1.0.0', seconds: 1.0).to_markdown

    expect(results.map { |r| r['error'] }.compact).to be_empty
    expect(results.map { |r| r['winner'] }).to all(start_with('Player'))
    expect(report).to include('## Hands per game', '## Penalties by seat')
  end
end
