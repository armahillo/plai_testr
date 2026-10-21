require 'spec_helper'
require 'open3'

RSpec.describe PlaiTestr::Generator do
  let(:tmp)       { Dir.mktmpdir('generator_') }
  let(:app)       { File.join(tmp, 'my_playtests') }
  let(:generator) { described_class.new(out: StringIO.new) }

  after { FileUtils.rm_rf(tmp) }

  describe '#app' do
    before { generator.app(app) }

    it 'creates an app with both example games' do
      expect(Dir.glob('**/*', File::FNM_DOTMATCH, base: app)).to include(
        '.gitignore', '.rspec', 'AGENTS.md', 'CLAUDE.md', 'Gemfile', 'README.md', 'config/plai_testr.rb', 'spec/spec_helper.rb',
        'games/hearts/lib/hearts.rb', 'games/gin_rummy/lib/gin_rummy.rb', 'games/hearts/data/personas.yml', 'games/hearts/data/bots.yml'
      )
    end

    it 'bundles the installed gem by version' do
      expect(File.read(File.join(app, 'Gemfile'))).to include("gem 'plai_testr', '~> #{PlaiTestr::VERSION[/\A\d+\.\d+/]}'")
    end

    it 'refuses a directory that is not empty' do
      expect { generator.app(app) }.to raise_error(PlaiTestr::UsageError, /not empty/)
    end
  end

  describe '#game' do
    let(:games_dir) { File.join(tmp, 'games') }

    it 'creates a game skeleton named after the game' do
      generator.game('dice_race', games_dir: games_dir)

      expect(Dir.glob('**/*', base: File.join(games_dir, 'dice_race')).select { |f| f.end_with?('.rb', '.json', '.md', '.yml') }).to contain_exactly(
        'lib/dice_race.rb', 'lib/dice_race/session/runner.rb', 'lib/dice_race/bot.rb', 'lib/dice_race/state/game_state.rb',
        'data/rules.json', 'data/rules.md', 'data/personas.yml', 'data/bots.yml', 'spec/session/runner_spec.rb'
      )
      expect(File.read(File.join(games_dir, 'dice_race/lib/dice_race.rb'))).to include("PlaiTestr.register('dice_race'", 'DiceRace::Session::Runner')
      expect(JSON.parse(File.read(File.join(games_dir, 'dice_race/data/rules.json'))).dig('game', 'name')).to eq('Dice Race')
    end

    it 'refuses names that are not snake_case' do
      expect { generator.game('Dice-Race', games_dir: games_dir) }.to raise_error(PlaiTestr::UsageError, /snake_case/)
    end

    it 'refuses a game that already exists' do
      generator.game('dice_race', games_dir: games_dir)

      expect { generator.game('dice_race', games_dir: games_dir) }.to raise_error(PlaiTestr::UsageError, /already exists/)
    end
  end

  it 'generates an app whose specs pass, including a new game' do
    generator.app(app)
    generator.game('dice_race', games_dir: File.join(app, 'games'))

    out, status = Open3.capture2e('ruby', '-I', File.expand_path('../../lib', __dir__), Gem.bin_path('rspec-core', 'rspec'), chdir: app)

    expect(status).to be_success, out
    expect(out).to match(/0 failures, 2 pending/)
  end
end
