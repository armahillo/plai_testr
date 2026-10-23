require 'spec_helper'

RSpec.describe Hearts::Session::Runner do
  let(:game)   { PlaiTestr.load('hearts') }
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

  it 'deals the whole deck, 13 cards each' do
    hands = game.players.map { |p| state.player_state(p).hand }

    expect(hands.map(&:length)).to all(eq(13))
    expect(hands.flatten.map { |c| c['uid'] }.uniq.length).to eq(52)
  end

  it 'passes 3 cards to the left on the first hand, then starts with the 2♣' do
    passed = game.players.to_h { |p| [p, state.player_state(p).hand.first(3)] }
    game.players.each { |p| runner.apply_action_effects(p, { pass: { value: passed[p].map { |c| c['uid'] } } }) }

    expect(state.player_state('Player 2').hand).to include(*passed['Player 1'])
    expect(state.player_state(state.active).hand.map { |c| c['name'] }).to include('2♣')
    expect(labels(state.active)).to eq(['Play 2♣'])
  end

  context 'during tricks' do
    before { state.data.merge!('step' => 'play', 'tricks' => 1, 'trick' => [], 'active' => 'Player 1') }

    it 'does not lead hearts until they are broken' do
      give('Player 1', '5♥', '9♣')

      expect(labels('Player 1')).to eq(['Play 9♣'])
    end

    it 'follows the suit led when it can, and says whether each card wins the trick' do
      give('Player 2', '5♥', '7♣', 'K♣')
      state.data['trick'] = [{ 'player' => 'Player 1', 'card' => cards('9♣').first }]

      expect(labels('Player 2')).to eq(['Play 7♣ (stays under the 9♣)', 'Play K♣ (wins the trick so far)'])
    end

    it 'tells a player who cannot follow suit that any card is allowed' do
      give('Player 2', 'Q♠', '5♥')
      state.data.merge!('trick' => [{ 'player' => 'Player 1', 'card' => cards('2♣').first }], 'active' => 'Player 2')

      expect(runner.view_text_for('Player 2')).to end_with('You are following, not leading. You have no clubs, so you may play any card.')
      expect(labels('Player 2')).to eq(['Play Q♠ (13 pts; cannot win this trick)', 'Play 5♥ (1 pt; cannot win this trick)'])
    end

    it 'keeps points off the first trick unless there is nothing else' do
      state.data.merge!('tricks' => 0, 'trick' => [{ 'player' => 'Player 1', 'card' => cards('2♣').first }])
      give('Player 2', 'Q♠', '5♥', '9♦')

      expect(labels('Player 2')).to eq(['Play 9♦ (cannot win this trick)'])
    end
  end

  it 'scores 26 to everyone else when a player shoots the moon' do
    state.data['taken'] = { 'Player 1' => deck.select { |c| Hearts.points(c).positive? }, 'Player 2' => [], 'Player 3' => [], 'Player 4' => [] }
    runner.send(:score_hand)

    expect(state.scores).to eq('Player 1' => 0, 'Player 2' => 26, 'Player 3' => 26, 'Player 4' => 26)
  end

  it 'counts hearts, the Q♠ and moons in the session report' do
    state.data['taken'] = { 'Player 1' => cards('Q♠', '5♥'), 'Player 2' => cards('2♥'), 'Player 3' => [], 'Player 4' => [] }
    runner.send(:score_hand)

    expect(runner.report_sections.first).to include('| Player 1 | 14 | 1 | 1 | 0 |', '| Player 2 | 1 | 1 | 0 | 0 |')
  end

  describe 'personas' do
    it 'seats four players with two personas, each used twice' do
      expect(state.data['personas'].values.tally).to eq('safe_player' => 2, 'moon_shooter' => 2)
    end

    it 'has the moon shooter keep the dangerous cards the safe player passes' do
      state.player_state('Player 1').hand.replace(cards('Q♠', 'A♥', '2♣', '3♦'))
      moves = runner.legal_moves('Player 1')
      state.data['personas']['Player 1'] = 'safe_player'
      safe  = runner.bot_choice('Player 1', moves, pick: [2, 2])
      state.data['personas']['Player 1'] = 'moon_shooter'
      moon  = runner.bot_choice('Player 1', moves, pick: [2, 2])

      expect(safe['choices'].map { |i| moves[i - 1][:label] }).to contain_exactly('Pass Q♠ (13 pts)', 'Pass A♥ (1 pt)')
      expect(moon['choices'].map { |i| moves[i - 1][:label] }).to contain_exactly('Pass 2♣', 'Pass 3♦')
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

  it 'plays whole games with its bot rules and reports penalties by seat' do
    results = PlaiTestr::Botrun.new(game: game, players: game.players, seeds: (1..20).to_a).run
    report  = game.botrun_report_class.new(results, game: 'Hearts', version: '1.0.0', seconds: 1.0).to_markdown

    expect(results.map { |r| r['error'] }.compact).to be_empty
    expect(results.map { |r| r['winner'] }).to all(start_with('Player'))
    expect(report).to include('## Hands per game', '## Penalties by seat')
  end
end
