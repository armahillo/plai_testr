require 'spec_helper'
require 'stringio'

RSpec.describe GinRummy::Session::Runner do
  let(:game)   { PlaiTester.load('gin_rummy') }
  let(:rules)  { PlaiTester::Compiler::RulesLoader.load(game.rules_file) }
  let(:runner) { described_class.new(rules: rules, players: game.players, models: {}, game_state_class: game.game_state_class, seed: 1, mode: 'bot', persist: false) }
  let(:state)  { runner.instance_variable_get(:@game_state) }
  let(:deck)   { PlaiTester::Deck.build(rules) }

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

  it 'deals 10 cards each and turns up one card; the non-dealer starts' do
    expect(game.players.map { |p| state.player_state(p).hand.length }).to eq([10, 10])
    expect(state.discard_pile.length).to eq(1)
    expect(state.stock.length).to eq(31)
    expect(state.active).to eq('Player 1')
  end

  it 'does not let a player discard the card they just took from the discard pile' do
    taken = state.discard_pile.last['name']
    runner.send(:apply_action_effects, 'Player 1', { 'action' => 'draw', 'parameters' => { 'source' => 'discard' } })

    expect(labels('Player 1').grep(/#{taken}/)).to be_empty
  end

  it 'offers a knock only when the deadwood after discarding is 10 or less' do
    give('Player 1', 'A♣', '2♣', '3♣', '7♦', '7♥', '7♠', 'J♠', 'Q♠', 'K♠', '4♦', '9♥')
    state.custom['step'] = 'discard'

    expect(labels('Player 1')).to include('Discard 9♥ and knock with 4 deadwood')
    expect(labels('Player 1').grep(/Discard A♣ and knock/)).to be_empty
  end

  it 'scores an undercut to the defender' do
    give('Player 1', 'A♣', '2♣', '3♣', '7♦', '7♥', '7♠', 'J♠', 'Q♠', 'K♠', '5♦')
    give('Player 2', '4♣', '5♣', '6♣', '8♦', '8♥', '8♠', '9♦', '10♦', 'J♦', '2♥')
    quietly { runner.send(:score_hand, 'Player 1') }

    expect(state.scores).to eq('Player 1' => 0, 'Player 2' => 28)
  end

  describe 'personas' do
    def runner_with(personas) = described_class.new(rules: rules, players: game.players, models: {}, game_state_class: game.game_state_class,
                                                    seed: 1, personas: personas, mode: 'bot', persist: false)

    it 'gives each player a different persona when none are requested' do
      expect(state.custom['personas'].values).to contain_exactly(*described_class.persona_names)
    end

    it 'refuses an unknown persona' do
      expect { runner_with(%w[gambler *]) }.to raise_error(ArgumentError, /Unknown persona "gambler"/)
    end

    def bot_rule(persona)
      state.custom['personas']['Player 1'] = persona
      runner.send(:scripted_choice, 'Player 1', runner.send(:legal_moves, 'Player 1'))['rule']
    end

    it 'has the gin hunter hold a knock that the quick knocker takes' do
      give('Player 1', 'A♣', '2♣', '3♣', '7♦', '7♥', '7♠', 'J♠', 'Q♠', 'K♠', '4♦', '9♥')
      state.custom['step'] = 'discard'

      expect(bot_rule('quick_knocker')).to eq('knock')
      expect(bot_rule('gin_hunter')).to eq('shed_deadwood')
    end
  end

  it 'plays whole games with its bot rules' do
    results = PlaiTester::Botrun.new(runner_class: described_class, game_state_class: game.game_state_class, rules: rules,
                                     players: game.players, seeds: (1..10).to_a, personas: ['all']).run

    expect(results.map { |r| r['error'] }.compact).to be_empty
    expect(results.map { |r| r['winner'] }).to all(start_with('Player'))
  end
end
