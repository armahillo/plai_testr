require 'spec_helper'

RSpec.describe PlaiTester::Session::Runner do
  let(:players) { ['Alice', 'Bob'] }
  let(:client)  { instance_double(PlaiTester::Agents::OllamaClient) }
  let(:manager) do
    instance_double(
      PlaiTester::Session::Manager,
      session_id:              'test-session',
      session_dir:             Dir.tmpdir,
      save_checkpoint:         nil,
      append_transcript_entry: nil
    )
  end
  let(:rules) do
    {
      'game'           => { 'name' => 'Test Game', 'version' => '1.0' },
      'turn_structure' => [{ 'name' => 'Act', 'description' => 'Take an action' }],
      'win_conditions' => [{ 'type' => 'turn_limit', 'description' => 'Max turns', 'limit' => 5 }],
      'actions'        => [
        { 'type' => 'move',   'description' => 'Move a piece' },
        { 'type' => 'attack', 'description' => 'Attack', 'triggers_reactions' => true },
        { 'type' => 'block',  'description' => 'Block',  'reaction' => true }
      ]
    }
  end

  before do
    allow(PlaiTester::Agents::OllamaClient).to  receive(:new).and_return(client)
    allow(PlaiTester::Session::Manager).to       receive(:new).and_return(manager)
  end

  subject(:runner) do
    described_class.new(rules: rules, players: players, models: { player: 'p-model', referee: 'r-model' })
  end

  def player_chat(action, params = {}, reasoning = 'test')
    { 'message' => { 'content' => JSON.generate({ 'action' => action, 'parameters' => params, 'reasoning' => reasoning }) } }
  end

  def referee_chat(valid:, changes: {}, reason: 'ok')
    { 'message' => { 'content' => JSON.generate({ 'valid' => valid, 'reason' => reason, 'state_changes' => changes }) } }
  end

  describe '#available_actions_for' do
    it 'returns non-reaction action types' do
      expect(runner.send(:available_actions_for, 'Alice')).to contain_exactly('move', 'attack')
    end

    it 'excludes reaction actions' do
      expect(runner.send(:available_actions_for, 'Alice')).not_to include('block')
    end
  end

  describe '#setup' do
    let(:rules_with_setup) { rules.merge('setup' => [{ 'step' => 1, 'description' => 'Deal cards.' }]) }
    let(:runner_with_setup) { described_class.new(rules: rules_with_setup, players: players, models: { player: 'p-model', referee: 'r-model' }) }
    let(:initial_state)     { { 'flags' => {}, 'custom' => { 'deck' => [1, 2, 3] }, 'player_states' => {} } }

    it 'calls the referee to compute initial state and applies it' do
      allow(client).to receive(:chat).with(hash_including(model: 'r-model')).and_return(
        { 'message' => { 'content' => JSON.generate(initial_state) } }
      )

      runner_with_setup.send(:setup)

      expect(runner_with_setup.instance_variable_get(:@game_state).serialize['custom']['deck']).to eq([1, 2, 3])
    end

    it 'is skipped when rules have no setup steps' do
      # base rules fixture has no setup key — setup returns immediately
      expect(client).not_to receive(:chat).with(hash_including(model: 'r-model'))
      runner.send(:setup)
    end
  end

  describe '#triggers_reactions?' do
    it 'returns true for actions flagged with triggers_reactions' do
      expect(runner.send(:triggers_reactions?, { 'action' => 'attack' })).to be true
    end

    it 'returns false for regular actions' do
      expect(runner.send(:triggers_reactions?, { 'action' => 'move' })).to be false
    end

    it 'returns false for unknown action types' do
      expect(runner.send(:triggers_reactions?, { 'action' => 'unknown' })).to be false
    end
  end

  describe '#evaluate_win_condition' do
    let(:game_state) { runner.instance_variable_get(:@game_state) }

    describe 'score_threshold' do
      let(:condition) { { 'type' => 'score_threshold', 'threshold' => 10 } }

      it 'returns true when any player meets the threshold' do
        game_state.apply_changes('player_states' => { 'Alice' => { 'score' => 10 } })
        expect(runner.send(:evaluate_win_condition, condition)).to be true
      end

      it 'returns false when no player meets the threshold' do
        expect(runner.send(:evaluate_win_condition, condition)).to be false
      end
    end

    describe 'flag' do
      let(:condition) { { 'type' => 'flag', 'flag' => 'game_over', 'value' => true } }

      it 'returns true when the flag equals the expected value' do
        game_state.apply_changes('flags' => { 'game_over' => true })
        expect(runner.send(:evaluate_win_condition, condition)).to be true
      end

      it 'returns false when the flag does not match' do
        expect(runner.send(:evaluate_win_condition, condition)).to be false
      end
    end

    describe 'turn_limit' do
      let(:condition) { { 'type' => 'turn_limit', 'limit' => 3 } }

      it 'returns true when the turn count reaches the limit' do
        3.times { game_state.advance_turn }
        expect(runner.send(:evaluate_win_condition, condition)).to be true
      end

      it 'returns false before the limit is reached' do
        expect(runner.send(:evaluate_win_condition, condition)).to be false
      end
    end

    it 'returns false for unknown condition types' do
      expect(runner.send(:evaluate_win_condition, { 'type' => 'custom' })).to be false
    end
  end

  describe '#attempt_turn' do
    let(:alice) { runner.instance_variable_get(:@players)['Alice'] }

    context 'when end_turn is declared' do
      before { allow(client).to receive(:chat).with(hash_including(model: 'p-model')).and_return(player_chat('end_turn')) }

      it 'returns the end_turn action with nil validation' do
        action, validation = runner.send(:attempt_turn, alice, 'Alice', ['move', 'end_turn'])

        expect(action['action']).to eq('end_turn')
        expect(validation).to       be_nil
      end

      it 'does not call the referee' do
        expect(client).not_to receive(:chat).with(hash_including(model: 'r-model'))
        runner.send(:attempt_turn, alice, 'Alice', ['move', 'end_turn'])
      end
    end

    context 'when the referee rejects every attempt' do
      before do
        allow(client).to receive(:chat).with(hash_including(model: 'p-model')).and_return(player_chat('move'))
        allow(client).to receive(:chat).with(hash_including(model: 'r-model')).and_return(referee_chat(valid: false, reason: 'illegal'))
      end

      it 'raises StalledError after MAX_RETRIES' do
        expect {
          runner.send(:attempt_turn, alice, 'Alice', ['move'])
        }.to raise_error(PlaiTester::Session::StalledError, /Alice/)
      end

      it 'includes all failed attempts in the error context' do
        runner.send(:attempt_turn, alice, 'Alice', ['move'])
      rescue PlaiTester::Session::StalledError => e
        expect(e.context[:attempts].length).to eq(described_class::MAX_RETRIES)
      end
    end

    context 'when the referee accepts on the second attempt' do
      before do
        allow(client).to receive(:chat).with(hash_including(model: 'p-model')).and_return(player_chat('move'))
        allow(client).to receive(:chat).with(hash_including(model: 'r-model')).and_return(
          referee_chat(valid: false, reason: 'not yet'),
          referee_chat(valid: true,  changes: {})
        )
      end

      it 'returns the valid action and validation' do
        action, validation = runner.send(:attempt_turn, alice, 'Alice', ['move'])

        expect(action['action']).to    eq('move')
        expect(validation['valid']).to be true
      end
    end
  end

  describe '#attempt_reaction' do
    let(:bob)     { runner.instance_variable_get(:@players)['Bob'] }
    let(:trigger) { { 'action' => 'attack', 'parameters' => {}, 'reasoning' => 'attacking' } }

    context 'when no_op is returned' do
      before { allow(client).to receive(:chat).with(hash_including(model: 'p-model')).and_return(player_chat('no_op')) }

      it 'returns no_op with nil validation' do
        action, validation = runner.send(:attempt_reaction, bob, 'Bob', 'Alice', trigger, ['block'])

        expect(action['action']).to eq('no_op')
        expect(validation).to       be_nil
      end

      it 'does not call the referee' do
        expect(client).not_to receive(:chat).with(hash_including(model: 'r-model'))
        runner.send(:attempt_reaction, bob, 'Bob', 'Alice', trigger, ['block'])
      end
    end

    context 'when the referee rejects every reaction attempt' do
      before do
        allow(client).to receive(:chat).with(hash_including(model: 'p-model')).and_return(player_chat('block'))
        allow(client).to receive(:chat).with(hash_including(model: 'r-model')).and_return(referee_chat(valid: false, reason: 'cannot block'))
      end

      it 'falls back to no_op rather than raising' do
        action, _validation = runner.send(:attempt_reaction, bob, 'Bob', 'Alice', trigger, ['block'])
        expect(action['action']).to eq('no_op')
      end
    end

    context 'when the reaction is valid' do
      before do
        allow(client).to receive(:chat).with(hash_including(model: 'p-model')).and_return(player_chat('block'))
        allow(client).to receive(:chat).with(hash_including(model: 'r-model')).and_return(referee_chat(valid: true, changes: {}))
      end

      it 'returns the reaction action and validation' do
        action, validation = runner.send(:attempt_reaction, bob, 'Bob', 'Alice', trigger, ['block'])

        expect(action['action']).to    eq('block')
        expect(validation['valid']).to be true
      end
    end
  end

  describe 'menu turns' do
    let(:menu_runner_class) do
      Class.new(described_class) do
        private

        def legal_moves(_player)
          [{ 'label' => 'Secret move', 'public' => 'did something', 'action' => { 'action' => 'move', 'parameters' => {} } },
           { 'label' => 'Other move', 'action' => { 'action' => 'attack', 'parameters' => {} } }]
        end

        def next_player = 'Bob'

        def apply_action_effects(_player, _action); end
      end
    end

    let(:menu_runner) { menu_runner_class.new(rules: rules, players: players, models: { player: 'p-model', referee: 'r-model' }) }

    before do
      allow(client).to receive(:chat).with(hash_including(model: 'p-model'))
                                     .and_return({ 'message' => { 'content' => '{"choice":1,"reasoning":"why","plan":"my plan"}' } })
      allow($stdout).to receive(:puts)
    end

    it 'lets the game choose who acts and logs the chosen move without calling the referee' do
      expect(client).not_to receive(:chat).with(hash_including(model: 'r-model'))

      menu_runner.send(:play_turn)
      entry = menu_runner.instance_variable_get(:@turn_log).last

      expect(entry).to include('player' => 'Bob', 'label' => 'Secret move', 'public' => 'did something', 'plan' => 'my plan', 'fallback' => false)
    end

    it "shows other players only the public text of a move" do
      menu_runner.send(:play_turn)

      expect(menu_runner.send(:recent_events_for, 'Alice')).to eq(['Bob: did something'])
      expect(menu_runner.send(:recent_events_for, 'Bob')).to   eq(['You: Secret move'])
    end

    it 'asks each player the debrief questions once and stores the answers' do
      menu_runner.define_singleton_method(:debrief_questions) { |_p| ['Any problems?'] }
      allow(client).to receive(:chat).with(hash_including(model: 'p-model', format: hash_including('required' => ['q1'])))
                                     .and_return({ 'message' => { 'content' => '{"q1":"none really"}' } })

      menu_runner.send(:run_debrief)
      menu_runner.send(:run_debrief) # already answered: no second round of questions

      expect(client).to have_received(:chat).with(hash_including(format: hash_including('required' => ['q1']))).twice
      expect(menu_runner.instance_variable_get(:@game_state).custom['debrief']['Alice'])
        .to eq([{ 'question' => 'Any problems?', 'answer' => 'none really' }])
    end
  end
end
