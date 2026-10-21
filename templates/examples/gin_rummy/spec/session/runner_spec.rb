require 'spec_helper'

RSpec.describe GinRummy::Session::Runner do
  let(:game)   { PlaiTestr.load('gin_rummy') }
  let(:runner) { runner_with(nil) }
  let(:state)  { runner.game_state }
  let(:deck)   { PlaiTestr::Deck.build(game.rules) }

  def runner_with(personas, seed: 1)
    described_class.new(game: game, players: game.players, seed: seed, personas: personas, mode: 'bot', persist: false, out: StringIO.new)
  end

  def cards(*names) = names.map { |name| deck.find { |c| c['name'] == name } }

  def give(player, *names) = state.player_state(player).hand.replace(cards(*names))

  def labels(player) = runner.legal_moves(player).map { |m| m[:label] }

  before { runner.setup }

  it 'deals 10 cards each and turns up one card; the non-dealer starts' do
    expect(game.players.map { |p| state.player_state(p).hand.length }).to eq([10, 10])
    expect(state.discard_pile.length).to eq(1)
    expect(state.stock.length).to eq(31)
    expect(state.active).to eq('Player 1')
  end

  it 'does not let a player discard the card they just took from the discard pile' do
    taken = state.discard_pile.last['name']
    runner.apply_action_effects('Player 1', { draw: { source: 'discard' } })

    expect(labels('Player 1').grep(/#{taken}/)).to be_empty
  end

  it 'offers a knock only when the deadwood after discarding is 10 or less' do
    give('Player 1', 'A♣', '2♣', '3♣', '7♦', '7♥', '7♠', 'J♠', 'Q♠', 'K♠', '4♦', '9♥')
    state.data['step'] = 'discard'

    expect(labels('Player 1')).to include('Discard 9♥ and knock with 4 deadwood')
    expect(labels('Player 1').grep(/Discard A♣ and knock/)).to be_empty
  end

  it 'shows what taking the top discard would do to the deadwood' do
    expect(labels('Player 1').last).to match(/\ATake the .+ from the discard pile \(best deadwood after your discard: \d+; now: \d+\)\z/)
  end

  it 'declares a hand that runs too long a draw and deals the next' do
    state.data.merge!('turns' => GinRummy::MAX_TURNS - 1, 'step' => 'discard')
    runner.apply_action_effects('Player 1', { discard: { value: state.player_state('Player 1').hand.first['uid'] } })

    expect(state.data['hand']).to eq(2)
    expect(state.data.dig('results', 'turn_cap')).to eq(1)
  end

  it 'scores an undercut to the defender' do
    give('Player 1', 'A♣', '2♣', '3♣', '7♦', '7♥', '7♠', 'J♠', 'Q♠', 'K♠', '5♦')
    give('Player 2', '4♣', '5♣', '6♣', '8♦', '8♥', '8♠', '9♦', '10♦', 'J♦', '2♥')
    runner.send(:score_hand, 'Player 1')

    expect(state.scores).to eq('Player 1' => 0, 'Player 2' => 28)
  end

  describe 'personas' do
    it 'gives each player a different persona when none are requested' do
      expect(state.data['personas'].values).to contain_exactly('quick_knocker', 'gin_hunter')
    end

    it 'refuses an unknown persona' do
      expect { runner_with(%w[gambler *]) }.to raise_error(PlaiTestr::PersonaError, /Unknown persona "gambler"/)
    end

    def bot_rule(persona)
      state.data['personas']['Player 1'] = persona
      runner.bot_choice('Player 1', runner.legal_moves('Player 1'))['rule']
    end

    it 'has the gin hunter hold a knock that the quick knocker takes' do
      give('Player 1', 'A♣', '2♣', '3♣', '7♦', '7♥', '7♠', 'J♠', 'Q♠', 'K♠', '4♦', '9♥')
      state.data['step'] = 'discard'

      expect(bot_rule('quick_knocker')).to eq('knock')
      expect(bot_rule('gin_hunter')).to eq('shed_deadwood')
    end
  end

  it 'builds every prompt a model player would see' do
    (1..3).each do |seed|
      session = runner_with(nil, seed: seed)
      session.setup
      until session.game_over?
        player = session.next_player
        %i[rules_text_for view_text_for recent_events_for persona_for turn_phase].each { |hook| session.public_send(hook, player) }
        session.play_turn
      end
      game.players.each { |p| session.debrief_view_for(p) }
    end
  end

  it 'plays whole games with its bot rules' do
    results = PlaiTestr::Botrun.new(game: game, players: game.players, seeds: (1..10).to_a, personas: ['all']).run

    expect(results.map { |r| r['error'] }.compact).to be_empty
    expect(results.map { |r| r['winner'] }).to all(start_with('Player'))
  end
end
