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

      def initialize(rules:, players:, models:, ollama_host: 'localhost', ollama_port: 11434, session_id: nil, checkpoint: nil, game_state_class: State::GameState)
        @rules            = rules
        @game_state_class = game_state_class
        @manager          = Manager.new(session_id: session_id)

        client    = Agents::OllamaClient.new(host: ollama_host, port: ollama_port)
        @referee  = Agents::RefereeAgent.new(model: models[:referee], client: client, rules: rules)
        @players  = build_player_agents(players, models[:player], client)
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

        trap('SIGINT') { interrupt! }
      end

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

        until game_over? || !@running
          play_turn
        end

        save_checkpoint('completed')
        path = generate_report
        puts "\nGame complete. Report: #{path}"
      rescue StalledError => e
        puts "\n  STALLED: #{e.message}"
        save_checkpoint('stalled')
        path = generate_report(stall_context: e.context)
        puts "  State saved. Review the report for what was attempted: #{path}"
        @running = false
      end

      private

      def resolve_random_if_needed(validation, action)
        return validation unless validation['random_ops']&.any?

        random_results = execute_random_ops(validation['random_ops'])
        puts "  Random: #{random_results}"
        @referee.resolve_random(
          random_results: random_results,
          game_state:     @game_state.serialize,
          action:         action
        )
      end

      def execute_random_ops(ops)
        ops.each_with_object({}) do |op, results|
          results[op['for']] = case op['op']
          when 'roll'      then @random.roll(sides: op.fetch('sides', 6), count: op.fetch('count', 1))
          when 'coin_flip' then @random.coin_flip
          end
        end
      end

      # Asks the referee to execute the rules' setup steps and applies the resulting state.
      # Not called when resuming from a checkpoint — state is already populated.
      # Override in game-specific subclasses to inject true randomness (e.g. pre-shuffle
      # via @random and pass the result to the referee via a custom setup_prompt).
      def setup
        return if @rules.fetch('setup', []).empty?

        puts "  Setting up..."
        initial = @referee.compute_initial_state(
          setup_steps: @rules.fetch('setup', []),
          components:  @rules.fetch('components', []),
          players:     @game_state.players
        )
        @game_state.apply_changes(initial)
      end

      def build_player_agents(players, model, client)
        players.each_with_object({}) do |name, h|
          h[name] = Agents::PlayerAgent.new(name: name, model: model, client: client, rules: @rules)
        end
      end

      def play_turn
        player_name    = @game_state.current_player
        agent          = @players[player_name]
        active_actions = available_actions_for(player_name)

        puts "Turn #{@game_state.turn + 1} — #{player_name}"

        turn_actions = []

        loop do
          action, validation = attempt_turn(agent, player_name, active_actions + ['end_turn'])

          if action['action'] == 'end_turn'
            turn_actions << { 'action' => 'end_turn', 'parameters' => {}, 'reasoning' => action['reasoning'], 'reactions' => [] }
            break
          end

          validation = resolve_random_if_needed(validation, action)
          @game_state.apply_changes(validation['state_changes'])

          reactions = triggers_reactions?(action) ? reaction_pass(action, player_name) : []

          turn_actions << {
            'action'     => action['action'],
            'parameters' => action['parameters'],
            'reasoning'  => action['reasoning'],
            'reactions'  => reactions
          }

          # Stop prompting for more actions if the game ended mid-turn
          break if game_over?
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

      # After an action that triggers reactions, query each other player in turn order.
      # Each may respond with a reaction action or a no_op. Validated reactions are applied
      # to game state immediately so subsequent reactors see the updated state.
      def reaction_pass(triggering_action, acting_player)
        reaction_action_types = @rules.fetch('actions', []).select { |a| a['reaction'] }.map { |a| a['type'] }

        @game_state.players.reject { |p| p == acting_player }.filter_map do |player_name|
          agent          = @players[player_name]
          action, validation = attempt_reaction(agent, player_name, acting_player, triggering_action, reaction_action_types)

          puts "  #{player_name} reacts: #{action['action']}"
          next if action['action'] == 'no_op'

          validation = resolve_random_if_needed(validation, action)
          @game_state.apply_changes(validation['state_changes']) if validation['valid']

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
        FileUtils.mkdir_p(PlaiTester::REPORTS_DIR)
        Reporter::ReportBuilder.new(
          session_id:   @manager.session_id,
          rules:        @rules,
          game_state:   @game_state,
          turn_log:     @turn_log,
          stall_context: stall_context
        ).build
      end

      def interrupt!
        puts "\n\nInterrupted — saving state..."
        save_checkpoint('interrupted')
        puts "Saved. Resume with: plai_tester resume #{@manager.session_id}"
        @running = false
      end
    end
  end
end
