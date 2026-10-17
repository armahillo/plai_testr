require 'spec_helper'

RSpec.describe PlaiTester::Game do
  let(:games_dir) { Dir.mktmpdir('games_') }

  before do
    FileUtils.mkdir_p(File.join(games_dir, 'nim', 'lib'))
    File.write(File.join(games_dir, 'nim', 'lib', 'nim.rb'), <<~RUBY)
      PlaiTester.register('nim', runner_class: PlaiTester::Session::Runner, game_state_class: PlaiTester::State::GameState)
    RUBY
    FileUtils.mkdir_p(File.join(games_dir, 'notes'))
    PlaiTester.games_dir = games_dir
  end

  after do
    PlaiTester.games_dir = nil
    PlaiTester.registry.delete('nim')
    FileUtils.rm_rf(games_dir)
  end

  it 'finds every game under games_dir that has an entry file' do
    expect(PlaiTester.names).to eq(['nim'])
  end

  it 'loads a registered game with its paths and classes' do
    game = PlaiTester.load('nim')

    expect(game).to have_attributes(name: 'nim', runner_class: PlaiTester::Session::Runner, players: ['Player 1', 'Player 2'])
    expect(game.rules_file).to eq(File.join(games_dir, 'nim', 'data', 'rules.json'))
    expect(game.sessions_dir).to eq(File.join(games_dir, 'nim', 'sessions'))
  end

  it 'explains which games exist when asked for an unknown one' do
    expect { PlaiTester.load('nope') }.to raise_error(ArgumentError, /Available: nim/)
  end
end
