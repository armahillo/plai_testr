module PlaiTester
  class CLI
    def initialize(game, ollama_host: ENV.fetch('PLAITESTER_OLLAMA_HOST', 'localhost'), ollama_port: ENV.fetch('PLAITESTER_OLLAMA_PORT', '11434').to_i)
      @game        = game
      @ollama_host = ollama_host
      @ollama_port = ollama_port
      @options     = {
        player:    ENV.fetch('PLAITESTER_PLAYER_MODEL', 'qwen3:8b'),
        referee:   ENV['PLAITESTER_REFEREE_MODEL'],
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
      when 'compare'   then compare
      when 'list'      then list
      else puts parser.help
      end
    end

    private

    def models = { player: @options[:player], referee: @options[:referee] }

    def parser
      @parser ||= OptionParser.new do |o|
        o.banner = <<~USAGE
          #{@game.name}: automated playtesting

          Commands:
            start   [--seed N] [--model M]          Start one new session
            batch   --seeds 1,2,3 [--model M]       Run several seeded sessions back to back
            resume  <session_id>                    Resume an interrupted session
            preflight                               Check Ollama and warm up the models
            compare [--since ID]                    Compare completed games by model and host
            list                                    List sessions

          Options:
        USAGE
        o.on('--seed N', Integer, 'Seed for setup shuffles (reproducible deals)') { |v| @options[:seeds] = [v] }
        o.on('--seeds LIST', Array, 'Comma-separated seeds for batch') { |v| @options[:seeds] = v.map { |s| Integer(s) } }
        o.on('--model M', 'Ollama model for the players (default qwen3:8b)') { |v| @options[:player] = v }
        o.on('--referee M', 'Ollama model for yes/no rulings (only for games that ask for them)') { |v| @options[:referee] = v }
        o.on('--skip-preflight', 'Do not check Ollama before running') { @options[:preflight] = false }
        o.on('--since ID', 'compare: only sessions whose id sorts at or after ID (e.g. 20261011-170000)') { |v| @options[:since] = v }
      end
    end

    # Confirms the Ollama server is reachable and the models are pulled, then loads each model
    # with a tiny request so the first real turn does not time out while the model loads.
    def preflight!
      client = Agents::OllamaClient.new(host: @ollama_host, port: @ollama_port)
      wanted = models.values.compact.uniq

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

    def new_runner(seed)
      @game.runner_class.new(
        rules:            Compiler::RulesLoader.load(@game.rules_file),
        players:          @game.players,
        models:           models,
        ollama_host:      @ollama_host,
        ollama_port:      @ollama_port,
        game_state_class: @game.game_state_class,
        seed:             seed
      )
    end

    def start
      preflight! if @options[:preflight]
      new_runner(@options[:seeds].first).run
    end

    def batch
      abort "Usage: #{@game.name} batch --seeds 1,2,3" if @options[:seeds].empty?
      preflight! if @options[:preflight]

      results = []
      @options[:seeds].each_with_index do |seed, i|
        puts "\n=== Batch #{i + 1}/#{@options[:seeds].length}: seed #{seed}, players #{@options[:player]} ===\n\n"
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
      preflight! if @options[:preflight]

      @game.runner_class.resume(
        session_id:       session_id,
        models:           models,
        ollama_host:      @ollama_host,
        ollama_port:      @ollama_port,
        game_state_class: @game.game_state_class
      ).run
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
