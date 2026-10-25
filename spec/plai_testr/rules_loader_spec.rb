require 'spec_helper'

RSpec.describe PlaiTestr::RulesLoader do
  let(:tmp)  { Dir.mktmpdir('rules_loader_spec_') }
  let(:path) { File.join(tmp, 'rules.json') }

  after { FileUtils.rm_rf(tmp) }

  def load(content)
    File.write(path, content.is_a?(String) ? content : JSON.generate(content))
    described_class.load(path)
  end

  it 'loads a valid rules file' do
    rules = load('game' => { 'name' => 'Nim', 'version' => '1.0', 'player_count' => { 'min' => 2, 'max' => 4, 'default' => 2 } })

    expect(rules.dig('game', 'name')).to eq('Nim')
  end

  it 'raises a RulesError when the file does not exist' do
    expect { described_class.load('/nonexistent/path.json') }.to raise_error(PlaiTestr::RulesError, /not found/)
  end

  it 'raises a RulesError naming the file when the JSON is invalid' do
    expect { load('{"game": ') }.to raise_error(PlaiTestr::RulesError, /rules\.json is not valid JSON/)
  end

  it 'lists every problem with the keys the gem reads' do
    rules = { 'game' => { 'name' => 'Nim', 'player_count' => { 'min' => 3, 'max' => 2, 'default' => 2 } },
              'components' => [{ 'name' => 'Deck', 'type' => 'card_deck', 'values' => {} }] }

    expect { load(rules) }.to raise_error(PlaiTestr::RulesError) do |error|
      expect(error.message).to include('game.version is required', 'min <= default <= max', 'Deck: must be a list of cards')
    end
  end

  describe 'component files in data/components/' do
    let(:game)       { { 'game' => { 'name' => 'Nim', 'version' => '1.0' } } }
    let(:components) { File.join(tmp, 'components').tap { |dir| FileUtils.mkdir_p(dir) } }

    def component(file, content) = File.write(File.join(components, file), content)

    it 'reads a CSV with a header row as a deck named after the file, with numbers as numbers' do
      component('cards.csv', "name,value,copies,note\nBlade,5,2,\nShield,1.5,1,blocks\n\n")

      expect(PlaiTestr::Deck.build(load(game), component: 'cards')).to eq([{ 'name' => 'Blade', 'value' => 5, 'uid' => 1 },
                                                                             { 'name' => 'Blade', 'value' => 5, 'uid' => 2 },
                                                                             { 'name' => 'Shield', 'value' => 1.5, 'note' => 'blocks', 'uid' => 3 }])
    end

    it 'reads YAML (with anchors) and JSON lists' do
      component('tiles.yml', "- &base\n  name: Forest\n  terrain: green\n- <<: *base\n  name: Grove\n")
      component('tokens.json', '[{ "name": "Coin" }]')

      expect(PlaiTestr::Deck.build(load(game), component: 'tiles').map { |t| t.values_at('name', 'terrain') }).to eq([%w[Forest green], %w[Grove green]])
      expect(PlaiTestr::Deck.build(load(game), component: 'tokens').map { |t| t['name'] }).to eq(['Coin'])
    end

    it 'names the file and entry for a card without fields or with bad copies' do
      component('cards.yml', "- name: Blade\n  copies: 0\n- just a string\n")

      expect { load(game) }.to raise_error(PlaiTestr::RulesError) do |error|
        expect(error.message).to include('cards.yml: entry 1 copies must be a whole number above 0', 'cards.yml: entry 2 must have fields')
      end
    end

    it 'refuses a file that is not a list' do
      component('cards.yml', "name: Blade\n")

      expect { load(game) }.to raise_error(PlaiTestr::RulesError, /cards\.yml: must be a list of cards/)
    end

    it 'refuses a component defined both in rules.json and in a file' do
      component('cards.yml', "- name: Blade\n")

      expect { load(game.merge('components' => [{ 'name' => 'cards', 'type' => 'card_deck', 'values' => [] }])) }
        .to raise_error(PlaiTestr::RulesError, /2 components are named cards/)
    end

    it 'reloads when a component file changes' do
      component('cards.yml', "- name: Blade\n")
      load(game)
      component('cards.yml', "- name: Shield\n")
      File.utime(Time.now + 5, Time.now + 5, File.join(components, 'cards.yml'))

      expect(PlaiTestr::Deck.build(described_class.load(path)).map { |c| c['name'] }).to eq(['Shield'])
    end
  end

  it 'requires a game section' do
    expect(described_class.validate({})).to eq(["'game' must be an object with a name and version"])
  end
end
