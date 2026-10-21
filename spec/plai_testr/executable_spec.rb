require 'spec_helper'
require 'open3'

RSpec.describe 'bin/plai_testr' do
  let(:exe)       { File.expand_path('../../bin/plai_testr', __dir__) }
  let(:lib)       { File.expand_path('../../lib', __dir__) }
  let(:app)       { Dir.mktmpdir('app_') }

  after { FileUtils.rm_rf(app) }

  it 'runs the CLI against the games in the current directory' do
    FileUtils.mkdir_p(File.join(app, 'games', 'nim', 'lib'))
    File.write(File.join(app, 'games', 'nim', 'lib', 'nim.rb'), '')

    _out, err, status = Open3.capture3('ruby', '-I', lib, exe, chdir: app)

    expect(status).not_to be_success
    expect(err).to include('plai_testr <game> <command>', 'games: nim')
  end
end
