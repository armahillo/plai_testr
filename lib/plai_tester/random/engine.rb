module PlaiTester
  module Random
    class Engine
      def roll(sides:, count: 1)
        Array.new(count) { rand(sides) + 1 }
      end

      def shuffle(collection)
        collection.shuffle
      end

      def coin_flip
        %w[heads tails].sample
      end
    end
  end
end
