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
      expect(error.message).to include('game.version is required', 'min <= default <= max', "Deck 'values' must be an array")
    end
  end

  it 'requires a game section' do
    expect(described_class.validate({})).to eq(["'game' must be an object with a name and version"])
  end
end
