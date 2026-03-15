require 'spec_helper'

RSpec.describe Testr::State::GameState do
  let(:players)       { ['Alice', 'Bob'] }
  let(:current_state) { { 'flags' => { 'bonus_active' => false }, 'scores' => { 'Alice' => 0, 'Bob' => 0 } } }
  subject(:state)     { described_class.new(players: players, current_state: current_state) }

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
    it 'merges score changes' do
      state.apply_changes('scores' => { 'Alice' => 3 })
      expect(state.scores['Alice']).to eq(3)
    end

    it 'merges flag changes' do
      state.apply_changes('flags' => { 'bonus_active' => true })
      expect(state.flags['bonus_active']).to be(true)
    end

    it 'merges custom state' do
      state.apply_changes('custom' => { 'round' => 2 })
      expect(state.to_h['custom']['round']).to eq(2)
    end

    it 'handles nil gracefully' do
      expect { state.apply_changes(nil) }.not_to raise_error
    end

    it 'handles an empty hash gracefully' do
      expect { state.apply_changes({}) }.not_to raise_error
    end
  end

  describe '#to_h' do
    it 'includes all required keys' do
      h = state.to_h
      expect(h.keys).to include('turn', 'current_player_index', 'current_player', 'players', 'flags', 'scores', 'custom')
    end
  end

  describe '.from_h' do
    it 'round-trips through to_h' do
      state.advance_turn
      state.apply_changes('scores' => { 'Bob' => 2 })

      restored = described_class.from_h(state.to_h)

      expect(restored.turn).to eq(state.turn)
      expect(restored.current_player).to eq(state.current_player)
      expect(restored.scores).to eq(state.scores)
      expect(restored.flags).to eq(state.flags)
    end
  end
end
