module PlaiTester
  module Reporter
    class ModelComparison
      BASE_COLUMNS = [
        'Model', 'Host', 'Games', 'Seeds', 'Avg minutes', 'Avg s / call', 'Prompt tok/s', 'Gen tok/s',
        'Avg / max prompt tokens', 'Retries', 'Fallbacks', 'Endings'
      ].freeze

      BASE_NOTES = [
        '*Avg s / call, Prompt tok/s, Gen tok/s*: Ollama\'s own timings per model call. Compare hosts on the same model and seeds. Sessions from before these were logged show —.',
        '*Retries / fallbacks*: reliability. A fallback means the model never gave a valid choice and option 1 was used.',
        '*Endings*: each game\'s end reason and how often it happened.',
        '*Debrief answers given*: non-empty, non-"nothing" answers to the end-of-game questions. Read them in the session reports; count alone says little.'
      ].freeze

      def initialize(sessions_dir, since: nil)
        @sessions_dir = sessions_dir
        @since        = since
      end

      def to_markdown
        groups = sessions.group_by { |s| [s[:model], s[:host]] }
        return "No completed sessions with a recorded player model#{" since #{@since}" if @since}.\n" if groups.empty?

        headers = BASE_COLUMNS + extra_columns.map(&:first) + ['Debrief answers given']
        rows    = groups.map { |(model, host), list| "| #{row(model, host, list).join(' | ')} |" }

        <<~MD
          # #{title}

          Generated #{Time.now.strftime('%Y-%m-%d %H:%M')}#{" — sessions since #{@since}" if @since}.

          | #{headers.join(' | ')} |
          |#{'---|' * headers.length}
          #{rows.join("\n")}

          **How to read it**
          #{(BASE_NOTES + notes).map { |n| "- #{n}" }.join("\n")}
        MD
      end

      private

      def title = 'Model comparison'

      def extra_columns = []

      def notes = []

      def sessions
        Dir.glob(File.join(@sessions_dir, '*', 'state.json')).filter_map do |path|
          id = File.basename(File.dirname(path))
          next if @since && id < @since

          data  = JSON.parse(File.read(path))
          state = data['game_state']
          model = state.dig('custom', 'player_model')
          next unless data['status'] == 'completed' && model

          { model: model, host: state.dig('custom', 'host') || 'unknown', seed: state.dig('custom', 'seed'), state: state,
            turns: data['turn_log'].reject { |t| t['auto'] }, log: ThinkLog.load(File.join(File.dirname(path), 'think.log')) }
        rescue JSON::ParserError
          nil
        end
      end

      def row(model, host, list)
        logs    = list.map { |s| s[:log] }
        turns   = list.flat_map { |s| s[:turns] }
        tokens  = logs.flat_map { |l| l.values('prompt_tokens') }
        answers = list.flat_map { |s| s[:state].dig('custom', 'debrief').to_h.values.flatten }
        given   = answers.count { |a| !a['answer'].to_s.strip.empty? && !a['answer'].to_s.strip.match?(/\Anothing\.?\z/i) }

        [
          "`#{model}`", host, list.length, list.map { |s| s[:seed] }.sort.join(', '),
          avg(logs.filter_map(&:minutes), 1),
          avg(logs.flat_map { |l| l.values('total_s') }, 1),
          avg(logs.flat_map { |l| l.values('prompt_tps') }, 0),
          avg(logs.flat_map { |l| l.values('eval_tps') }, 1),
          tokens.empty? ? '—' : "#{avg(tokens, 0)} / #{tokens.max.round}",
          turns.count { |t| t['attempts'].to_i > 1 },
          turns.count { |t| t['fallback'] },
          list.map { |s| s[:state].dig('flags', 'end_reason') || 'unknown' }.tally.map { |r, c| "#{r} #{c}" }.join(', '),
          *extra_columns.map { |_, value| value.call(list) },
          answers.empty? ? '—' : "#{given}/#{answers.length}"
        ]
      end

      def avg(values, digits)
        return '—' if values.empty?

        mean = values.sum.to_f / values.length
        digits.zero? ? mean.round : mean.round(digits)
      end
    end
  end
end
