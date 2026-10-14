require 'spec_helper'

RSpec.describe PlaiTester::Session::Runner do
  let(:tmp)     { Dir.mktmpdir('plai_runner_spec_') }
  let(:players) { ['Alice', 'Bob'] }
  let(:client)  { instance_double(PlaiTester::Agents::OllamaClient) }
  let(:rules) do
    path = File.join(tmp, 'rules.json')
    File.write(path, JSON.generate('game' => { 'name' => 'Counting Game', 'version' => '1.0' }))
    PlaiTester::Compiler::RulesLoader.load(path)
  end

  let(:game_class) do
    Class.new(described_class) do
      attr_accessor :moves, :pick

      private

      def setup = @game_state.apply_changes('custom' => { 'total' => 0, 'picked' => [] })

      def legal_moves(_player) = moves

      def pick_range(_player) = pick

      def apply_action_effects(_player, action)
        custom = @game_state.custom
        custom['total'] += action.dig('parameters', 'amount').to_i
        custom['picked'].concat(action.dig('parameters', 'values') || [])
        @game_state.apply_changes('flags' => { 'game_over' => true, 'winner' => 'Alice' }) if custom['total'] >= 3
      end
    end
  end

  let(:runner) do
    game_class.new(rules: rules, players: players, models: { player: 'p-model' }, seed: 7).tap do |r|
      r.moves = [move('Add one', 1, public: 'added something'), move('Add two', 2)]
    end
  end

  def move(label, amount, public: nil)
    { 'label' => label, 'public' => public, 'action' => { 'action' => 'add', 'parameters' => { 'amount' => amount } } }.compact
  end

  def chat(json) = { 'message' => { 'content' => json } }

  def state = runner.instance_variable_get(:@game_state)

  def log = runner.instance_variable_get(:@turn_log)

  before do
    PlaiTester.sessions_dir = File.join(tmp, 'sessions')
    PlaiTester.reports_dir  = File.join(tmp, 'reports')
    allow(PlaiTester::Agents::OllamaClient).to receive(:new).and_return(client)
    allow(client).to receive(:chat).and_return(chat('{"choice":2,"reasoning":"two is more","plan":"add fast"}'))
    allow($stdout).to receive(:puts)
    allow($stdout).to receive(:print)
  end

  after { FileUtils.rm_rf(tmp) }

  it 'records the seed, player model and host for a new session' do
    expect(state.custom).to include('seed' => 7, 'player_model' => 'p-model', 'host' => Socket.gethostname)
  end

  it 'builds no referee unless a referee model is given' do
    expect(runner.instance_variable_get(:@referee)).to be_nil
  end

  it 'applies the chosen move and logs it with the reasoning and plan' do
    runner.send(:setup)
    runner.send(:play_turn)

    expect(state.custom['total']).to eq(2)
    expect(log.last).to include('player' => 'Alice', 'label' => 'Add two', 'choice' => 2, 'plan' => 'add fast', 'fallback' => false)
  end

  it 'applies a single legal move without asking the model' do
    runner.moves = [move('Add one', 1)]
    runner.send(:setup)

    expect(client).not_to receive(:chat)
    runner.send(:play_turn)

    expect(log.last).to include('label' => 'Add one', 'auto' => true, 'attempts' => 0)
  end

  it 'asks for several moves at once on a pick turn and applies their values together' do
    runner.moves = %w[a b c].map { |v| { 'label' => "Pick #{v}", 'action' => { 'action' => 'keep', 'parameters' => { 'value' => v } } } }
    runner.pick  = [1, 2]
    runner.send(:setup)
    allow(client).to receive(:chat).and_return(chat('{"choices":[3,1],"reasoning":"r","plan":"p"}'))

    runner.send(:play_turn)

    expect(state.custom['picked']).to eq(%w[c a])
    expect(log.last).to include('choice' => [3, 1], 'label' => 'Pick c; Pick a')
  end

  it 'takes every option without asking when a pick must take them all' do
    runner.moves = %w[a b].map { |v| { 'label' => v, 'action' => { 'action' => 'keep', 'parameters' => { 'value' => v } } } }
    runner.pick  = [2, 2]
    runner.send(:setup)

    expect(client).not_to receive(:chat)
    runner.send(:play_turn)

    expect(state.custom['picked']).to eq(%w[a b])
  end

  it 'shows other players only the public text of a move' do
    runner.send(:setup)
    allow(client).to receive(:chat).and_return(chat('{"choice":1,"reasoning":"r","plan":"p"}'))
    runner.send(:play_turn)

    expect(runner.send(:recent_events_for, 'Bob')).to eq(['Alice: added something'])
    expect(runner.send(:recent_events_for, 'Alice')).to eq(['You: Add one'])
  end

  it 'asks each player the debrief questions once and stores the answers' do
    runner.define_singleton_method(:debrief_questions) { |_p| ['Any problems?'] }
    allow(client).to receive(:chat).with(hash_including(format: hash_including('required' => ['q1'])))
                                   .and_return(chat('{"q1":"none really"}'))

    runner.send(:run_debrief)
    runner.send(:run_debrief)

    expect(client).to have_received(:chat).with(hash_including(format: hash_including('required' => ['q1']))).twice
    expect(state.custom['debrief']['Alice']).to eq([{ 'question' => 'Any problems?', 'answer' => 'none really' }])
  end

  it 'plays to the end, checkpoints as completed, and writes a report' do
    runner.run

    checkpoint = JSON.parse(File.read(File.join(PlaiTester.sessions_dir, runner.session_id, 'state.json')))
    report     = File.read(File.join(PlaiTester.reports_dir, "#{runner.session_id}.md"))

    expect(runner.status).to eq('completed')
    expect(checkpoint['status']).to eq('completed')
    expect(report).to include('**Winner: Alice**', '## Model reliability', '## Speed', '## Turn log')
  end

  it 'resumes from a checkpoint without running setup again' do
    runner.send(:setup)
    runner.send(:play_turn)
    runner.send(:save_checkpoint, 'interrupted')

    resumed = game_class.resume(session_id: runner.session_id, models: { player: 'p-model' })
    resumed.moves = runner.moves

    expect(resumed.instance_variable_get(:@game_state).custom['total']).to eq(2)
    expect(resumed.seed).to eq(7)
  end
end
