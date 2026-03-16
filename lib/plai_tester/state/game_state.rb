module PlaiTester
  module State
    class GameState < Base
      attr_reader :turn, :current_player_index, :players, :flags

      def initialize(players:, current_state: {})
        @players              = players
        @turn                 = current_state.fetch('turn', 0)
        @current_player_index = current_state.fetch('current_player_index', 0)
        @flags                = current_state.fetch('flags', {}).dup
        @custom               = current_state.fetch('custom', {}).dup
        @player_states        = build_player_states(players, current_state)
      end

      def self.from_h(data)
        new(players: data['players'], current_state: data)
      end

      def current_player
        @players[@current_player_index]
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

      # state_changes keys: "flags" (object), "custom" (object), "player_states" (object keyed by player name)
      def apply_changes(state_changes)
        return if state_changes.nil? || state_changes.empty?

        @flags.merge!(state_changes['flags'])   if state_changes['flags']
        @custom.merge!(state_changes['custom']) if state_changes['custom']

        state_changes.fetch('player_states', {}).each do |name, changes|
          @player_states[name]&.apply_changes(changes)
        end
      end

      # Full state — for checkpoints and referee
      def serialize
        {
          'turn'                 => @turn,
          'current_player_index' => @current_player_index,
          'current_player'       => current_player,
          'players'              => @players,
          'flags'                => @flags,
          'custom'               => @custom,
          'player_states'        => @player_states.transform_values(&:serialize)
        }
      end

      # Per-player view — opponent hand contents are hidden
      def serialize_for(observer)
        {
          'turn'           => @turn,
          'current_player' => current_player,
          'players'        => @players,
          'flags'          => @flags,
          'custom'         => custom_for(observer),
          'player_states'  => @player_states.transform_values { |ps| ps.serialize_for(observer) }
        }
      end

      private

      # Override in game-specific subclasses to filter or transform custom state
      # per observer (e.g. hide face-down deck contents, show only counts).
      # The full @custom is always used by serialize (referee/checkpoints).
      def custom_for(_observer)
        @custom
      end

      # Override in game-specific subclasses to use a richer PlayerState
      def player_state_class
        PlayerState
      end

      def build_player_states(players, current_state)
        saved = current_state.fetch('player_states', {})

        players.each_with_object({}) do |name, h|
          if saved[name]
            h[name] = player_state_class.from_h(saved[name])
          else
            # Support loading legacy checkpoints that stored scores at the top level
            legacy_score = current_state.dig('scores', name) || 0
            h[name] = player_state_class.new(name: name, score: legacy_score)
          end
        end
      end
    end
  end
end
