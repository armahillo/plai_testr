module PlaiTester
  module Session
    class Runner
      RECENT_EVENTS = 8

      def initialize(rules:, players:, models:, ollama_host: 'localhost', ollama_port: 11434, session_id: nil, checkpoint: nil, game_state_class: State::GameState, seed: nil)
        @rules            = rules
        @game_state_class = game_state_class
        @manager          = Manager.new(session_id: session_id)
        @seed             = seed

        client    = Agents::OllamaClient.new(host: ollama_host, port: ollama_port, think_log: think_log_path)
        @referee  = models[:referee] && Agents::RefereeAgent.new(model: models[:referee], client: client, rules: rules)
        @players  = players.to_h { |name| [name, Agents::PlayerAgent.new(name: name, model: models[:player], client: client, rules: rules)] }
        @models   = models
        @running  = true
        @resuming = !checkpoint.nil?

        if checkpoint
          @game_state = @game_state_class.from_h(checkpoint['game_state'])
          @turn_log   = checkpoint['turn_log']
        else
          @game_state = @game_state_class.new(players: players, current_state: rules.fetch('initial_state', {}))
          @turn_log   = []
        end

        # A seed makes setup shuffles reproducible. It is stored in game state so a resumed
        # session reports the same seed.
        @seed ||= @game_state.custom['seed'] || Kernel.rand(1_000_000)
        @rng    = ::Random.new(@seed)
        @game_state.apply_changes('custom' => { 'seed' => @seed, 'player_model' => models[:player], 'host' => Socket.gethostname }) unless checkpoint

        trap('SIGINT') { interrupt! }
      end

      attr_reader :seed

      def session_id
        @manager.session_id
      end

      # Status of the last run: 'completed' or 'interrupted'.
      attr_reader :status

      def self.resume(session_id:, models:, ollama_host: 'localhost', ollama_port: 11434, game_state_class: State::GameState)
        manager    = Manager.new(session_id: session_id)
        checkpoint = manager.load_checkpoint
        rules      = Compiler::RulesLoader.load(checkpoint['rules_file'])

        new(
          rules:            rules,
          players:          checkpoint.dig('game_state', 'players'),
          models:           models,
          ollama_host:      ollama_host,
          ollama_port:      ollama_port,
          session_id:       session_id,
          checkpoint:       checkpoint,
          game_state_class: game_state_class
        )
      end

      def run
        puts "Session #{@manager.session_id}"
        puts "Game:    #{@rules.dig('game', 'name')} v#{@rules.dig('game', 'version')}"
        puts "Players: #{@game_state.players.join(', ')}"
        puts "Press Ctrl+C to save state and exit.\n\n"

        setup unless @resuming
        play_turn until game_over? || !@running
        run_debrief if game_over? && @running

        if game_over?
          @status = 'completed'
          save_checkpoint('completed')
          path = generate_report
          puts "\nGame complete. Report: #{path}"
        else
          @status = 'interrupted'
          save_checkpoint('interrupted')
          puts "Saved after turn #{@game_state.turn}. Resume with: resume #{@manager.session_id}"
        end
      end

      private

      # --- Game hooks ------------------------------------------------------------------
      # A move is { 'label' => String, 'action' => Hash, 'public' => String (optional) }.
      # 'label' is what the acting player sees; 'public' is what opponents see in their
      # recent-events list (defaults to the label — set it whenever the move is private).

      def setup
        raise NotImplementedError, "#{self.class} must implement #setup"
      end

      def legal_moves(_player_name)
        raise NotImplementedError, "#{self.class} must implement #legal_moves"
      end

      def apply_action_effects(_player_name, _action)
        raise NotImplementedError, "#{self.class} must implement #apply_action_effects"
      end

      # Who acts next. Default: strict alternation via GameState#advance_turn.
      def next_player
        @game_state.current_player
      end

      def pick_range(_player_name)
        nil
      end

      def game_over?
        @game_state.flags['game_over'] == true
      end

      # Rules text for the menu system prompt. Override to scope rules to the current phase.
      def rules_text_for(_player_name)
        @rules.dig('game', 'description').to_s
      end

      # What the player is allowed to see, as text. Override with a readable view.
      def view_text_for(player_name)
        JSON.pretty_generate(@game_state.serialize_for(player_name))
      end

      # Optional one-off note for this prompt (e.g. "your stack choice collided; choose again").
      def prompt_note_for(_player_name)
        nil
      end

      # Questions each player answers once after the game ends (designer feedback).
      # Return [] to skip the debrief.
      def debrief_questions(_player_name)
        []
      end

      # What a player sees while answering the debrief; defaults to their normal view.
      def debrief_view_for(player_name)
        view_text_for(player_name)
      end

      def report_sections
        []
      end

      # Own moves show their full label; other players' moves show only their public text.
      def recent_events_for(player_name)
        @turn_log.last(RECENT_EVENTS).filter_map do |t|
          next "You: #{t['label']}" if t['player'] == player_name

          "#{t['player']}: #{t['public']}" unless t['public'].to_s.empty?
        end
      end

      # --- Turns -----------------------------------------------------------------------

      def play_turn
        player_name = next_player
        @game_state.current_player = player_name

        moves = legal_moves(player_name)
        pick  = pick_range(player_name)
        raise "#{self.class}#legal_moves returned no moves for #{player_name}" if moves.empty? && pick.nil?

        if pick
          play_pick_turn(player_name, moves, *pick)
        elsif moves.length == 1
          play_forced_turn(player_name, moves.first)
        else
          play_choice_turn(player_name, moves)
        end
      end

      # Menu turns cannot be illegal (every option is legal by construction), so there is no
      # referee call — an unparseable reply falls back to option 1 and is flagged instead.
      def play_choice_turn(player_name, moves)
        puts "Turn #{@game_state.turn + 1} — #{player_name} (#{moves.length} options)"

        result = @players[player_name].choose(
          rules_text:  rules_text_for(player_name),
          view_text:   view_text_for(player_name),
          labels:      moves.map { |m| m['label'] },
          plan:        last_plan(player_name),
          recent:      recent_events_for(player_name),
          prompt_note: prompt_note_for(player_name)
        )
        move = moves[result['choice'] - 1]
        puts "  -> #{move['label']}#{' [FALLBACK]' if result['fallback']}#{" (#{result['attempts']} tries)" if result['attempts'] > 1}"

        apply_action_effects(player_name, move['action'])
        record_turn(player_name, move['action'], 'label' => move['label'], 'public' => move['public'] || move['label'],
                                                 'options' => moves.length, 'choice' => result['choice'],
                                                 'reasoning' => result['reasoning'], 'plan' => result['plan'],
                                                 'attempts' => result['attempts'], 'fallback' => result['fallback'])
      end

      def play_forced_turn(player_name, move)
        puts "Turn #{@game_state.turn + 1} — #{player_name}: #{move['label']} [only option]"

        apply_action_effects(player_name, move['action'])
        record_turn(player_name, move['action'], 'label' => move['label'], 'public' => move['public'] || move['label'],
                                                 'options' => 1, 'choice' => 1, 'attempts' => 0, 'fallback' => false, 'auto' => true)
      end

      def play_pick_turn(player_name, moves, min, max)
        max    = [max, moves.length].min
        min    = [min, max].min
        result = if min == moves.length
                   { 'choices' => (1..min).to_a, 'attempts' => 0, 'fallback' => false, 'auto' => true }
                 else
                   puts "Turn #{@game_state.turn + 1} — #{player_name} (pick #{min}-#{max} of #{moves.length})"
                   @players[player_name].choose_many(
                     rules_text:  rules_text_for(player_name),
                     view_text:   view_text_for(player_name),
                     labels:      moves.map { |m| m['label'] },
                     min:         min,
                     max:         max,
                     plan:        last_plan(player_name),
                     recent:      recent_events_for(player_name),
                     prompt_note: prompt_note_for(player_name)
                   )
                 end
        chosen = result['choices'].map { |i| moves[i - 1] }
        label  = chosen.empty? ? '(none)' : chosen.map { |m| m['label'] }.join('; ')
        action = { 'action'     => moves.first&.dig('action', 'action') || 'pick',
                   'parameters' => { 'values' => chosen.map { |m| m.dig('action', 'parameters', 'value') } } }
        puts "  -> #{label}#{' [FALLBACK]' if result['fallback']}"

        apply_action_effects(player_name, action)
        record_turn(player_name, action, 'label' => label, 'public' => chosen.map { |m| m['public'] }.compact.join('; '),
                                         'options' => moves.length, 'choice' => result['choices'],
                                         'reasoning' => result['reasoning'], 'plan' => result['plan'],
                                         'attempts' => result['attempts'], 'fallback' => result['fallback'],
                                         'auto' => result['auto'] || false)
      end

      def record_turn(player_name, action, fields)
        entry = { 'turn' => @game_state.turn + 1, 'player' => player_name }.merge(fields).merge(
          'actions'     => [action.merge('reasoning' => fields['reasoning'])],
          'state_after' => @game_state.serialize
        )

        @turn_log << entry
        @manager.append_transcript_entry(entry)
        @game_state.advance_turn
        save_checkpoint('in_progress')
      end

      def last_plan(player_name)
        @turn_log.reverse.find { |t| t['player'] == player_name && t['plan'] }&.fetch('plan')
      end

      # Stored in custom['debrief'] so a resumed session does not ask a player twice.
      def run_debrief
        @game_state.players.each do |player_name|
          questions = debrief_questions(player_name)
          next if questions.empty? || @game_state.custom.dig('debrief', player_name)

          puts "Debrief — #{player_name}"
          answers = @players[player_name].debrief(
            rules_text: rules_text_for(player_name),
            view_text:  debrief_view_for(player_name),
            questions:  questions
          )
          @game_state.apply_changes('custom' => { 'debrief' => (@game_state.custom['debrief'] || {}).merge(player_name => answers) })
          save_checkpoint('in_progress')
        end
      end

      # --- Persistence and reporting ---------------------------------------------------

      def think_log_path
        File.join(@manager.session_dir, 'think.log')
      end

      def save_checkpoint(status)
        @manager.save_checkpoint(@game_state, @turn_log, {
          'status'        => status,
          'game'          => @rules.dig('game', 'name'),
          'rules_file'    => @rules['_source_file'],
          'rules_version' => @rules.dig('game', 'version')
        })
      end

      def generate_report
        FileUtils.mkdir_p(PlaiTester.reports_dir)
        Reporter::ReportBuilder.new(
          session_id: @manager.session_id,
          rules:      @rules,
          game_state: @game_state,
          turn_log:   @turn_log,
          think_log:  Reporter::ThinkLog.load(think_log_path),
          sections:   report_sections
        ).build
      end

      # First Ctrl+C: finish the turn in progress, checkpoint, and stop cleanly.
      # Second Ctrl+C: exit immediately — the checkpoint from the last completed turn is on disk.
      def interrupt!
        exit!(130) unless @running

        @running = false
        $stderr.puts "\n\nInterrupted — finishing the current turn, then saving. Press Ctrl+C again to quit immediately."
      end
    end
  end
end
