module PlaiTester
  module Session
    class StalledError < StandardError
      attr_reader :context

      def initialize(context)
        @context = context
        super("#{context[:player]} could not produce a valid action after #{context[:attempts].length} attempts on turn #{context[:turn]}")
      end
    end

    class Runner
      MAX_RETRIES = 3

      RECENT_EVENTS = 8

      def initialize(rules:, players:, models:, ollama_host: 'localhost', ollama_port: 11434, session_id: nil, checkpoint: nil, game_state_class: State::GameState, seed: nil)
        @rules            = rules
        @game_state_class = game_state_class
        @manager          = Manager.new(session_id: session_id)
        @seed             = seed

        client    = Agents::OllamaClient.new(host: ollama_host, port: ollama_port, think_log: File.join(@manager.session_dir, 'think.log'))
        @referee  = Agents::RefereeAgent.new(model: models[:referee], client: client, rules: rules)
        @players  = build_player_agents(players, models[:player], client)
        @models   = models
        @random   = Random::Engine.new
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

        trap('SIGINT') { interrupt! }
      end

      attr_reader :seed

      def session_id
        @manager.session_id
      end

      # Status of the last run: 'completed', 'stalled' or 'interrupted'.
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

        unless @resuming
          @game_state.apply_changes('custom' => { 'seed' => @seed })
          setup
        end

        until game_over? || !@running
          play_turn
        end

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
      rescue StalledError => e
        puts "\n  STALLED: #{e.message}"
        @status = 'stalled'
        save_checkpoint('stalled')
        path = generate_report(stall_context: e.context)
        puts "  State saved. Review the report for what was attempted: #{path}"
        @running = false
      end

      private

      # Apply the effects of a validated action to game state.
      # Override in game-specific subclasses — the base runner does not know how to
      # compute state changes; that logic lives with the game rules.
      def apply_action_effects(_player_name, action)
        raise NotImplementedError, "#{self.class} must implement #apply_action_effects (tried to apply '#{action['action']}')"
      end

      # Return true for actions that should end the active player's turn immediately
      # without waiting for an explicit end_turn. Override in game-specific subclasses.
      def ends_turn_immediately?(_action)
        false
      end

      # Return false to suppress end_turn from the action list for mandatory-action turns
      # (e.g. training phase where every player must take exactly one action).
      def end_turn_allowed?(_player_name)
        true
      end

      # Return false to skip referee validation for an action and let the Ruby runner
      # handle all legality checks itself. Use for deterministic actions where the referee
      # adds no value and is likely to hallucinate.
      def validate_action?(_action)
        true
      end

      # Asks the referee to execute the rules' setup steps and applies the resulting state.
      # Not called when resuming from a checkpoint — state is already populated.
      # Override in game-specific subclasses to inject true randomness (e.g. pre-shuffle
      # via @random and pass the result to the referee via a custom setup_prompt).
      def setup
        steps = @rules.fetch('setup', [])
        return if steps.empty?

        puts "  Setting up — #{steps.length} step#{steps.length == 1 ? '' : 's'} (referee computing initial state, this may take a moment)..."
        initial = @referee.compute_initial_state(
          setup_steps: steps,
          components:  @rules.fetch('components', []),
          players:     @game_state.players
        )
        @game_state.apply_changes(initial)
        puts "  Setup complete."
      end

      def build_player_agents(players, model, client)
        players.each_with_object({}) do |name, h|
          h[name] = Agents::PlayerAgent.new(name: name, model: model, client: client, rules: @rules)
        end
      end

      # --- Menu-turn hooks -------------------------------------------------------------
      # Games opt into menu turns by returning an array from legal_moves. Each move is
      #   { 'label' => String, 'action' => Hash, 'public' => String (optional) }
      # 'label' is what the acting player sees; 'public' is what opponents see in their
      # recent-events list (defaults to the label — set it whenever the move is private).
      # Return nil to use the legacy free-form action + referee validation path.

      def legal_moves(_player_name)
        nil
      end

      # Who acts next. Default: strict alternation via GameState#advance_turn.
      def next_player
        @game_state.current_player
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

      def play_turn
        player_name = next_player
        @game_state.current_player = player_name

        moves = legal_moves(player_name)
        return play_menu_turn(player_name, moves) if moves

        agent          = @players[player_name]
        active_actions = available_actions_for(player_name)

        puts "Turn #{@game_state.turn + 1} — #{player_name}"

        turn_actions = []

        loop do
          offered = end_turn_allowed?(player_name) ? active_actions + ['end_turn'] : active_actions
          action, _validation = attempt_turn(agent, player_name, offered)

          if action['action'] == 'end_turn'
            turn_actions << { 'action' => 'end_turn', 'parameters' => {}, 'reasoning' => action['reasoning'], 'reactions' => [] }
            break
          end

          apply_action_effects(player_name, action)

          reactions = triggers_reactions?(action) ? reaction_pass(action, player_name) : []

          turn_actions << {
            'action'     => action['action'],
            'parameters' => action['parameters'],
            'reasoning'  => action['reasoning'],
            'reactions'  => reactions
          }

          break if ends_turn_immediately?(action) || game_over?
        end

        entry = {
          'turn'        => @game_state.turn + 1,
          'player'      => player_name,
          'actions'     => turn_actions,
          'state_after' => @game_state.serialize
        }

        @turn_log << entry
        @manager.append_transcript_entry(entry)
        @game_state.advance_turn
        save_checkpoint('in_progress')
      end

      # Menu turns cannot be illegal (every option is legal by construction), so there is no
      # referee call and no StalledError — an unparseable reply falls back to option 1 and is
      # flagged in the transcript instead.
      def play_menu_turn(player_name, moves)
        raise "#{self.class}#legal_moves returned no moves for #{player_name}" if moves.empty?

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

        entry = {
          'turn'        => @game_state.turn + 1,
          'player'      => player_name,
          'mode'        => 'menu',
          'options'     => moves.length,
          'choice'      => result['choice'],
          'label'       => move['label'],
          'public'      => move['public'] || move['label'],
          'reasoning'   => result['reasoning'],
          'plan'        => result['plan'],
          'attempts'    => result['attempts'],
          'fallback'    => result['fallback'],
          'actions'     => [move['action'].merge('reasoning' => result['reasoning'], 'reactions' => [])],
          'state_after' => @game_state.serialize
        }

        @turn_log << entry
        @manager.append_transcript_entry(entry)
        @game_state.advance_turn
        save_checkpoint('in_progress')
      end

      def last_plan(player_name)
        @turn_log.reverse.find { |t| t['player'] == player_name && t['plan'] }&.fetch('plan')
      end

      # Own moves show their full label; other players' moves show only their public text.
      def recent_events_for(player_name)
        @turn_log.select { |t| t['mode'] == 'menu' }.last(RECENT_EVENTS).map do |t|
          t['player'] == player_name ? "You: #{t['label']}" : "#{t['player']}: #{t['public']}"
        end
      end

      # After an action that triggers reactions, query each other player in turn order.
      # Each may respond with a reaction action or a no_op. Validated reactions are applied
      # to game state immediately so subsequent reactors see the updated state.
      def reaction_pass(triggering_action, acting_player)
        reaction_action_types = @rules.fetch('actions', []).select { |a| a['reaction'] }.map { |a| a['type'] }

        @game_state.players.reject { |p| p == acting_player }.filter_map do |player_name|
          agent              = @players[player_name]
          action, validation = attempt_reaction(agent, player_name, acting_player, triggering_action, reaction_action_types)

          puts "  #{player_name} reacts: #{action['action']}"
          next if action['action'] == 'no_op'

          apply_action_effects(player_name, action) if validation&.fetch('valid', false)

          {
            'player'     => player_name,
            'action'     => action['action'],
            'parameters' => action['parameters'],
            'reasoning'  => action['reasoning']
          }
        end
      end

      # Mirrors attempt_turn but for reaction prompts. Retries up to MAX_RETRIES;
      # falls back to no_op rather than raising StalledError — a failed reaction
      # should not halt the whole game.
      def attempt_reaction(agent, player_name, acting_player, triggering_action, available_reactions)
        context = Protocol::Context.reaction(acting_player: acting_player, triggering_action: triggering_action)

        MAX_RETRIES.times do |i|
          action = agent.react_to(acting_player, triggering_action, @game_state.serialize_for(player_name), available_reactions)

          return [action, nil] if action['action'] == 'no_op'

          validation = @referee.validate(player: player_name, action: action, game_state: @game_state.serialize, context: context)

          return [action, validation] if validation['valid']

          puts "  Invalid reaction (attempt #{i + 1}/#{MAX_RETRIES}): #{validation['reason']}"
        end

        puts "  #{player_name} could not produce a valid reaction after #{MAX_RETRIES} attempts — defaulting to no_op"
        [{ 'action' => 'no_op', 'parameters' => {}, 'reasoning' => 'no valid reaction found' }, nil]
      end

      # Override in game-specific subclasses to restrict actions based on current state
      # (e.g. disable 'buy' when the player has no coins). Reactions are always excluded —
      # they are only surfaced during reaction_pass.
      def available_actions_for(_player_name)
        @rules.fetch('actions', []).reject { |a| a['reaction'] }.map { |a| a['type'] }
      end

      def triggers_reactions?(action)
        rule = @rules.fetch('actions', []).find { |a| a['type'] == action['action'] }
        rule&.fetch('triggers_reactions', false) || false
      end

      def attempt_turn(agent, player_name, available_actions)
        attempts = []

        MAX_RETRIES.times do |i|
          action     = agent.take_turn(@game_state.serialize_for(player_name), available_actions, @turn_log)

          puts "  Action: #{action['action']} #{action['parameters']}"

          # end_turn needs no referee — the player decides when they're done
          return [action, nil] if action['action'] == 'end_turn'

          return [action, nil] unless validate_action?(action)

          validation = @referee.validate(player: player_name, action: action, game_state: @game_state.serialize, context: Protocol::Context.turn_action)

          if validation['valid']
            return [action, validation]
          end

          puts "  Invalid (attempt #{i + 1}/#{MAX_RETRIES}): #{validation['reason']}"
          attempts << { attempt: i + 1, action: action, rejection: validation['reason'] }
        end

        raise StalledError.new({
          turn:       @game_state.turn + 1,
          player:     player_name,
          game_state: @game_state.serialize,
          attempts:   attempts
        })
      end

      def game_over?
        @rules.fetch('win_conditions', []).any? { |wc| evaluate_win_condition(wc) }
      end

      def evaluate_win_condition(condition)
        case condition['type']
        when 'score_threshold'
          @game_state.scores.any? { |_, score| score.to_i >= condition['threshold'].to_i }
        when 'flag'
          @game_state.flags[condition['flag']] == condition['value']
        when 'turn_limit'
          @game_state.turn >= condition['limit'].to_i
        else
          false
        end
      end

      def save_checkpoint(status)
        @manager.save_checkpoint(@game_state, @turn_log, {
          'status'        => status,
          'game'          => @rules.dig('game', 'name'),
          'rules_file'    => @rules['_source_file'],
          'rules_version' => @rules.dig('game', 'version')
        })
      end

      def generate_report(stall_context: nil)
        FileUtils.mkdir_p(PlaiTester.reports_dir)
        Reporter::ReportBuilder.new(
          session_id:   @manager.session_id,
          rules:        @rules,
          game_state:   @game_state,
          turn_log:     @turn_log,
          stall_context: stall_context
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
