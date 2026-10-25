require 'spec_helper'

RSpec.describe PlaiTestr::Examples do
  let(:tmp)  { Dir.mktmpdir('examples_') }

  before { PlaiTestr::Generator.new(out: StringIO.new).app(File.join(tmp, 'app')) }
  after  { FileUtils.rm_rf(tmp) }

  def app_game(name) = File.join(tmp, 'app', 'games', name)

  it 'stamps every example game with the checksum of its template' do
    described_class.names.each do |name|
      expect(described_class.stamp_for(app_game(name))).to include('example' => name, 'version' => PlaiTestr::VERSION,
                                                                   'checksum' => described_class.template_checksum(name))
    end
  end

  it 'replaces an example that has not been edited' do
    expect(described_class.replaceable?(app_game('hearts'))).to be(true)
    expect(described_class.current?(app_game('hearts'))).to be(true)
  end

  it 'ignores sessions, reports and hidden files' do
    %w[sessions/x/state.json reports/x.md .DS_Store].each do |path|
      FileUtils.mkdir_p(File.dirname(File.join(app_game('hearts'), path)))
      File.write(File.join(app_game('hearts'), path), 'output')
    end

    expect(described_class.replaceable?(app_game('hearts'))).to be(true)
  end

  it 'keeps an edited example, so a new version goes alongside' do
    File.write(File.join(app_game('hearts'), 'data', 'rules.md'), "\nHouse rule.", mode: 'a')

    expect(described_class.replaceable?(app_game('hearts'))).to be(false)
  end

  it 'counts an added file as an edit' do
    File.write(File.join(app_game('gin_rummy'), 'spec', 'house_rules_spec.rb'), '')

    expect(described_class.replaceable?(app_game('gin_rummy'))).to be(false)
  end

  it 'is out of date once it differs from the installed template' do
    File.write(File.join(app_game('hearts'), 'NOTES.md'), 'old notes')

    expect(described_class.current?(app_game('hearts'))).to be(false)
  end
end
