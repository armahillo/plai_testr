module PlaiTester
  module Reporter
    class ReportBuilder
      def initialize(session_id:, rules:, game_state:, turn_log:, think_log: ThinkLog.new(''), sections: [], names: {})
        @session_id = session_id
        @rules      = rules
        @game_state = game_state
        @turn_log   = turn_log
        @think_log  = think_log
        @sections   = sections
        @names      = names
      end

      def build
        report = [header, result, reliability, bot_agreement, speed, *@sections, turn_log_section].compact.join("\n\n---\n\n")
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
          | **Players** | #{@game_state.players.map { |p| name(p) == p ? p : "#{name(p)} (#{p})" }.join(', ')} |
          | **Player model** | #{custom['player_model'] || 'unknown'}#{' (thinking)' if custom['think']}#{" — mode: #{custom['mode']}" if custom['mode'] && custom['mode'] != 'llm'} |
          | **Host** | #{custom['host'] || 'unknown'} |
          | **Seed** | #{custom['seed']} |#{"\n| **Personas** | #{custom['personas'].map { |p, label| "#{p}: #{label}" }.join('; ')} |" if custom['personas']}
          | **Decisions** | #{@game_state.turn} |
          | **Generated** | #{Time.now.strftime('%Y-%m-%d %H:%M')} |
        MD
      end

      def result
        flags  = @game_state.flags
        winner = flags['winner'] || leader
        scores = @game_state.scores.map { |p, s| "| #{name(p)} | #{s} |" }.join("\n")

        <<~MD.strip
          ## Result

          **Winner: #{winner ? name(winner) : 'none'}**#{" (#{flags['end_reason'].to_s.tr('_', ' ')})" if flags['end_reason']}

          | Player | Score |
          |---|---|
          #{scores}
        MD
      end

      def name(player) = @names.fetch(player, player)

      def leader
        top = @game_state.scores.select { |_, s| s.to_i.positive? }.max_by { |_, s| s.to_i }
        top && @game_state.scores.values.count(top.last) == 1 ? top.first : nil
      end

      def reliability
        scripted  = @turn_log.count { |t| t['decider'] == 'rule' }
        asked     = @turn_log.reject { |t| t['auto'] || t['decider'] == 'rule' }
        fallbacks = asked.count { |t| t['fallback'] }
        rate      = asked.empty? ? 0 : (100.0 * fallbacks / asked.length).round(1)

        <<~MD.strip
          ## Model reliability

          | Decisions | Asked the model | Bot rules | Only one option | Needed a retry | Fallbacks (no valid choice → option 1) | Fallback rate |
          |---|---|---|---|---|---|---|
          | #{@turn_log.length} | #{asked.length} | #{scripted} | #{@turn_log.length - asked.length - scripted} | #{asked.count { |t| t['attempts'].to_i > 1 }} | #{fallbacks} | #{rate}% |
        MD
      end

      def bot_agreement
        shadowed = @turn_log.select { |t| t['bot_rule'] }
        return nil if shadowed.empty?

        rows = shadowed.group_by { |t| [t['bot_rule'], t['bot_obvious']] }.sort_by { |(rule, obvious), _| [obvious ? 0 : 1, rule] }.map do |(rule, obvious), list|
          agreed = list.count { |t| Array(t['choice']).sort == Array(t['bot_choice']).sort }
          "| #{rule} | #{obvious ? 'obvious' : 'default'} | #{list.length} | #{agreed} | #{(100.0 * agreed / list.length).round}% |"
        end

        <<~MD.strip
          ## Bot agreement

          On model turns the bot's choice is recorded too. Low agreement on an *obvious* rule means the model missed a clearly best move (or the rule is wrong); *default* rules are only the bot's guess.

          | Bot rule | Kind | Model turns | Model agreed | Agreement |
          |---|---|---|---|---|
          #{rows.join("\n")}
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

      def decider_icon(turn)
        return '' unless @game_state.custom['mode'] == 'hybrid' && !turn['auto']

        turn['decider'] == 'rule' ? '🤖 ' : '🧠 '
      end

      def turn_log_section
        lines = @turn_log.map do |t|
          line = "- **#{t['turn']}. #{name(t['player'])}#{" · #{t['phase']}" if t['phase']}:** #{decider_icon(t)}#{t['log'] || t['label']}#{' _(only option)_' if t['auto']}#{" _(rule: #{t['rule']})_" if t['decider'] == 'rule'}#{' **[FALLBACK]**' if t['fallback']}"
          t['reasoning'].to_s.empty? ? line : "#{line}\n  > #{t['reasoning']}"
        end

        "## Turn log\n\n<details><summary>#{lines.length} decisions</summary>\n\n#{lines.join("\n")}\n\n</details>"
      end
    end
  end
end
