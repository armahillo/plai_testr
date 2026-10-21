module PlaiTestr
  module State
    class PlayerState < Base
      attr_reader :name, :score, :hand, :data

      def initialize(name:, score: 0, hand: [], data: {})
        @name  = name
        @score = score.to_i
        @hand  = hand.dup
        @data  = data.dup
      end

      def self.from_h(data)
        new(
          name:  data['name'],
          score: data.fetch('score', 0),
          hand:  data.fetch('hand',  []),
          data:  data.fetch('data',  {})
        )
      end

      def apply_changes(changes)
        return if changes.nil? || changes.empty?

        @score = changes['score'] if changes.key?('score')
        @hand  = changes['hand']  if changes.key?('hand')
        @data.merge!(changes['data']) if changes['data']
      end

      # Full state — for checkpoints
      def serialize
        {
          'name'  => @name,
          'score' => @score,
          'hand'  => @hand,
          'data'  => @data
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
          'data'      => public_data
        }
      end

      private

      # Override in subclasses to selectively expose data to opponents
      def public_data
        {}
      end
    end
  end
end
