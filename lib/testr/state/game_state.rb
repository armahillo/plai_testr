module Testr
  module State
    class GameState
      attr_reader :turn, :current_player_index, :players, :flags, :scores

      def initialize(players:, current_state: {})
        @players              = players
        @turn                 = current_state.fetch('turn', 0)
        @current_player_index = current_state.fetch('current_player_index', 0)
        @flags                = current_state.fetch('flags', {}).dup
        @scores               = current_state.fetch('scores', default_scores).dup
        @custom               = current_state.fetch('custom', {}).dup
      end

      def self.from_h(data)
        new(players: data['players'], current_state: data)
      end

      def current_player
        @players[@current_player_index]
      end

      def advance_turn
        @turn += 1
        @current_player_index = (@current_player_index + 1) % @players.length
      end

      # state_changes is a hash with optional keys: "flags", "scores", "custom"
      def apply_changes(state_changes)
        return if state_changes.nil? || state_changes.empty?

        @flags.merge!(state_changes['flags'])   if state_changes['flags']
        @scores.merge!(state_changes['scores']) if state_changes['scores']
        @custom.merge!(state_changes['custom']) if state_changes['custom']
      end

      def to_h
        {
          'turn'                 => @turn,
          'current_player_index' => @current_player_index,
          'current_player'       => current_player,
          'players'              => @players,
          'flags'                => @flags,
          'scores'               => @scores,
          'custom'               => @custom
        }
      end

      private

      def default_scores
        @players.each_with_object({}) { |p, h| h[p] = 0 }
      end
    end
  end
end
