require 'spec_helper'

RSpec.describe PlaiTestr::State::PlayerState do
  subject(:state) { described_class.new(name: 'Alice', score: 2, hand: ['card_a', 'card_b'], data: { 'wounded' => false }) }

  describe '#serialize' do
    it 'includes full hand and data' do
      h = state.serialize
      expect(h['name']).to  eq('Alice')
      expect(h['score']).to eq(2)
      expect(h['hand']).to  eq(['card_a', 'card_b'])
      expect(h['data']).to  eq('wounded' => false)
    end
  end

  describe '#serialize_for' do
    context 'when the observer is the player themselves' do
      it 'returns the full state' do
        expect(state.serialize_for('Alice')).to eq(state.serialize)
      end
    end

    context 'when the observer is an opponent' do
      it 'hides hand contents, exposes only hand size and score' do
        h = state.serialize_for('Bob')
        expect(h['hand_size']).to eq(2)
        expect(h['score']).to     eq(2)
        expect(h).not_to          have_key('hand')
      end
    end
  end

  describe '#apply_changes' do
    it 'updates score' do
      state.apply_changes('score' => 5)
      expect(state.score).to eq(5)
    end

    it 'replaces hand' do
      state.apply_changes('hand' => ['card_c'])
      expect(state.hand).to eq(['card_c'])
    end

    it 'merges data' do
      state.apply_changes('data' => { 'wounded' => true })
      expect(state.data['wounded']).to be(true)
    end

    it 'handles nil gracefully' do
      expect { state.apply_changes(nil) }.not_to raise_error
    end
  end

  describe '.from_h' do
    it 'round-trips through serialize' do
      restored = described_class.from_h(state.serialize)
      expect(restored.name).to  eq(state.name)
      expect(restored.score).to eq(state.score)
      expect(restored.hand).to  eq(state.hand)
      expect(restored.data).to  eq(state.data)
    end
  end
end
