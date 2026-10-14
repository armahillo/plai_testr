require_relative 'lib/version'

Gem::Specification.new do |spec|
  spec.name     = 'plai_tester'
  spec.version  = PlaiTester::VERSION
  spec.authors  = ['Aaron H']
  spec.summary  = 'Automated board game playtesting using local LLM agents'
  spec.license  = 'MIT'
  spec.homepage = ''  # TODO: add before publishing to RubyGems

  spec.description = <<~DESC.strip
    PlaiTester mediates sessions of board games between LLM agents running locally
    via Ollama. The game lists every legal move as a numbered menu and the model picks
    one. It records turn-by-turn transcripts with reasoning, checkpoints for resuming,
    and generates playtest reports to help game designers assess balance and gameplay issues.
  DESC

  spec.files         = Dir['lib/**/*.rb', 'rules/**/*']
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.1'

  spec.add_development_dependency 'rake',  '~> 13'
  spec.add_development_dependency 'rspec', '~> 3'
end
