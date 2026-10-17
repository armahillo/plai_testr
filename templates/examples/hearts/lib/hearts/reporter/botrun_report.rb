module Hearts
  module Reporter
    class BotrunReport < PlaiTester::Reporter::BotrunReport
      private

      def extra_sections
        games = @played.select { |r| r['stats'] }
        return [] if games.empty?

        [hands(games), penalties(games)]
      end

      def hands(games)
        counts = games.map { |r| r.dig('stats', 'hands') }.sort
        table('## Hands per game', %w[Mean Median 90th Max], ["| #{counts.sum.fdiv(counts.length).round(1)} | #{percentile(counts, 50)} | #{percentile(counts, 90)} | #{counts.max} |"])
      end

      def penalties(games)
        rows = games.first['names'].keys.map do |seat|
          "| #{seat} | #{average(games, 'hearts', seat).round(1)} | #{average(games, 'queen', seat).round(2)} | #{games.sum { |r| r.dig('stats', 'taken', 'moons', seat) }} |"
        end
        table('## Penalties by seat', ['Seat', 'Hearts per game', 'Q♠ per game', 'Moons shot'], rows,
              "Player 2 sits on Player 1's left, and so on around the table.")
      end

      def average(games, key, seat) = games.sum { |r| r.dig('stats', 'taken', key, seat) }.fdiv(games.length)
    end
  end
end
