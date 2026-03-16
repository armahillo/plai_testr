require 'spec_helper'

RSpec.describe PlaiTester::State::GameState do
  let(:players) { ['Alice', 'Bob'] }
  subject(:state) { described_class.new(players: players) }

  describe '#current_player' do
    it 'starts with the first player' do
      expect(state.current_player).to eq('Alice')
    end
  end

  describe '#advance_turn' do
    it 'increments the turn counter' do
      expect { state.advance_turn }.to change(state, :turn).by(1)
    end

    it 'cycles to the next player' do
      state.advance_turn
      expect(state.current_player).to eq('Bob')
    end

    it 'wraps back to the first player' do
      2.times { state.advance_turn }
      expect(state.current_player).to eq('Alice')
    end
  end

  describe '#apply_changes' do
    it 'merges score changes via player_states' do
      state.apply_changes('player_states' => { 'Alice' => { 'score' => 3 } })
      expect(state.scores['Alice']).to eq(3)
    end

    it 'merges flag changes' do
      state.apply_changes('flags' => { 'bonus_active' => true })
      expect(state.flags['bonus_active']).to be(true)
    end

    it 'merges custom state' do
      state.apply_changes('custom' => { 'round' => 2 })
      expect(state.serialize['custom']['round']).to eq(2)
    end

    it 'handles nil gracefully' do
      expect { state.apply_changes(nil) }.not_to raise_error
    end

    it 'handles an empty hash gracefully' do
      expect { state.apply_changes({}) }.not_to raise_error
    end
  end

  describe '#player_state' do
    it 'returns the PlayerState for a named player' do
      expect(state.player_state('Alice')).to be_a(PlaiTester::State::PlayerState)
    end
  end

  describe '#scores' do
    it 'returns a hash of player scores' do
      state.apply_changes('player_states' => { 'Bob' => { 'score' => 7 } })
      expect(state.scores).to eq('Alice' => 0, 'Bob' => 7)
    end
  end

  describe '#serialize' do
    it 'includes all required keys' do
      h = state.serialize
      expect(h.keys).to include('turn', 'current_player_index', 'current_player', 'players', 'flags', 'custom', 'player_states')
    end

    it 'embeds full player state' do
      h = state.serialize
      expect(h['player_states']['Alice']).to include('name' => 'Alice', 'score' => 0, 'hand' => [])
    end
  end

  describe '#custom_for' do
    it 'returns the full @custom by default' do
      state.apply_changes('custom' => { 'round' => 3 })
      expect(state.serialize_for('Alice')['custom']).to eq('round' => 3)
    end

    it 'can be overridden in a subclass to filter per observer' do
      filtered_class = Class.new(described_class) do
        private
        def custom_for(_observer) = @custom.merge('filtered' => true)
      end

      substate = filtered_class.new(players: ['Alice', 'Bob'])
      expect(substate.serialize_for('Alice')['custom']['filtered']).to be(true)
      expect(substate.serialize['custom']).not_to have_key('filtered')
    end
  end

  describe '#serialize_for' do
    before { state.apply_changes('player_states' => { 'Alice' => { 'hand' => ['secret_card'] } }) }

    it "includes the observer's full hand" do
      h = state.serialize_for('Alice')
      expect(h['player_states']['Alice']['hand']).to eq(['secret_card'])
    end

    it "hides the opponent's hand contents" do
      h = state.serialize_for('Alice')
      expect(h['player_states']['Bob']).to     have_key('hand_size')
      expect(h['player_states']['Bob']).not_to have_key('hand')
    end
  end

  describe '.from_h' do
    it 'round-trips through serialize' do
      state.advance_turn
      state.apply_changes('player_states' => { 'Bob' => { 'score' => 2 } })

      restored = described_class.from_h(state.serialize)

      expect(restored.turn).to           eq(state.turn)
      expect(restored.current_player).to eq(state.current_player)
      expect(restored.scores).to         eq(state.scores)
      expect(restored.flags).to          eq(state.flags)
    end

    it 'supports legacy checkpoints with top-level scores' do
      legacy = { 'players' => players, 'scores' => { 'Alice' => 4, 'Bob' => 1 } }
      restored = described_class.from_h(legacy)
      expect(restored.scores).to eq('Alice' => 4, 'Bob' => 1)
    end
  end
end
