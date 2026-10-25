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

  it 'refuses an option the command does not take, and shows the ones it does' do
    expect { described_class.new(game).run(%w[play --games 5]) }.to raise_error(PlaiTestr::UsageError, /invalid option: --games.*Usage: plai_testr counting play/m)
  end

  it 'resumes through the runner class' do
    allow(runner).to receive(:data).and_return('mode' => 'bot')
    expect(runner_class).to receive(:resume).with(game, 'abc', out: $stdout, verbose: nil).and_return(runner)

    described_class.new(game).run(%w[resume abc])
  end

  describe '.start' do
    it 'shows the usage when given no arguments' do
      expect { described_class.start([]) }.to output(/plai_testr <game> <command>/).to_stdout
    end

    it 'lists the games in the app' do
      FileUtils.mkdir_p(File.join(game.root, 'lib'))
      FileUtils.touch(File.join(game.root, 'lib', 'counting.rb'))

      expect { described_class.start(%w[games]) }.to output(/\Acounting\s+T v1\n\z/).to_stdout
    end

    it 'shows only the options a command takes' do
      expect { described_class.start(%w[help botrun]) }.to output(/--games N.*--personas LIST.*"all"/m).to_stdout
      expect { described_class.start(%w[help botrun]) }.not_to output(/--model/).to_stdout
    end

    it 'shows a command\'s options for --help anywhere after the game' do
      expect { described_class.start(%w[hearts play --seed 3 --help]) }.to output(/Usage: plai_testr hearts play \[options\].*--seed N/m).to_stdout
    end

    it 'shows the version' do
      expect { described_class.start(%w[--version]) }.to output("plai_testr #{PlaiTestr::VERSION}\n").to_stdout
    end

    it 'refuses an unknown command' do
      expect { described_class.start(%w[help hearts dance]) }.to raise_error(SystemExit).and output(/Unknown command: hearts dance/).to_stderr
    end

    it 'prints the message of a PlaiTestr error without a backtrace' do
      expect { described_class.start(%w[nope list]) }.to raise_error(SystemExit).and output(/Unknown game "nope"/).to_stderr
    end
  end
end
