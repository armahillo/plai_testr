module PlaiTester
  module Reporter
    class BotrunReport
      def initialize(results, game:, version:, seconds:, personas: nil)
        @results  = results
        @played   = results.reject { |r| r['error'] }
        @game     = game
        @version  = version
        @seconds  = seconds
        @personas = personas
      end

      def to_markdown
        [header, endings, persona_wins, matchups, seat_wins, lengths, rules_fired, *extra_sections, outliers, errors].compact.join("\n\n") + "\n"
      end

      private

      def extra_sections = []

      def header
        seeds = @results.map { |r| r['seed'] }
        <<~MD.strip
          # Botrun: #{@game}

          | | |
          |---|---|
          | **Rules version** | #{@version} |
          | **Games** | #{@results.length} (seeds #{seeds.min}–#{seeds.max})#{", #{@results.length - @played.length} crashed" if @played.length < @results.length} |
          | **Players** | #{@played.first&.dig('names')&.length || '—'} |
          | **Personas** | #{@personas ? @personas.join(', ') : 'random per seed'} |
          | **Time** | #{@seconds.round(1)} s (#{(@seconds * 1000 / [@results.length, 1].max).round} ms per game) |
          | **Generated** | #{Time.now.strftime('%Y-%m-%d %H:%M')} |

          Every decision was made by the game's bot rules; no model was called. Results describe how the bot plays, so confirm anything surprising with a few model games.
        MD
      end

      def endings
        rows = @played.group_by { |r| r['end_reason'] || 'unknown' }.sort_by { |_, list| -list.length }
                      .map { |reason, list| "| #{reason} | #{list.length} | #{pct(list.length, @played.length)} |" }
        table('## How games ended', %w[Ending Games Share], rows)
      end

      def persona_wins
        seats = @played.flat_map { |r| r['personas'].to_h.map { |player, persona| [persona, r['winner'] == player, r['winner'].nil?] } }
        return nil if seats.empty?

        rows = seats.group_by(&:first).sort.map do |persona, list|
          wins = list.count { |_, won, _| won }
          "| #{persona} | #{list.length} | #{wins} | #{list.count { |_, _, draw| draw }} | #{pct(wins, list.length)} | #{wilson(wins, list.length)} |"
        end
        table('## Wins by persona', ['Persona', 'Games', 'Wins', 'Draws', 'Win rate', '95% range'], rows,
              'A persona playing itself counts once per seat. The 95% range is how far the true win rate could plausibly be from this sample; ranges that overlap are not a real difference.')
      end

      def matchups
        pairs = @played.select { |r| r['personas'].to_h.length == 2 && r['personas'].values.uniq.length == 2 }
        return nil if pairs.empty?

        rows = pairs.group_by { |r| r['personas'].values.sort }.sort.map do |(a, b), list|
          wins_a = list.count { |r| r['personas'][r['winner']] == a }
          wins_b = list.count { |r| r['personas'][r['winner']] == b }
          "| #{a} vs #{b} | #{list.length} | #{wins_a} | #{wins_b} | #{list.length - wins_a - wins_b} | #{pct(wins_a, list.length)} #{wilson(wins_a, list.length)} |"
        end
        table('## Matchups', ['Matchup', 'Games', 'First wins', 'Second wins', 'Draws', 'First win rate (95% range)'], rows)
      end

      def seat_wins
        seats = @played.first&.dig('names')&.keys or return nil
        rows  = seats.map do |seat|
          wins = @played.count { |r| r['winner'] == seat }
          "| #{seat} | #{wins} | #{pct(wins, @played.length)} | #{wilson(wins, @played.length)} |"
        end
        table('## Wins by seat', ['Seat', 'Wins', 'Win rate', '95% range'], rows)
      end

      def lengths
        counts = @played.map { |r| r['decisions'] }.sort
        return nil if counts.empty?

        stats = [counts.sum.fdiv(counts.length).round, percentile(counts, 50), percentile(counts, 90), counts.max]
        table('## Game length (decisions)', %w[Mean Median 90th Max], ["| #{stats.join(' | ')} |"])
      end

      def rules_fired
        tally = @played.each_with_object(Hash.new(0)) { |r, sum| r['rules'].each { |rule, n| sum[rule] += n } }
        total = tally.values.sum
        rows  = tally.sort_by { |_, n| -n }.map { |rule, n| "| #{rule} | #{n} | #{pct(n, total)} |" }
        table('## Bot rules used', %w[Rule Decisions Share], rows,
              '`none` means the bot had no rule for that decision and took option 1; a large share points at a gap in the bot.')
      end

      def outliers
        longest = @played.max_by(5) { |r| r['decisions'] }.map { |r| "seed #{r['seed']} (#{r['decisions']} decisions, #{r['end_reason']})" }
        common  = @played.map { |r| r['end_reason'] }.tally.max_by { |_, n| n }&.first
        rare    = @played.reject { |r| r['end_reason'] == common }.group_by { |r| r['end_reason'] }
                         .map { |reason, list| "- #{reason}: seeds #{list.first(10).map { |r| r['seed'] }.join(', ')}#{' …' if list.length > 10}" }
        "## Games to look at\n\n- Longest: #{longest.join('; ')}\n#{rare.join("\n")}".strip
      end

      def errors
        crashed = @results.select { |r| r['error'] }
        return nil if crashed.empty?

        "## Crashes\n\n#{crashed.first(20).map { |r| "- seed #{r['seed']}: #{r['error']}" }.join("\n")}"
      end

      def table(title, headers, rows, note = nil)
        ["#{title}\n", "| #{headers.join(' | ')} |", "|#{'---|' * headers.length}", *rows, (note && "\n#{note}")].compact.join("\n")
      end

      def pct(count, total) = total.zero? ? '—' : "#{(100.0 * count / total).round}%"

      def percentile(sorted, p) = sorted[((p / 100.0) * (sorted.length - 1)).round]

      def wilson(wins, total)
        return '—' if total.zero?

        z      = 1.96
        rate   = wins.fdiv(total)
        center = (rate + z**2 / (2 * total)) / (1 + z**2 / total)
        half   = z * Math.sqrt(rate * (1 - rate) / total + z**2 / (4 * total**2)) / (1 + z**2 / total)
        "#{((center - half) * 100).round}–#{((center + half) * 100).round}%"
      end
    end
  end
end
