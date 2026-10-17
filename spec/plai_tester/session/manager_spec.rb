require 'spec_helper'

RSpec.describe PlaiTester::Session::Manager do
  let(:players)    { ['Player 1', 'Player 2'] }
  let(:game_state) { PlaiTester::State::GameState.new(players: players) }
  let(:tmp_dir)    { Dir.mktmpdir('plai_tester_spec_') }

  after { FileUtils.rm_rf(tmp_dir) }

  def new_manager(**opts)
    described_class.new(base_dir: tmp_dir, **opts)
  end

  subject(:manager) { new_manager }

  describe '#session_id' do
    it 'is a timestamp, with a counter when another session started in the same second' do
      allow(Time).to receive(:now).and_return(Time.new(2026, 10, 15, 9, 30, 5))

      expect([new_manager, new_manager, new_manager].map(&:session_id)).to eq(%w[20261015-093005 20261015-093005-2 20261015-093005-3])
    end
  end

  describe '#save_checkpoint and #load_checkpoint' do
    it 'round-trips game state through JSON' do
      game_state.advance_turn
      game_state.apply_changes('player_states' => { 'Player 1' => { 'score' => 3 } })

      manager.save_checkpoint(game_state, [], { 'status' => 'in_progress', 'game' => 'Test' })
      checkpoint = manager.load_checkpoint

      expect(checkpoint['game_state']['turn']).to eq(game_state.turn)
      expect(checkpoint['game_state']['player_states']['Player 1']['score']).to eq(3)
      expect(checkpoint['status']).to eq('in_progress')
    end
  end

  describe '#append_transcript_entry' do
    it 'appends newline-delimited JSON to the transcript file' do
      manager.append_transcript_entry({ 'turn' => 1, 'player' => 'Player 1', 'action' => 'test' })
      manager.append_transcript_entry({ 'turn' => 2, 'player' => 'Player 2', 'action' => 'test' })

      lines = File.readlines(manager.transcript_path).map(&:strip).reject(&:empty?)
      expect(lines.length).to eq(2)
      expect(JSON.parse(lines.first)['turn']).to eq(1)
    end
  end

  describe '.list' do
    it 'returns an empty array when no sessions exist' do
      expect(described_class.list(base_dir: tmp_dir)).to eq([])
    end

    it 'lists saved sessions ordered newest first' do
      m1 = new_manager(session_id: 'session-a')
      m2 = new_manager(session_id: 'session-b')

      allow(Time).to receive(:now).and_return(Time.parse('2026-01-01'), Time.parse('2026-01-02'))

      m1.save_checkpoint(game_state, [], { 'status' => 'completed',   'game' => 'Game A' })
      m2.save_checkpoint(game_state, [], { 'status' => 'in_progress', 'game' => 'Game B' })

      sessions = described_class.list(base_dir: tmp_dir)
      expect(sessions.first['session_id']).to eq(m2.session_id)
      expect(sessions.length).to eq(2)
    end
  end
end
