require_relative 'lib/plai_testr/version'

Gem::Specification.new do |spec|
  spec.name     = 'plai_testr'
  spec.version  = PlaiTestr::VERSION
  spec.authors  = ['Aaron H']
  spec.email    = ['armahillo@gmail.com']
  spec.summary  = 'Automated tabletop game playtesting using local LLM agents'
  spec.license  = 'MIT'
  spec.homepage = 'https://aaronh.games/tools/plai_testr/'
  source        = 'https://github.com/armahillo/plai_testr'

  spec.description = <<~DESC.strip
    PlAI Testr mediates sessions of tabletop games between LLM agents running locally
    via Ollama. The game lists every legal move as a numbered menu and the model picks
    one. It records turn-by-turn transcripts with reasoning, checkpoints for resuming,
    and generates playtest reports to help game designers assess balance and gameplay issues.
  DESC

  spec.metadata = {
    'homepage_uri'          => spec.homepage,
    'source_code_uri'       => source,
    'changelog_uri'         => "#{source}/blob/main/CHANGELOG.md",
    'bug_tracker_uri'       => "#{source}/issues",
    'rubygems_mfa_required' => 'true'
  }

  spec.files         = Dir['lib/**/*.rb', 'bin/*', 'docs/**/*.md', 'README.md', 'LICENSE.txt', 'CHANGELOG.md'] + Dir.glob('templates/**/*', File::FNM_DOTMATCH).reject { |f| File.directory?(f) }
  spec.bindir        = 'bin'
  spec.executables   = ['plai_testr']
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.4'

  spec.add_dependency 'csv', '~> 3.3'

  spec.add_development_dependency 'rake',  '~> 13'
  spec.add_development_dependency 'rspec', '~> 3'
end
