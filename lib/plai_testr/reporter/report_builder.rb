module PlaiTestr
  module Reporter
    class ReportBuilder
      def initialize(session_id:, rules:, game_state:, turn_log:, think_log: ThinkLog.new(''), sections: [], names: {}, debrief: true, warnings: [])
        @session_id = session_id
        @rules      = rules
        @game_state = game_state
        @turn_log   = turn_log
        @think_log  = think_log
        @sections   = sections
        @names      = names
        @debrief    = debrief
        @warnings   = warnings
      end

      def build
        report = [header, result, reliability, bot_agreement, speed, warnings, *@sections, debrief, turn_log_section].compact.join("\n\n---\n\n")
        path   = File.join(PlaiTestr.reports_dir, "#{@session_id}.md")
        File.write(path, Tables.align(report))
        path
      end

      private

      def header
        data     = @game_state.data
        settings = data['model_settings']
        bot_only = data['mode'] == 'bot'
        rows     = [
          "| **Session** | `#{@session_id}` |",
          "| **Rules version** | #{@rules.dig('game', 'version')} |",
          "| **Players** | #{@game_state.players.map { |p| name(p).include?(p) ? name(p) : "#{name(p)} (#{p})" }.join(', ')} |",
          bot_only ? '| **Player model** | none — mode: bot |' : "| **Player model** | #{data['player_model'] || 'unknown'}#{' (thinking)' if data['think']}#{" — mode: #{data['mode']}" if data['mode'] && data['mode'] != 'llm'} |",
          "| **Host** | #{data['host'] || 'unknown'} |",
          "| **Seed** | #{data['seed']} |"
        ]
        rows << "| **Personas** | #{data['personas'].map { |p, label| "#{p}: #{label}" }.join('; ')} |" if data['personas']
        rows << "| **Model settings** | #{settings.map { |key, value| "#{key} #{value}" }.join(', ')} |" if settings && !bot_only
        rows << "| **Decisions** | #{@game_state.turn} |"
        rows << "| **Wall time** | #{Duration.format(data['wall_seconds'])} |" if data['wall_seconds']
        rows << "| **Generated** | #{Time.now.strftime('%Y-%m-%d %H:%M')} |"

        "# Playtest Report: #{@rules.dig('game', 'name')}\n\n| | |\n|---|---|\n#{rows.join("\n")}"
      end

      def result
        status = @game_state.status
        winner = status['winner'] || leader
        scores = @game_state.scores.map { |p, s| "| #{name(p)} | #{s} |" }.join("\n")

        <<~MD.strip
          ## Result

          **Winner: #{winner ? name(winner) : 'none'}**#{" (#{status['end_reason'].to_s.tr('_', ' ')})" if status['end_reason']}

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
        bot       = @turn_log.count { |t| t['decider'] == 'BOT' && !t['fallback'] }
        asked     = @turn_log.reject { |t| t['auto'] || (t['decider'] == 'BOT' && !t['fallback']) }
        fallbacks = asked.count { |t| t['fallback'] }
        rate      = asked.empty? ? 0 : (100.0 * fallbacks / asked.length).round(1)
        full      = @turn_log.count { |t| t['context_full'] }

        <<~MD.strip
          ## Model reliability

          | Decisions | Asked the model | Bot rules | Only one option | Needed a retry | Fallbacks (no valid choice → 🤖 bot or 🎲 random) | Fallback rate | Context nearly full |
          |---|---|---|---|---|---|---|---|
          | #{@turn_log.length} | #{asked.length} | #{bot} | #{@turn_log.length - asked.length - bot} | #{asked.count { |t| t['attempts'].to_i > 1 }} | #{fallbacks} | #{rate}% | #{full} |
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

          On model turns the bot's choice is recorded too. Low agreement on an *obvious* rule means the model missed a clearly best move (or the rule is wrong); *default* rules are only the bot's guess. Fallback turns are left out.

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

      def warnings
        return nil if @warnings.empty?

        "## Warnings\n\n#{@warnings.tally.map { |text, count| "- #{text}#{" (×#{count})" if count > 1}" }.join("\n")}"
      end

      def debrief
        answers = @game_state.data['debrief']
        return nil unless @debrief && answers&.any?

        players = answers.map do |player, list|
          "**#{name(player)}**\n\n#{list.map { |a| "- *#{a['question']}*\n  #{a['answer'].to_s.empty? ? '_(no answer)_' : a['answer']}" }.join("\n")}"
        end

        model = @game_state.data['debrief_model']
        about = model ? "_Answered by #{model}#{' (thinking)' if @game_state.data['debrief_think']}._\n\n" : ''

        "## Debrief\n\n#{about}#{players.join("\n\n")}"
      end

      def turn_line(turn)
        parts = ["- **#{turn['turn']}. #{name(turn['player'])}"]
        parts << " · #{turn['phase']}" if turn['phase']
        parts << ':** '
        parts << "#{DECIDER_ICONS[turn['decider']]} " if turn['decider']
        parts << PlaiTestr.rename((turn['log'] || turn['label']).to_s, @names)
        parts << ' _(only option)_' if turn['auto']
        parts << " _(rule: #{turn['rule']})_" if turn['decider'] == 'BOT'
        parts << ' **[FALLBACK]**' if turn['fallback']
        parts << "\n  > #{turn['reasoning']}" unless turn['reasoning'].to_s.empty?
        parts.join
      end

      def turn_log_section
        "## Turn log\n\n<details><summary>#{@turn_log.length} decisions</summary>\n\n#{@turn_log.map { |t| turn_line(t) }.join("\n")}\n\n</details>"
      end
    end
  end
end
