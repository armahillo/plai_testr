module PlaiTester
  module Reporter
    class ReportBuilder
      def initialize(session_id:, rules:, game_state:, turn_log:, think_log: ThinkLog.new(''), sections: [])
        @session_id = session_id
        @rules      = rules
        @game_state = game_state
        @turn_log   = turn_log
        @think_log  = think_log
        @sections   = sections
      end

      def build
        report = [header, result, reliability, speed, *@sections, turn_log_section].join("\n\n---\n\n")
        path   = File.join(PlaiTester.reports_dir, "#{@session_id}.md")
        File.write(path, report)
        path
      end

      private

      def header
        custom = @game_state.custom

        <<~MD.strip
          # Playtest Report: #{@rules.dig('game', 'name')}

          | | |
          |---|---|
          | **Session** | `#{@session_id}` |
          | **Rules version** | #{@rules.dig('game', 'version')} |
          | **Players** | #{@game_state.players.join(', ')} |
          | **Player model** | #{custom['player_model'] || 'unknown'} |
          | **Host** | #{custom['host'] || 'unknown'} |
          | **Seed** | #{custom['seed']} |
          | **Decisions** | #{@game_state.turn} |
          | **Generated** | #{Time.now.strftime('%Y-%m-%d %H:%M')} |
        MD
      end

      def result
        flags  = @game_state.flags
        winner = flags['winner'] || leader
        scores = @game_state.scores.map { |p, s| "| #{p} | #{s} |" }.join("\n")

        <<~MD.strip
          ## Result

          **Winner: #{winner || 'none'}**#{" (#{flags['end_reason'].to_s.tr('_', ' ')})" if flags['end_reason']}

          | Player | Score |
          |---|---|
          #{scores}
        MD
      end

      def leader
        top = @game_state.scores.select { |_, s| s.to_i.positive? }.max_by { |_, s| s.to_i }
        top && @game_state.scores.values.count(top.last) == 1 ? top.first : nil
      end

      def reliability
        asked     = @turn_log.reject { |t| t['auto'] }
        fallbacks = asked.count { |t| t['fallback'] }
        rate      = asked.empty? ? 0 : (100.0 * fallbacks / asked.length).round(1)

        <<~MD.strip
          ## Model reliability

          | Decisions | Asked the model | Only one option | Needed a retry | Fallbacks (no valid choice → option 1) | Fallback rate |
          |---|---|---|---|---|---|
          | #{@turn_log.length} | #{asked.length} | #{@turn_log.length - asked.length} | #{asked.count { |t| t['attempts'].to_i > 1 }} | #{fallbacks} | #{rate}% |
        MD
      end

      def speed
        log = @think_log
        return "## Speed\n\nNo model calls were logged." if log.calls.empty?

        cell = ->(value, digits = 1) { value ? value.round(digits) : '—' }

        <<~MD.strip
          ## Speed

          | Model calls | Minutes | Avg s / call | Avg prompt tokens | Prompt tok/s | Gen tok/s | Model load s (total) |
          |---|---|---|---|---|---|---|
          | #{log.calls.length} | #{cell.call(log.minutes)} | #{cell.call(log.average('total_s'))} | #{cell.call(log.average('prompt_tokens'), 0)} | #{cell.call(log.average('prompt_tps'), 0)} | #{cell.call(log.average('eval_tps'))} | #{cell.call(log.values('load_s').sum)} |
        MD
      end

      def turn_log_section
        lines = @turn_log.map do |t|
          line = "- **#{t['turn']}. #{t['player']}:** #{t['label']}#{' _(only option)_' if t['auto']}#{' **[FALLBACK]**' if t['fallback']}"
          t['reasoning'].to_s.empty? ? line : "#{line}\n  > #{t['reasoning']}"
        end

        "## Turn log\n\n<details><summary>#{lines.length} decisions</summary>\n\n#{lines.join("\n")}\n\n</details>"
      end
    end
  end
end
