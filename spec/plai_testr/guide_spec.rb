require 'spec_helper'

RSpec.describe PlaiTestr::Guide do
  let(:app)  { Dir.mktmpdir('guide_') }
  let(:link) { File.join(app, '.plai_testr', 'gem') }

  after { FileUtils.rm_rf(app) }

  it 'links the app to the installed gem, whose guide sits at a fixed path' do
    described_class.link(app)

    expect(File.readlink(link)).to eq(described_class::ROOT)
    expect(File.read(File.join(app, described_class::GUIDE))).to start_with('# PlAI Testr agent guide')
  end

  it 'repoints a link left by another gem version' do
    FileUtils.mkdir_p(File.dirname(link))
    File.symlink(Dir.mktmpdir('old_gem_'), link)

    described_class.link(app)

    expect(File.readlink(link)).to eq(described_class::ROOT)
  end

  it 'copies the docs where symlinks are unavailable' do
    allow(File).to receive(:symlink).and_raise(NotImplementedError)

    described_class.link(app)

    expect(File.symlink?(link)).to be(false)
    expect(File.exist?(File.join(app, described_class::GUIDE))).to be(true)
  end
end
