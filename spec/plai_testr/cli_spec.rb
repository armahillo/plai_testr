require 'spec_helper'

RSpec.describe PlaiTestr::CLI do
  let(:tmp)    { Dir.mktmpdir('cli_spec_') }
  let(:runner) { instance_double(PlaiTestr::Session::Runner, run: nil, status: 'completed', seed: 1, report_path: 'r.md', session_id: 'x') }
  let(:runner_class) { class_double(PlaiTestr::Session::Runner, new: runner) }
  let(:game) do
    build_game(runner_class, rules: { 'game' => { 'name' => 'T', 'version' => '1', 'player_count' => { 'min' => 2, 'max' => 4, 'default' => 3 } } })
  end

  before do
    PlaiTestr.games_dir = File.join(tmp, 'games')
    allow($stdout).to receive(:print)
    allow($stdout).to receive(:puts)
  end

  after do
    PlaiTestr.games_dir = nil
    FileUtils.rm_rf(tmp)
  end

  it 'plays one game with a random seed from 1 to 100 when none is given' do
    expect(runner_class).to receive(:new).with(hash_including(seed: be_between(1, 100))).and_return(runner)

    described_class.new(game).run(%w[play --skip-preflight])
  end

  it 'seats the default number of players' do
    expect(runner_class).to receive(:new).with(hash_including(players: ['Player 1', 'Player 2', 'Player 3']))

    described_class.new(game).run(%w[play --skip-preflight --seed 4])
  end

  it 'seats --players N players' do
    expect(runner_class).to receive(:new).with(hash_including(players: ['Player 1', 'Player 2', 'Player 3', 'Player 4']))

    described_class.new(game).run(%w[play --players 4 --skip-preflight])
  end

  it 'refuses a player count outside the rules' do
    expect { described_class.new(game).run(%w[play --players 5 --skip-preflight]) }.to raise_error(PlaiTestr::UsageError, /5 players is outside 2-4/)
  end

  it 'refuses personas for a game without any, before playing' do
    expect(runner_class).not_to receive(:new)

    expect { described_class.new(game).run(%w[play --personas a,b --skip-preflight]) }.to raise_error(PlaiTestr::PersonaError, /no personas/)
  end

  it 'exits with status 130 when the game was interrupted, so scripts can stop' do
    allow(runner).to receive(:status).and_return('interrupted')

    expect { described_class.new(game).run(%w[play --skip-preflight]) }.to raise_error(SystemExit) { |e| expect(e.status).to eq(130) }
  end

  it 'resumes through the runner class' do
    allow(runner).to receive(:data).and_return('mode' => 'bot')
    expect(runner_class).to receive(:resume).with(game, 'abc', out: $stdout, verbose: nil).and_return(runner)

    described_class.new(game).run(%w[resume abc])
  end

  describe '.start' do
    it 'names the available games when given no game' do
      expect { described_class.start([]) }.to raise_error(SystemExit).and output(/<game> <command>/).to_stderr
    end

    it 'prints the message of a PlaiTestr error without a backtrace' do
      expect { described_class.start(%w[nope list]) }.to raise_error(SystemExit).and output(/Unknown game "nope"/).to_stderr
    end
  end
end
