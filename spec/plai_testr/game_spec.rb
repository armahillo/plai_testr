require 'spec_helper'

RSpec.describe PlaiTestr::Game do
  let(:games_dir) { Dir.mktmpdir('games_') }

  before do
    FileUtils.mkdir_p(File.join(games_dir, 'nim', 'lib'))
    File.write(File.join(games_dir, 'nim', 'lib', 'nim.rb'), <<~RUBY)
      PlaiTestr.register('nim', runner_class: PlaiTestr::Session::Runner, game_state_class: PlaiTestr::State::GameState)
    RUBY
    FileUtils.mkdir_p(File.join(games_dir, 'notes'))
    PlaiTestr.games_dir = games_dir
  end

  after do
    PlaiTestr.games_dir = nil
    PlaiTestr.registry.delete('nim')
    FileUtils.rm_rf(games_dir)
  end

  it 'finds every game under games_dir that has an entry file' do
    expect(PlaiTestr.names).to eq(['nim'])
  end

  it 'loads a registered game with its paths and classes' do
    game = PlaiTestr.load('nim')

    expect(game).to have_attributes(name: 'nim', runner_class: PlaiTestr::Session::Runner, players: ['Player 1', 'Player 2'])
    expect(game.rules_file).to eq(File.join(games_dir, 'nim', 'data', 'rules.json'))
    expect(game.sessions_dir).to eq(File.join(games_dir, 'nim', 'sessions'))
  end

  it 'resolves a relative games_dir when it is set, not when it is read' do
    Dir.chdir(File.dirname(games_dir)) { PlaiTestr.games_dir = File.basename(games_dir) }

    expect(PlaiTestr.load('nim').name).to eq('nim')
  end

  it 'fingerprints its data and code, so a change is noticed' do
    game   = PlaiTestr.load('nim')
    before = game.fingerprint
    FileUtils.mkdir_p(File.join(games_dir, 'nim', 'data'))
    File.write(File.join(games_dir, 'nim', 'data', 'rules.json'), '{}')

    expect(game.fingerprint).not_to eq(before)
  end

  it 'reports a YAML syntax error in its data with the file name' do
    FileUtils.mkdir_p(File.join(games_dir, 'nim', 'data'))
    File.write(File.join(games_dir, 'nim', 'data', 'cards.yml'), "a: [1, 2\n")

    expect { PlaiTestr.load('nim').check! }.to raise_error(PlaiTestr::RulesError, /cards\.yml/)
  end

  it 'warns when a game gives its debrief no facts' do
    bare  = build_game(Class.new(PlaiTestr::Session::Runner), name: 'bare')
    facts = build_game(Class.new(PlaiTestr::Session::Runner) { def debrief_facts(_p) = { 'moves' => 1 } }, name: 'facts')
    stats = build_game(Class.new(PlaiTestr::Session::Runner) { def botrun_stats = { 'moves' => 1 } }, name: 'stats')

    expect(bare.check!).to include(/debriefs get no game facts/)
    expect(facts.check! + stats.check!).to be_empty
  end

  it 'explains which games exist when asked for an unknown one' do
    expect { PlaiTestr.load('nope') }.to raise_error(PlaiTestr::UsageError, /Available: nim/)
  end
end
