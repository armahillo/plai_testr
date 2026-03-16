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
    via Ollama, records turn-by-turn transcripts with reasoning, and generates
    playtest reports to help game designers assess balance and gameplay issues.
  DESC

  spec.files         = Dir['lib/**/*.rb', 'rules/**/*', 'bin/*']
  spec.executables   = ['plai_tester']
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.1'

  spec.add_development_dependency 'rake',  '~> 13'
  spec.add_development_dependency 'rspec', '~> 3'
end
