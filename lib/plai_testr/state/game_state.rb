module PlaiTestr
  module State
    class GameState < Base
      attr_reader :turn, :current_player_index, :players, :status, :data

      def initialize(players:, current_state: {})
        @players              = players
        @turn                 = current_state.fetch('turn', 0)
        @current_player_index = current_state.fetch('current_player_index', 0)
        @status               = current_state.fetch('status', {}).dup
        @data                 = current_state.fetch('data', {}).dup
        @player_states        = build_player_states(players, current_state.fetch('player_states', {}))
      end

      def self.from_h(data)
        new(players: data['players'], current_state: data)
      end

      def current_player
        @players[@current_player_index]
      end

      # Lets games with non-alternating turn order (simultaneous choices, rotating
      # starting players) decide who acts next. advance_turn still rotates by default.
      def current_player=(name)
        index = @players.index(name)
        raise ArgumentError, "Unknown player: #{name.inspect}" unless index

        @current_player_index = index
      end

      def player_state(name)
        @player_states[name]
      end

      def advance_turn
        @turn += 1
        @current_player_index = (@current_player_index + 1) % @players.length
      end

      # Convenience accessor for reporter and win-condition evaluation
      def scores
        @player_states.transform_values(&:score)
      end

      # state_changes keys: "status" (object), "data" (object), "player_states" (object keyed by player name)
      def apply_changes(state_changes)
        return if state_changes.nil? || state_changes.empty?

        @status.merge!(state_changes['status']) if state_changes['status']
        @data.merge!(state_changes['data'])     if state_changes['data']

        state_changes.fetch('player_states', {}).each do |name, changes|
          @player_states[name]&.apply_changes(changes)
        end
      end

      # Full state — for checkpoints
      def serialize
        {
          'turn'                 => @turn,
          'current_player_index' => @current_player_index,
          'current_player'       => current_player,
          'players'              => @players,
          'status'               => @status.dup,
          'data'                 => @data.dup,
          'player_states'        => @player_states.transform_values(&:serialize)
        }
      end

      # Per-player view — opponent hand contents are hidden
      def serialize_for(observer)
        {
          'turn'           => @turn,
          'current_player' => current_player,
          'players'        => @players,
          'status'         => @status,
          'data'           => data_for(observer),
          'player_states'  => @player_states.transform_values { |ps| ps.serialize_for(observer) }
        }
      end

      private

      # What `observer` may see of @data. The default hides the runner's warnings and shows only
      # the event log entries meant for them. Subclasses hide more with
      # `super.except('deck').merge('deck_size' => ...)`. serialize (checkpoints) keeps all of @data.
      def data_for(observer)
        shown = @data.except('warnings', 'wall_seconds')
        return shown unless shown.key?('log')

        shown.merge('log' => EventLog.new(shown['log']).visible_to(observer))
      end

      # Override in game-specific subclasses to use a richer PlayerState
      def player_state_class
        PlayerState
      end

      def build_player_states(players, saved)
        players.to_h { |name| [name, saved[name] ? player_state_class.from_h(saved[name]) : player_state_class.new(name: name)] }
      end
    end
  end
end
