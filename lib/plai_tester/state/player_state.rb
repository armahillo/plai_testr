module PlaiTester
  module State
    class PlayerState < Base
      attr_reader :name, :score, :hand, :flags

      def initialize(name:, score: 0, hand: [], flags: {})
        @name  = name
        @score = score.to_i
        @hand  = hand.dup
        @flags = flags.dup
      end

      def self.from_h(data)
        new(
          name:  data['name'],
          score: data.fetch('score', 0),
          hand:  data.fetch('hand',  []),
          flags: data.fetch('flags', {})
        )
      end

      def apply_changes(changes)
        return if changes.nil? || changes.empty?

        @score = changes['score'] if changes.key?('score')
        @hand  = changes['hand']  if changes.key?('hand')
        @flags.merge!(changes['flags']) if changes['flags']
      end

      # Full state — for checkpoints and referee
      def serialize
        {
          'name'  => @name,
          'score' => @score,
          'hand'  => @hand,
          'flags' => @flags
        }
      end

      # Opponent-visible state — hand contents are hidden, only size shown
      # Subclasses override to expose game-specific public fields (e.g. top stance card)
      def serialize_for(observer)
        return serialize if observer == @name

        {
          'name'      => @name,
          'score'     => @score,
          'hand_size' => @hand.length,
          'flags'     => public_flags
        }
      end

      private

      # Override in subclasses to selectively expose flags to opponents
      def public_flags
        {}
      end
    end
  end
end
