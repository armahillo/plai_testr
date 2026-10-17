module PlaiTester
  class CLI
    def initialize(game, ollama_host: ENV.fetch('PLAITESTER_OLLAMA_HOST', 'localhost'), ollama_port: ENV.fetch('PLAITESTER_OLLAMA_PORT', '11434').to_i)
      @game        = game
      @ollama_host = ollama_host
      @ollama_port = ollama_port
      @options     = {
        player:    ENV.fetch('PLAITESTER_PLAYER_MODEL', 'qwen3:8b'),
        referee:   ENV['PLAITESTER_REFEREE_MODEL'],
        think:     false,
        mode:      'llm',
        games:     100,
        seeds:     [],
        preflight: true
      }

      PlaiTester.sessions_dir = game.sessions_dir
      PlaiTester.reports_dir  = game.reports_dir
    end

    def run(argv)
      args = parser.parse(argv)

      case args[0]
      when 'preflight' then preflight!
      when 'start'     then start
      when 'batch'     then batch
      when 'resume'    then resume(args[1])
      when 'botrun'    then botrun
      when 'compare'   then compare
      when 'list'      then list
      else puts parser.help
      end
    end

    private

    def models = { player: @options[:player], referee: @options[:referee], think: @options[:think] }

    def parser
      @parser ||= OptionParser.new do |o|
        o.banner = <<~USAGE
          #{@game.name}: automated playtesting

          Commands:
            start   [--seed N] [--players N] [--model M] [--think] [--mode M] [--personas A,B]     Start one new session
            batch   --seeds 1,2,3 [--players N] [--model M] [--think] [--mode M] [--personas A,B]  Run several seeded sessions back to back
            botrun  [--games N | --seeds 1,2,3] [--players N] [--personas all|A,B]   Play many games with bot rules only (no model), then report
            resume  <session_id>                    Resume an interrupted session
            preflight                               Check Ollama and warm up the models
            compare [--since ID]                    Compare completed games by model and host
            list                                    List sessions

          Options:
        USAGE
        o.on('--seed N', Integer, 'Seed for setup shuffles (reproducible deals)') { |v| @options[:seeds] = [v] }
        o.on('--seeds LIST', Array, 'Comma-separated seeds for batch') { |v| @options[:seeds] = v.map { |s| Integer(s) } }
        o.on('--model M', 'Ollama model for the players (default qwen3:8b; resume keeps the session\'s model)') { |v| @options[:player] = v; @options[:player_set] = true }
        o.on('--mode M', Session::Runner::MODES, 'llm (default): the model decides; hybrid: bot rules play obvious moves; bot: no model') { |v| @options[:mode] = v }
        o.on('--games N', Integer, 'botrun: number of games, seeds 1..N (default 100)') { |v| @options[:games] = v }
        o.on('--think', 'Let the player model think before each choice (slower; stronger play)') { @options[:think] = true }
        o.on('--referee M', 'Ollama model for yes/no rulings (only for games that ask for them)') { |v| @options[:referee] = v }
        o.on('--players N', Integer, 'Number of players, within the game\'s player_count (default: the game\'s default)') { |v| @options[:player_count] = v }
        o.on('--personas LIST', Array, 'One persona per player, comma-separated (game-specific; default: random per seed); botrun also takes "all" to cycle every pairing') { |v| @options[:personas] = v }
        o.on('--skip-preflight', 'Do not check Ollama before running') { @options[:preflight] = false }
        o.on('--since ID', 'compare: only sessions whose id sorts at or after ID (e.g. 20261011-170000)') { |v| @options[:since] = v }
      end
    end

    # Confirms the Ollama server is reachable and the models are pulled, then loads each model
    # with a tiny request so the first real turn does not time out while the model loads.
    def preflight!
      client = Agents::OllamaClient.new(host: @ollama_host, port: @ollama_port)
      wanted = models.values_at(:player, :referee).compact.uniq

      available = begin
        client.model_names
      rescue StandardError => e
        start_command = case RUBY_PLATFORM
                        when /darwin/ then 'brew services start ollama'
                        when /linux/  then 'sudo systemctl start ollama'
                        else 'ollama serve'
                        end
        abort "Preflight failed: cannot reach Ollama at #{@ollama_host}:#{@ollama_port} (#{e.class}: #{e.message}).\n" \
              "Start it with: #{start_command}"
      end

      missing = wanted.reject { |m| available.include?(m) || available.include?("#{m}:latest") }
      abort "Preflight failed: model(s) not pulled: #{missing.join(', ')}. Run: ollama pull #{missing.first}" unless missing.empty?

      wanted.each do |model|
        print "  Warming up #{model}... "
        client.chat(model: model, messages: [{ role: 'user', content: 'Reply with OK.' }], think: false, num_predict: 1, keep_alive: '30m')
        puts 'ready'
      end
    end

    def rules = @rules ||= Compiler::RulesLoader.load(@game.rules_file)

    def players
      range = rules.dig('game', 'player_count')
      count = @options[:player_count] || range&.dig('default') or return @game.players
      abort "#{@game.name}: #{count} players is outside #{range['min']}-#{range['max']}" if range && !count.between?(range['min'], range['max'])

      Array.new(count) { |i| "Player #{i + 1}" }
    end

    def new_runner(seed)
      @game.runner_class.new(
        rules:            rules,
        players:          players,
        models:           models,
        ollama_host:      @ollama_host,
        ollama_port:      @ollama_port,
        game_state_class: @game.game_state_class,
        seed:             seed,
        personas:         @options[:personas],
        mode:             @options[:mode]
      )
    rescue ArgumentError => e
      abort "#{@game.name}: #{e.message}"
    end

    def start
      preflight! if preflight?
      new_runner(@options[:seeds].first).run
    end

    def batch
      abort "Usage: #{@game.name} batch --seeds 1,2,3" if @options[:seeds].empty?
      preflight! if preflight?

      results = []
      @options[:seeds].each_with_index do |seed, i|
        puts "\n=== Batch #{i + 1}/#{@options[:seeds].length}: seed #{seed}, players #{@options[:player]}#{' (thinking)' if @options[:think]} ===\n\n"
        runner = new_runner(seed)
        begin
          runner.run
        rescue StandardError => e
          # One broken session should not stop an unattended batch; record it and move on.
          warn "  Session #{runner.session_id} crashed: #{e.class}: #{e.message}"
          results << { seed: seed, session: runner.session_id, status: "crashed (#{e.class})" }
          next
        end
        results << { seed: seed, session: runner.session_id, status: runner.status }
        break if runner.status == 'interrupted' # Ctrl+C stops the whole batch
      end

      puts "\n=== Batch summary ==="
      results.each do |r|
        report = File.join(PlaiTester.reports_dir, "#{r[:session]}.md")
        puts "seed #{r[:seed].to_s.ljust(6)} #{r[:status].to_s.ljust(12)} session #{r[:session]}  #{File.exist?(report) ? report : '(no report)'}"
      end
    end

    def resume(session_id)
      abort "Usage: #{@game.name} resume <session_id>" unless session_id
      @options[:player] = Session::Manager.new(session_id: session_id).load_checkpoint.dig('game_state', 'custom', 'player_model') || @options[:player] unless @options[:player_set]
      preflight! if @options[:preflight]

      @game.runner_class.resume(
        session_id:       session_id,
        models:           models,
        ollama_host:      @ollama_host,
        ollama_port:      @ollama_port,
        game_state_class: @game.game_state_class
      ).run
    end

    def preflight? = @options[:preflight] && @options[:mode] != 'bot'

    def botrun
      seeds   = @options[:seeds].empty? ? (1..@options[:games]).to_a : @options[:seeds]
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      results = Botrun.new(runner_class: @game.runner_class, game_state_class: @game.game_state_class, rules: rules,
                           players: players, seeds: seeds, personas: @options[:personas]).run do |done|
        print "\r  #{done}/#{seeds.length} games" if $stdout.tty?
      end
      seconds  = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      markdown = @game.botrun_report_class.new(results, game: rules.dig('game', 'name'), version: rules.dig('game', 'version'),
                                                        seconds: seconds, personas: @options[:personas]).to_markdown
      FileUtils.mkdir_p(PlaiTester.reports_dir)
      path = File.join(PlaiTester.reports_dir, "botrun-#{Time.now.strftime('%Y%m%d-%H%M%S')}.md")
      File.write(path, markdown)
      puts "\n\n#{markdown}\nSaved: #{path}"
    rescue ArgumentError => e
      abort "#{@game.name}: #{e.message}"
    end

    def compare
      markdown = @game.comparison_class.new(PlaiTester.sessions_dir, since: @options[:since]).to_markdown
      FileUtils.mkdir_p(PlaiTester.reports_dir)
      path = File.join(PlaiTester.reports_dir, "comparison-#{Time.now.strftime('%Y%m%d-%H%M%S')}.md")
      File.write(path, markdown)
      puts markdown, "\nSaved: #{path}"
    end

    def list
      sessions = Session::Manager.list
      return puts 'No sessions found.' if sessions.empty?

      puts format('%-24s  %-12s  %s', 'SESSION_ID', 'STATUS', 'SAVED_AT')
      sessions.each { |s| puts format('%-24s  %-12s  %s', *s.values_at('session_id', 'status', 'saved_at')) }
    end
  end
end
