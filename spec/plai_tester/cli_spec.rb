require 'spec_helper'

RSpec.describe PlaiTester::CLI do
  let(:tmp)    { Dir.mktmpdir('cli_spec_') }
  let(:runner) { double('runner', run: nil) }
  let(:game)   { double('game', name: 'test', sessions_dir: tmp, reports_dir: tmp, runner_class: runner_class, game_state_class: nil) }
  let(:runner_class) { double('runner class', resume: runner) }

  after { FileUtils.rm_rf(tmp) }
  let(:client) { instance_double(PlaiTester::Agents::OllamaClient, model_names: ['p-model:latest']) }

  before do
    allow(PlaiTester::Agents::OllamaClient).to receive(:new).and_return(client)
    allow($stdout).to receive(:print)
    allow($stdout).to receive(:puts)
  end

  it 'preflights only the model names, not other options such as --think' do
    expect(client).to receive(:chat).once.with(hash_including(model: 'p-model'))

    described_class.new(game).run(%w[preflight --model p-model --think])
  end

  it 'resumes with the session\'s own player model unless --model is given' do
    FileUtils.mkdir_p(File.join(tmp, 'abc'))
    File.write(File.join(tmp, 'abc', 'state.json'), JSON.generate('game_state' => { 'custom' => { 'player_model' => 'p-model' } }))

    expect(runner_class).to receive(:resume).with(hash_including(models: hash_including(player: 'p-model'))).and_return(runner)
    described_class.new(game).run(%w[resume abc --skip-preflight])
  end

  context 'with a player count in the rules' do
    let(:game) { double('game', name: 'test', sessions_dir: tmp, reports_dir: tmp, runner_class: runner_class, game_state_class: nil, players: %w[A B], rules_file: rules_file) }
    let(:runner_class) { double('runner class', new: runner) }
    let(:runner) { double('runner', run: nil) }
    let(:rules_file) do
      File.join(tmp, 'rules.json').tap { |path| File.write(path, JSON.generate('game' => { 'name' => 'T', 'player_count' => { 'min' => 2, 'max' => 4, 'default' => 3 } })) }
    end

    it 'seats the default number of players' do
      expect(runner_class).to receive(:new).with(hash_including(players: ['Player 1', 'Player 2', 'Player 3']))

      described_class.new(game).run(%w[start --skip-preflight])
    end

    it 'seats --players N players' do
      expect(runner_class).to receive(:new).with(hash_including(players: ['Player 1', 'Player 2', 'Player 3', 'Player 4']))

      described_class.new(game).run(%w[start --players 4 --skip-preflight])
    end

    it 'refuses a player count outside the rules' do
      expect { described_class.new(game).run(%w[start --players 5 --skip-preflight]) }.to raise_error(SystemExit).and output(/5 players is outside 2-4/).to_stderr
    end
  end

  describe '.start' do
    let(:games_dir) { Dir.mktmpdir('games_') }

    before { PlaiTester.games_dir = games_dir }
    after do
      PlaiTester.games_dir = nil
      FileUtils.rm_rf(games_dir)
    end

    it 'names the available games when given no game' do
      expect { described_class.start([]) }.to raise_error(SystemExit).and output(/<game> <command>/).to_stderr
    end

    it 'refuses an unknown game' do
      expect { described_class.start(%w[nope list]) }.to raise_error(SystemExit).and output(/Unknown game "nope"/).to_stderr
    end
  end
end
