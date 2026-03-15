module Testr
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

      def initialize(rules:, players:, models:, ollama_host: 'localhost', ollama_port: 11434, session_id: nil, checkpoint: nil)
        @rules   = rules
        @manager = Manager.new(session_id: session_id)

        client    = Agents::OllamaClient.new(host: ollama_host, port: ollama_port)
        @referee  = Agents::RefereeAgent.new(model: models[:referee], client: client, rules: rules)
        @players  = build_player_agents(players, models[:player], client)
        @running  = true

        if checkpoint
          @game_state = State::GameState.from_h(checkpoint['game_state'])
          @turn_log   = checkpoint['turn_log']
        else
          @game_state = State::GameState.new(players: players, current_state: rules.fetch('initial_state', {}))
          @turn_log   = []
        end

        trap('SIGINT') { interrupt! }
      end

      def self.resume(session_id:, models:, ollama_host: 'localhost', ollama_port: 11434)
        manager    = Manager.new(session_id: session_id)
        checkpoint = manager.load_checkpoint
        rules      = JSON.parse(File.read(checkpoint['rules_file']))

        new(
          rules:       rules,
          players:     checkpoint.dig('game_state', 'players'),
          models:      models,
          ollama_host: ollama_host,
          ollama_port: ollama_port,
          session_id:  session_id,
          checkpoint:  checkpoint
        )
      end

      def run
        puts "Session #{@manager.session_id}"
        puts "Game:    #{@rules.dig('game', 'name')} v#{@rules.dig('game', 'version')}"
        puts "Players: #{@game_state.players.join(', ')}"
        puts "Press Ctrl+C to save state and exit.\n\n"

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

      def build_player_agents(players, model, client)
        players.each_with_object({}) do |name, h|
          h[name] = Agents::PlayerAgent.new(name: name, model: model, client: client, rules: @rules)
        end
      end

      def play_turn
        player_name      = @game_state.current_player
        agent            = @players[player_name]
        available_actions = @rules.fetch('actions', []).map { |a| a['type'] }

        puts "Turn #{@game_state.turn + 1} — #{player_name}"

        action, validation = attempt_turn(agent, player_name, available_actions)

        if validation['valid']
          @game_state.apply_changes(validation['state_changes'])

          entry = {
            'turn'        => @game_state.turn + 1,
            'player'      => player_name,
            'action'      => action['action'],
            'parameters'  => action['parameters'],
            'reasoning'   => action['reasoning'],
            'state_after' => @game_state.to_h
          }

          @turn_log << entry
          @manager.append_transcript_entry(entry)
          @game_state.advance_turn
          save_checkpoint('in_progress')
        end
      end

      def attempt_turn(agent, player_name, available_actions)
        attempts = []

        MAX_RETRIES.times do |i|
          action     = agent.take_turn(@game_state.to_h, available_actions, @turn_log)
          validation = @referee.validate(player: player_name, action: action, game_state: @game_state.to_h)

          puts "  Action: #{action['action']} #{action['parameters']}"

          return [action, validation] if validation['valid']

          puts "  Invalid (attempt #{i + 1}/#{MAX_RETRIES}): #{validation['reason']}"
          attempts << { attempt: i + 1, action: action, rejection: validation['reason'] }
        end

        raise StalledError.new({
          turn:       @game_state.turn + 1,
          player:     player_name,
          game_state: @game_state.to_h,
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
        FileUtils.mkdir_p(Testr::REPORTS_DIR)
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
        puts "Saved. Resume with: testr resume #{@manager.session_id}"
        @running = false
      end
    end
  end
end
