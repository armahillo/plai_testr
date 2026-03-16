module PlaiTester
  # Builders for the context hash passed to the referee's validate method.
  # Context describes why a validation is being requested, so the referee
  # can apply the correct rules (e.g. reaction legality vs. normal turn legality).
  module Protocol
    module Context
      def self.turn_action
        { 'type' => 'turn_action' }
      end

      def self.reaction(acting_player:, triggering_action:)
        {
          'type'    => 'reaction',
          'trigger' => {
            'player' => acting_player,
            'action' => triggering_action
          }
        }
      end
    end
  end
end
