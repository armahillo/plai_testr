require 'erb'
require 'pathname'

module PlaiTestr
  class Generator
    TEMPLATES = File.expand_path('../../templates', __dir__)
    GAME_NAME = /\A[a-z][a-z0-9_]*\z/

    def initialize(out: $stdout)
      @out = out
    end

    def app(dir)
      root = File.expand_path(dir)
      raise UsageError, "#{dir} already exists and is not empty" if Dir.exist?(root) && !Dir.empty?(root)

      copy(File.join(TEMPLATES, 'app'), root, app_name: File.basename(root), version: VERSION.split('.').first(2).join('.'))
      Dir.children(File.join(TEMPLATES, 'examples')).sort.each do |example|
        copy(File.join(TEMPLATES, 'examples', example), File.join(root, 'games', example))
      end
      Guide.link(root)
      root
    end

    def game(name, games_dir: PlaiTestr.games_dir)
      raise UsageError, "Game names are lowercase snake_case, like my_game (got #{name.inspect})" unless name.match?(GAME_NAME)
      raise UsageError, "#{name} is a plai_testr command; choose another game name" if CLI::APP_COMMANDS.key?(name)

      root  = File.join(games_dir, name)
      words = name.split('_').map(&:capitalize)
      raise UsageError, "#{root} already exists" if File.exist?(root)

      copy(File.join(TEMPLATES, 'game'), root, name: name, module_name: words.join, title: words.join(' '))
      root
    end

    private

    def copy(source, target, **locals)
      Dir.glob('**/*', File::FNM_DOTMATCH, base: source).sort.each do |path|
        from = File.join(source, path)
        next if File.directory?(from)

        to = File.join(target, path.gsub('__name__', locals[:name].to_s).delete_suffix('.erb'))
        FileUtils.mkdir_p(File.dirname(to))
        File.write(to, path.end_with?('.erb') ? ERB.new(File.read(from), trim_mode: '-').result_with_hash(locals) : File.read(from))
        File.chmod(File.stat(from).mode, to)
        @out.puts "  create  #{Pathname(to).relative_path_from(Dir.pwd)}"
      end
    end
  end
end
