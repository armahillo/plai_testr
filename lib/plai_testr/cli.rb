module PlaiTestr
  class CLI
    COMMANDS = {
      'play'      => ['',             'Play one game with model players (runs preflight first)'],
      'botrun'    => ['',             'Play many games with bot rules only (no model), then report'],
      'resume'    => ['<session_id>', 'Resume an interrupted session'],
      'debrief'   => ['<session_id>', 'Ask the players of a completed session the debrief questions again, then rebuild its report'],
      'preflight' => ['',             'Check Ollama, pull and warm up the models, measure the prompt, lint with bot games'],
      'compare'   => ['',             'Compare completed games by model and host'],
      'list'      => ['',             'List sessions']
    }.freeze
    APP_COMMANDS = {
      'new'      => ['<directory>',     'Create a playtesting app with example games'],
      'generate' => ['game <name>',     'Add a game skeleton under games/<name>'],
      'games'    => ['',                'List the games in this app'],
      'help'     => ['[<command>]',     'Show this help, or the options for one command'],
      'version'  => ['',                'Show the PlAI Testr version']
    }.freeze
    GAME_COMMANDS  = %w[play botrun resume debrief preflight].freeze
    HELP_FLAGS     = %w[-h --help].freeze
    PROGRESS_EVERY = 50

    OPTIONS = {
      seed:           ['--seed N', Integer, { 'play' => 'Seed for shuffles and dice (default: random 1-100, printed)',
                                              'preflight' => 'Seed for the lint games (default 1)' }, ->(o, v) { o[:seed] = v }],
      games:          ['--games N', Integer, 'Number of games, seeds 1..N (default 100)', ->(o, v) { o[:games] = v }],
      seeds:          ['--seeds LIST', Array, 'Comma-separated seeds, instead of --games', ->(o, v) { o[:seeds] = v.map { |s| Integer(s) } }],
      model:          ['--model M', -> { "Ollama model for the players (default #{PlaiTestr.config.player_model})" }, ->(o, v) { o[:player] = v }],
      mode:           ['--mode M', Session::Runner::MODES, 'llm (default): the model decides; hybrid: bot rules play obvious moves; bot: no model',
                       ->(o, v) { o[:mode] = v }],
      think:          ['--think', 'Let the player model think before each choice (slower; stronger play)', ->(o, _) { o[:think] = true }],
      referee:        ['--referee M', 'Ollama model for yes/no rulings (only for games that ask for them)', ->(o, v) { o[:referee] = v }],
      players:        ['--players N', Integer, "Number of players, within the game's player_count (default: the game's default)",
                       ->(o, v) { o[:player_count] = v }],
      personas:       ['--personas LIST', Array, { 'botrun' => 'One persona per player, comma-separated; * for random, "all" to cycle every arrangement (default: random)',
                                                   'default' => 'One persona per player, comma-separated; * for random (default: random)' },
                       ->(o, v) { o[:personas] = v }],
      debrief_model:  ['--debrief-model M', "Ollama model for the end-of-game debrief (default: the player model)", ->(o, v) { o[:debrief] = v }],
      debrief_think:  ['--debrief-think', 'Let the model think before answering the debrief (slower; fewer made-up answers)', ->(o, _) { o[:debrief_think] = true }],
      redebrief_model: ['--model M', "Ollama model for the debrief (default: the session's player model)", ->(o, v) { o[:debrief] = v }],
      redebrief_think: ['--think', 'Let the model think before answering (slower; fewer made-up answers)', ->(o, _) { o[:debrief_think] = true }],
      skip_preflight: ['--skip-preflight', 'Skip the Ollama checks and the lint games', ->(o, _) { o[:preflight] = false }],
      since:          ['--since ID', 'Only sessions whose id sorts at or after ID (e.g. 20261011-170000)', ->(o, v) { o[:since] = v }],
      quiet:          ['--quiet', 'Show only a progress line and the result', ->(o, _) { o[:quiet] = true }],
      verbose:        ['--verbose', { 'botrun' => 'Show every game', 'default' => 'Also show the raw model output and timings' }, ->(o, _) { o[:verbose] = true }]
    }.freeze
    COMMAND_OPTIONS = {
      'play'      => %i[seed model mode think referee players personas debrief_model debrief_think skip_preflight quiet verbose],
      'botrun'    => %i[games seeds players personas quiet verbose],
      'resume'    => %i[skip_preflight quiet verbose],
      'debrief'   => %i[redebrief_model redebrief_think skip_preflight verbose],
      'preflight' => %i[seed model think referee players personas],
      'compare'   => %i[since],
      'list'      => []
    }.freeze

    def self.start(argv)
      $stdout.sync = true
      PlaiTestr.load_config
      Guide.link if Dir.exist?(PlaiTestr.games_dir)

      case argv
      in [] | ['help'] then puts usage
      in [*, '-h' | '--help', *] then puts help((argv - HELP_FLAGS).take_while { |word| !word.start_with?('-') }.first(2))
      in ['help', *words] then puts help(words)
      in ['version'] | ['--version'] then puts "plai_testr #{VERSION}"
      in ['games'] then puts games
      in ['new', dir]
        Generator.new.app(dir)
        puts "\nNext:\n  cd #{dir}\n  bundle install\n  bundle exec plai_testr hearts botrun --games 100\n  bundle exec plai_testr hearts play"
      in ['generate', 'game', name]
        Generator.new.game(name)
        puts "\nNext: describe the game in games/#{name}/data/, implement games/#{name}/lib/#{name}/session/runner.rb, then run bundle exec rspec games/#{name}"
      in [String => name, *rest] unless name.start_with?('-')
        new(PlaiTestr.load(name)).run(rest)
      else
        abort usage
      end
    rescue Error => e
      raise if e.is_a?(MoveError) || ENV['PLAI_TESTR_DEBUG']

      abort e.message
    end

    def self.usage
      names = PlaiTestr.names

      <<~USAGE
        Usage:
        #{rows(APP_COMMANDS.transform_keys { |c| "plai_testr #{c}" })}
          plai_testr <game> <command> [options]

        Game commands:
        #{rows(COMMANDS)}

        Games: #{names.empty? ? 'none here (run plai_testr new <directory> to create an app)' : names.join(', ')}

        Options for a command: plai_testr help <command>, or plai_testr <game> <command> --help
      USAGE
    end

    def self.game_usage(game)
      <<~USAGE
        Usage: plai_testr #{game} <command> [options]

        Commands:
        #{rows(COMMANDS)}

        Options for a command: plai_testr #{game} <command> --help
      USAGE
    end

    def self.help(words)
      case words
      in [] then usage
      in [String => command, *] if APP_COMMANDS.key?(command)
        args, text = APP_COMMANDS.fetch(command)
        "Usage: plai_testr #{command} #{args}".rstrip + "\n\n#{text}\n"
      in [String => command] if COMMANDS.key?(command) then parser_for(command, game: '<game>').help
      in [String => game, String => command] if COMMANDS.key?(command) then parser_for(command, game: game).help
      in [String => game] then game_usage(game)
      else raise UsageError, "Unknown command: #{words.join(' ')}\n\n#{usage}"
      end
    end

    def self.games
      return 'No games here (run plai_testr new <directory> to create an app).' if PlaiTestr.names.empty?

      PlaiTestr.names.map do |name|
        rules = RulesLoader.load(File.join(PlaiTestr.games_dir, name, 'data', 'rules.json'))
        format('%-20s %s v%s', name, rules.dig('game', 'name'), rules.dig('game', 'version'))
      end.join("\n")
    end

    def self.parser_for(command, game:, options: {})
      args, text = COMMANDS.fetch(command)

      OptionParser.new do |o|
        o.banner = "Usage: plai_testr #{game} #{command} #{args}".rstrip + " [options]\n\n#{text}\n\nOptions:"
        COMMAND_OPTIONS.fetch(command).each do |key|
          *spec, describe, set = OPTIONS.fetch(key)
          description = case describe
                        when Hash then describe.fetch(command) { describe.fetch('default') }
                        when Proc then describe.call
                        else describe
                        end
          o.on(*spec, description) { |v| set.call(options, v) }
        end
        o.separator('    (none)') if COMMAND_OPTIONS.fetch(command).empty?
      end
    end

    def self.rows(commands) = commands.map { |name, (args, text)| format('  %-38s %s', "#{name} #{args}".rstrip, text) }.join("\n")

    def initialize(game)
      @game    = game
      @options = {
        player:    PlaiTestr.config.player_model,
        referee:   PlaiTestr.config.referee_model,
        think:     false,
        mode:      'llm',
        games:     100,
        seeds:     [],
        preflight: true
      }

      PlaiTestr.sessions_dir = game.sessions_dir
      PlaiTestr.reports_dir  = game.reports_dir
    end

    def run(argv)
      command, *rest = argv
      return puts(self.class.game_usage(@game.name)) unless COMMANDS.key?(command)

      args = self.class.parser_for(command, game: @game.name, options: @options).parse(rest)
      @game.check!.each { |note| warn "  [warning] #{note}" } if GAME_COMMANDS.include?(command)

      case command
      when 'play'      then play
      when 'botrun'    then botrun
      when 'resume'    then resume(args.first)
      when 'debrief'   then debrief(args.first)
      when 'preflight' then Preflight.new(game: @game, players: seats, models: models, personas: @options[:personas]).run(@options[:seed] || 1)
      when 'compare'   then compare
      when 'list'      then list
      end
    rescue OptionParser::ParseError => e
      raise UsageError, "#{e.message}\n\n#{self.class.parser_for(command, game: @game.name).help}"
    end

    private

    def models = { player: @options[:player], referee: @options[:referee], think: @options[:think], debrief: @options[:debrief], debrief_think: @options[:debrief_think] }

    def seats
      range = @game.rules.dig('game', 'player_count')
      count = @options[:player_count] || range&.dig('default')
      return @game.players unless count
      raise UsageError, "#{@game.name}: #{count} players is outside #{range['min']}-#{range['max']}" if range && !count.between?(range['min'], range['max'])

      Array.new(count) { |i| "Player #{i + 1}" }
    end

    def preflight? = @options[:preflight] && @options[:mode] != 'bot'

    def output = @options[:quiet] ? StringIO.new : $stdout

    def play
      seed    = @options[:seed] || rand(1..100)
      players = seats
      @game.personas.check_request(@options[:personas], players: players.length)
      Preflight.new(game: @game, players: players, models: models, personas: @options[:personas], out: output).run(seed) if preflight?

      runner = @game.runner_class.new(game: @game, players: players, models: models, seed: seed, mode: @options[:mode],
                                      personas: @options[:personas], out: output, verbose: @options[:verbose])
      play_session(runner)
    end

    def resume(session_id)
      raise UsageError, "Usage: plai_testr #{@game.name} resume <session_id>" unless session_id

      runner = @game.runner_class.resume(@game, session_id, out: output, verbose: @options[:verbose])
      session_models = { player: runner.data['player_model'], referee: runner.data['referee_model'] }
      Preflight.new(game: @game, players: runner.game_state.players, models: session_models, out: output).ollama! if @options[:preflight] && runner.data['mode'] != 'bot'
      play_session(runner)
    end

    def debrief(session_id)
      raise UsageError, "Usage: plai_testr #{@game.name} debrief <session_id>" unless session_id

      runner = @game.runner_class.redebrief(@game, session_id, models: models, out: $stdout, verbose: @options[:verbose])
      Preflight.new(game: @game, players: runner.game_state.players, models: { player: runner.data['player_model'], debrief: models[:debrief] }).ollama! if @options[:preflight]
      runner.debrief!
      puts "\nReport: #{runner.report_path}"
    end

    def play_session(runner)
      started = clock
      runner.run { |decisions| progress("decision #{decisions} · #{duration(clock - started)}", decisions) if @options[:quiet] }
      if @options[:quiet]
        puts
        puts runner.status == 'completed' ? "Game complete (seed #{runner.seed}). Report: #{runner.report_path}" : "Saved. Resume with: plai_testr #{@game.name} resume #{runner.session_id}"
      end
      exit 130 if runner.status == 'interrupted'
    end

    def botrun
      seeds   = @options[:seeds].empty? ? (1..@options[:games]).to_a : @options[:seeds]
      started = clock
      botrun  = Botrun.new(game: @game, players: seats, seeds: seeds, personas: @options[:personas], out: (@options[:verbose] ? $stdout : nil))
      results = botrun.run { |done| progress("#{done}/#{seeds.length} games", done) }
      rules   = @game.rules

      markdown = @game.botrun_report_class.new(results, game: rules.dig('game', 'name'), version: rules.dig('game', 'version'),
                                                        seconds: clock - started, personas: @options[:personas], planned: seeds.length).to_markdown
      markdown = Reporter::Tables.align(markdown)
      FileUtils.mkdir_p(PlaiTestr.reports_dir)
      path = File.join(PlaiTestr.reports_dir, "botrun-#{Time.now.strftime('%Y%m%d-%H%M%S')}.md")
      File.write(path, markdown)
      puts @options[:quiet] ? "\nReport: #{path}" : "\n\n#{markdown}\nSaved: #{path}"
    end

    def compare
      markdown = Reporter::Tables.align(@game.comparison_class.new(PlaiTestr.sessions_dir, since: @options[:since]).to_markdown)
      FileUtils.mkdir_p(PlaiTestr.reports_dir)
      path = File.join(PlaiTestr.reports_dir, "comparison-#{Time.now.strftime('%Y%m%d-%H%M%S')}.md")
      File.write(path, markdown)
      puts markdown, "\nSaved: #{path}"
    end

    def list
      sessions = Session::Manager.list
      return puts 'No sessions found.' if sessions.empty?

      puts format('%-24s  %-12s  %s', 'SESSION_ID', 'STATUS', 'SAVED_AT')
      sessions.each { |s| puts format('%-24s  %-12s  %s', *s.values_at('session_id', 'status', 'saved_at')) }
    end

    def progress(text, count)
      if $stdout.tty?
        print "\r  #{text}\e[K"
      elsif (count % PROGRESS_EVERY).zero?
        puts "  #{text}"
      end
    end

    def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def duration(seconds) = format('%dm %02ds', seconds / 60, seconds % 60)
  end
end
