module PlaiTestr
  class CLI
    COMMANDS       = %w[play botrun resume preflight compare list].freeze
    GAME_COMMANDS  = %w[play botrun resume preflight].freeze
    PROGRESS_EVERY = 50

    def self.start(argv)
      $stdout.sync = true
      PlaiTestr.load_config

      case argv
      in ['new', dir]
        Generator.new.app(dir)
        puts "\nNext:\n  cd #{dir}\n  bundle install\n  bundle exec plai_testr hearts botrun --games 100\n  bundle exec plai_testr hearts play"
      in ['generate', 'game', name]
        Generator.new.game(name)
        puts "\nNext: describe the game in games/#{name}/data/, implement games/#{name}/lib/#{name}/session/runner.rb, then run bundle exec rspec games/#{name}"
      in [String => name, *rest] unless name.start_with?('-')
        new(PlaiTestr.load(name)).run(rest)
      else
        abort <<~USAGE
          Usage:
            #{File.basename($PROGRAM_NAME)} new <directory>              Create a playtesting app with example games
            #{File.basename($PROGRAM_NAME)} generate game <name>         Add a game skeleton under games/<name>
            #{File.basename($PROGRAM_NAME)} <game> <command> [options]   Play a game (games: #{PlaiTestr.names.join(', ')})
        USAGE
      end
    rescue Error => e
      raise if e.is_a?(MoveError) || ENV['PLAI_TESTR_DEBUG']

      abort e.message
    end

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
      args    = parser.parse(argv)
      command = args.first
      return puts(parser.help) unless COMMANDS.include?(command)

      @game.check!.each { |note| warn "  [warning] #{note}" } if GAME_COMMANDS.include?(command)

      case command
      when 'play'      then play
      when 'botrun'    then botrun
      when 'resume'    then resume(args[1])
      when 'preflight' then Preflight.new(game: @game, players: seats, models: models, personas: @options[:personas]).run(@options[:seed] || 1)
      when 'compare'   then compare
      when 'list'      then list
      end
    rescue OptionParser::ParseError => e
      raise UsageError, e.message
    end

    private

    def models = { player: @options[:player], referee: @options[:referee], think: @options[:think] }

    def parser
      @parser ||= OptionParser.new do |o|
        o.banner = <<~USAGE
          #{@game.name}: automated playtesting

          Commands:
            play    [--seed N] [--model M] [--think] [--mode M] [--players N] [--personas A,B] [--referee M]   Play one game
            botrun  [--games N | --seeds 1,2,3] [--players N] [--personas all|A,B]   Play many games with bot rules only (no model), then report
            resume  <session_id>                    Resume an interrupted session
            preflight                               Check Ollama, pull and warm up the models, measure the prompt, lint with bot games
            compare [--since ID]                    Compare completed games by model and host
            list                                    List sessions

          Options:
        USAGE
        o.on('--seed N', Integer, 'play: seed for shuffles and dice (default: random 1-100, printed)') { |v| @options[:seed] = v }
        o.on('--seeds LIST', Array, 'botrun: comma-separated seeds') { |v| @options[:seeds] = v.map { |s| Integer(s) } }
        o.on('--games N', Integer, 'botrun: number of games, seeds 1..N (default 100)') { |v| @options[:games] = v }
        o.on('--model M', "Ollama model for the players (default #{PlaiTestr.config.player_model})") { |v| @options[:player] = v }
        o.on('--mode M', Session::Runner::MODES, 'llm (default): the model decides; hybrid: bot rules play obvious moves; bot: no model') { |v| @options[:mode] = v }
        o.on('--think', 'Let the player model think before each choice (slower; stronger play)') { @options[:think] = true }
        o.on('--referee M', 'Ollama model for yes/no rulings (only for games that ask for them)') { |v| @options[:referee] = v }
        o.on('--players N', Integer, 'Number of players, within the game\'s player_count (default: the game\'s default)') { |v| @options[:player_count] = v }
        o.on('--personas LIST', Array, 'One persona per player, comma-separated, * for random (default: random); botrun also takes "all"') { |v| @options[:personas] = v }
        o.on('--skip-preflight', 'Skip the Ollama checks and the lint games') { @options[:preflight] = false }
        o.on('--since ID', 'compare: only sessions whose id sorts at or after ID (e.g. 20261011-170000)') { |v| @options[:since] = v }
        o.on('--quiet', 'Show only a progress line and the result') { @options[:quiet] = true }
        o.on('--verbose', 'Also show the raw model output and timings (play), or every game (botrun)') { @options[:verbose] = true }
      end
    end

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

    def play_session(runner)
      started = clock
      runner.run { |decisions| progress("decision #{decisions} · #{duration(clock - started)}", decisions) if @options[:quiet] }
      return unless @options[:quiet]

      puts
      puts runner.status == 'completed' ? "Game complete (seed #{runner.seed}). Report: #{runner.report_path}" : "Saved. Resume with: plai_testr #{@game.name} resume #{runner.session_id}"
    end

    def botrun
      seeds   = @options[:seeds].empty? ? (1..@options[:games]).to_a : @options[:seeds]
      started = clock
      botrun  = Botrun.new(game: @game, players: seats, seeds: seeds, personas: @options[:personas], out: (@options[:verbose] ? $stdout : nil))
      results = botrun.run { |done| progress("#{done}/#{seeds.length} games", done) }
      rules   = @game.rules

      markdown = @game.botrun_report_class.new(results, game: rules.dig('game', 'name'), version: rules.dig('game', 'version'),
                                                        seconds: clock - started, personas: @options[:personas], planned: seeds.length).to_markdown
      FileUtils.mkdir_p(PlaiTestr.reports_dir)
      path = File.join(PlaiTestr.reports_dir, "botrun-#{Time.now.strftime('%Y%m%d-%H%M%S')}.md")
      File.write(path, markdown)
      puts @options[:quiet] ? "\nReport: #{path}" : "\n\n#{markdown}\nSaved: #{path}"
    end

    def compare
      markdown = @game.comparison_class.new(PlaiTestr.sessions_dir, since: @options[:since]).to_markdown
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
