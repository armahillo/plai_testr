require 'spec_helper'

RSpec.describe Testr::Compiler::RulesLoader do
  let(:example_path) { File.join(Testr::RULES_DIR, 'example.json') }

  describe '.load' do
    it 'loads the example rules file without error' do
      rules = described_class.load(example_path)
      expect(rules).to be_a(Hash)
    end

    it 'injects _source_file into the loaded rules' do
      rules = described_class.load(example_path)
      expect(rules['_source_file']).to eq(File.expand_path(example_path))
    end

    it 'raises when the file does not exist' do
      expect { described_class.load('/nonexistent/path.json') }.to raise_error(/not found/)
    end

    it 'raises when required keys are missing' do
      bad_rules = { 'game' => { 'name' => 'Incomplete' } }
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:read).and_return(JSON.generate(bad_rules))

      expect { described_class.load('fake.json') }.to raise_error(/Missing required/)
    end
  end

  describe '.validate' do
    let(:valid_rules) do
      JSON.parse(File.read(example_path))
    end

    it 'returns no errors for a valid rules file' do
      expect(described_class.validate(valid_rules)).to be_empty
    end

    it 'returns an error for each missing required key' do
      errors = described_class.validate({})
      expect(errors.length).to eq(Testr::Compiler::RulesLoader::REQUIRED_KEYS.length)
    end
  end
end
