module Testr
  module Reporter
    class ReportBuilder
      def initialize(session_id:, rules:, game_state:, turn_log:, stall_context: nil)
        @session_id    = session_id
        @rules         = rules
        @game_state    = game_state
        @turn_log      = turn_log
        @stall_context = stall_context
      end

      def build
        sections = [header, summary, player_performance, turn_log_section, observations]
        sections << stall_section if @stall_context
        report = sections.join("\n\n---\n\n")
        path   = File.join(Testr::REPORTS_DIR, "#{@session_id}.md")
        File.write(path, report)
        path
      end

      private

      def header
        <<~MD.strip
          # Playtest Report: #{@rules.dig('game', 'name')}

          | | |
          |---|---|
          | **Session** | `#{@session_id}` |
          | **Rules version** | #{@rules.dig('game', 'version')} |
          | **Players** | #{@game_state.players.join(', ')} |
          | **Total turns** | #{@game_state.turn} |
          | **Generated** | #{Time.now.strftime('%Y-%m-%d %H:%M')} |
        MD
      end

      def summary
        winner = @game_state.scores.max_by { |_, v| v.to_i }&.first
        score_lines = @game_state.scores.map { |p, s| "| #{p} | #{s} |" }.join("\n")

        <<~MD.strip
          ## Summary

          The game concluded after **#{@game_state.turn} turns**.

          ### Final scores

          | Player | Score |
          |---|---|
          #{score_lines}

          **Winner: #{winner || 'undetermined'}**

          ### Flags at game end

          #{@game_state.flags.empty? ? '_none_' : @game_state.flags.map { |k, v| "- `#{k}`: #{v}" }.join("\n")}
        MD
      end

      def player_performance
        lines = ["## Player Performance"]

        @game_state.players.each do |player|
          turns  = @turn_log.select { |t| t['player'] == player }
          counts = turns.group_by { |t| t['action'] }.transform_values(&:count)

          lines << "\n### #{player}"
          lines << "- Turns taken: #{turns.length}"
          lines << "- Final score: #{@game_state.scores[player]}"

          unless counts.empty?
            lines << "- Actions:"
            counts.each { |action, count| lines << "  - `#{action}`: #{count}x" }
          end
        end

        lines.join("\n")
      end

      def turn_log_section
        lines = ["## Turn-by-Turn Log"]

        @turn_log.each do |turn|
          lines << "\n**Turn #{turn['turn']} — #{turn['player']}**: `#{turn['action']}` #{format_params(turn['parameters'])}"
          lines << "> #{turn['reasoning']}" if turn['reasoning']
        end

        lines.join("\n")
      end

      def observations
        spread = score_spread

        <<~MD.strip
          ## Observations

          _Automated observations for balance and flow assessment._

          - **Game length**: #{@game_state.turn} turns
          - **Score spread**: #{spread}
          - **Turn distribution**: #{turn_distribution}
        MD
      end

      def score_spread
        values = @game_state.scores.values.map(&:to_i)
        return 'N/A' if values.empty?

        "#{values.min}–#{values.max} (delta: #{values.max - values.min})"
      end

      def turn_distribution
        counts = @turn_log.group_by { |t| t['player'] }.transform_values(&:count)
        counts.map { |p, n| "#{p}: #{n}" }.join(', ')
      end

      def stall_section
        ctx      = @stall_context
        attempts = ctx[:attempts].map do |a|
          <<~MD.strip
            **Attempt #{a[:attempt]}**
            - Action: `#{a[:action]['action']}` #{format_params(a[:action]['parameters'])}
            - Reasoning: #{a[:action]['reasoning']}
            - Rejection: #{a[:rejection]}
          MD
        end.join("\n\n")

        <<~MD.strip
          ## Session Stalled

          > The session ended because **#{ctx[:player]}** could not produce a valid action on turn #{ctx[:turn]}
          > after #{ctx[:attempts].length} attempts. Review the attempts and rejections below to identify
          > what rules clarification is needed.

          ### Game state at stall

          ```json
          #{JSON.pretty_generate(ctx[:game_state])}
          ```

          ### Failed attempts

          #{attempts}
        MD
      end

      def format_params(params)
        return '' if params.nil? || params.empty?

        params.map { |k, v| "#{k}=#{v}" }.join(' ')
      end
    end
  end
end
