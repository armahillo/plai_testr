module PlaiTestr
  module Agents
    class PlayerAgent
      MAX_PARSE_RETRIES = 2

      def initialize(name:, model:, client:, game_name:, settings: PlaiTestr.config.model_settings, think: false)
        @name      = name
        @model     = model
        @client    = client
        @game_name = game_name
        @settings  = settings
        @think     = think
      end

      # Response contract for menu turns. Ollama enforces this schema via `format`.
      MENU_SCHEMA = {
        'type'       => 'object',
        'properties' => {
          'choice'      => { 'type' => 'integer' },
          'reasoning'   => { 'type' => 'string' },
          'plan'        => { 'type' => 'string' }
        },
        'required' => %w[choice reasoning plan]
      }.freeze

      PICK_SCHEMA = {
        'type'       => 'object',
        'properties' => {
          'choices'   => { 'type' => 'array', 'items' => { 'type' => 'integer' } },
          'reasoning' => { 'type' => 'string' },
          'plan'      => { 'type' => 'string' }
        },
        'required' => %w[choices reasoning plan]
      }.freeze

      # Menu turn: the game supplies the rules text, a human-readable view, and a numbered list
      # of legal moves; the model only has to return the number of one of them.
      #
      # Returns { 'choice' => Integer (1-based, always valid), 'reasoning', 'plan',
      #           'attempts' => Integer, 'fallback' => Boolean }.
      # Invalid or out-of-range replies are re-prompted; after MAX_PARSE_RETRIES 'choice' is nil
      # and 'fallback' is true, and the runner picks the move instead.
      def choose(rules_text:, view_text:, labels:, plan: nil, recent: [], prompt_note: nil, persona: nil, think: true)
        messages = menu_messages(rules_text:, view_text:, labels:, plan:, recent:, prompt_note:, persona:)

        ask(messages, MENU_SCHEMA, think, plan) do |parsed|
          choice = parsed['choice'].to_s =~ /\A\d+\z/ ? parsed['choice'].to_i : nil
          next { 'choice' => choice } if choice&.between?(1, labels.length)

          "That was not a valid choice. Reply with JSON whose \"choice\" is a number from 1 to #{labels.length}."
        end
      end

      def choose_many(rules_text:, view_text:, labels:, min:, max:, plan: nil, recent: [], prompt_note: nil, persona: nil, think: true)
        rule     = min == max ? "exactly #{min}" : "between #{min} and #{max}"
        note     = [prompt_note, "Choose #{rule} different options. Reply with JSON: {\"choices\": [<numbers>], \"reasoning\": \"...\", \"plan\": \"...\"}"].compact.join("\n")
        messages = menu_messages(rules_text:, view_text:, labels:, plan:, recent:, prompt_note: note, persona:)

        ask(messages, PICK_SCHEMA, think, plan) do |parsed|
          choices = Array(parsed['choices']).map { |c| Integer(c, exception: false) }
          valid   = choices.none?(&:nil?) && choices.uniq.length == choices.length &&
                    choices.length.between?(min, max) && choices.all? { |c| c.between?(1, labels.length) }
          next { 'choices' => choices } if valid

          "That was not valid. \"choices\" must list #{rule} different numbers from 1 to #{labels.length}."
        end
      end

      def prompt_tokens(**prompt)
        @client.chat(model: @model, messages: menu_messages(**prompt), **chat_options(true).merge(num_predict: 1))['prompt_eval_count'].to_i
      end

      def context_size = @think ? @settings[:long_context_size] : @settings[:context_size]

      # Asked once per player after the game, instead of collecting design notes every turn
      # (per-turn notes were either filler or, from larger models, always empty).
      #
      # Returns [{ 'question' => String, 'answer' => String }] in question order. A missing or
      # unparseable answer becomes an empty string; the debrief never raises on bad output.
      def debrief(rules_text:, view_text:, questions:, persona: nil, summary: nil, think: false)
        keys     = questions.each_index.map { |i| "q#{i + 1}" }
        schema   = { 'type' => 'object', 'properties' => keys.to_h { |k| [k, { 'type' => 'string' }] }, 'required' => keys }
        messages = [
          { role: 'system', content: debrief_system_prompt(rules_text, persona) },
          { role: 'user',   content: debrief_prompt(view_text, summary, questions, keys) }
        ]
        budget   = think ? @settings[:think_budget] + @settings[:debrief_budget] : @settings[:debrief_budget]
        options  = { temperature: @settings[:temperature], think: think, num_ctx: @settings[:long_context_size], num_predict: budget }

        parsed = {}
        (MAX_PARSE_RETRIES + 1).times do
          response = @client.chat(model: @model, messages: messages, format: schema, **options)
          parsed   = parse_menu_response(response.dig('message', 'content').to_s)
          break if parsed.is_a?(Hash) && keys.any? { |k| !parsed[k].to_s.strip.empty? }
        end
        parsed = {} unless parsed.is_a?(Hash)

        questions.zip(keys).map { |q, k| { 'question' => q, 'answer' => parsed[k].to_s.strip } }
      end

      def menu_messages(rules_text:, view_text:, labels:, plan: nil, recent: [], prompt_note: nil, persona: nil)
        [
          { role: 'system', content: menu_system_prompt(rules_text, persona) },
          { role: 'user',   content: menu_turn_prompt(view_text, labels, plan, recent, prompt_note) }
        ]
      end

      private

      def ask(messages, schema, think, plan)
        context_full = false

        (MAX_PARSE_RETRIES + 1).times do |i|
          response     = @client.chat(model: @model, messages: messages, format: schema, **chat_options(think))
          context_full ||= response['context_full'] == true
          content      = response.dig('message', 'content').to_s
          parsed       = parse_menu_response(content)
          verdict      = parsed.is_a?(Hash) ? yield(parsed) : 'That was not valid JSON. Reply with JSON only.'
          return parsed.slice('reasoning', 'plan').merge(verdict, 'attempts' => i + 1, 'fallback' => false, 'context_full' => context_full) if verdict.is_a?(Hash)

          messages += [
            { role: 'assistant', content: content[0, 300] },
            { role: 'user',      content: verdict }
          ]
        end

        { 'choice' => nil, 'choices' => nil, 'reasoning' => nil, 'plan' => plan,
          'attempts' => MAX_PARSE_RETRIES + 1, 'fallback' => true, 'context_full' => context_full }
      end

      def chat_options(think)
        base = { temperature: @settings[:temperature], num_ctx: context_size }
        return base.merge(think: false, num_predict: @settings[:menu_budget]) unless @think && think

        base.merge(think: true, num_predict: @settings[:think_budget])
      end

      def debrief_system_prompt(rules_text, persona)
        <<~PROMPT
          You are #{@name}. You just finished a playtest of the tabletop game #{@game_name}.
          Now you are a playtester giving the game designer honest feedback.

          #{rules_text}
          #{"\nTHE STRATEGY YOU PLAYED: #{persona}\n" if persona}

          HOW TO ANSWER:
          - Answer from GAME SUMMARY first: its facts were counted by the game engine and are correct.
            Use YOUR FINAL POSITION and its log for detail. Never contradict the summary.
          - Only say a player did something if the summary or the log shows it. When you mention an event, name its round or decision.
          - Speak from your own experience: what you planned (YOUR PLAN AS IT CHANGED), what happened, and why.
          - Be specific: name actual components, rules, and decisions. 1-3 sentences per answer.
            Criticism is welcome; the designer wants to find problems.
          - If the facts do not answer a question, say "not in the facts" or "nothing" rather than guessing.

          Reply with JSON only.
        PROMPT
      end

      def debrief_prompt(view_text, summary, questions, keys)
        list = questions.zip(keys).map { |q, k| "#{k}: #{q}" }.join("\n")

        <<~PROMPT
          #{"GAME SUMMARY:\n#{summary}\n" if summary}
          YOUR FINAL POSITION:
          #{view_text}

          QUESTIONS:
          #{list}

          Reply with JSON only: {#{keys.map { |k| "\"#{k}\": \"<answer>\"" }.join(', ')}}
        PROMPT
      end

      def menu_system_prompt(rules_text, persona)
        <<~PROMPT
          You are #{@name}, a player in a playtest of the tabletop game #{@game_name}. Play to win.

          #{rules_text}
          #{"\nYOUR STRATEGY (follow it in every decision): #{persona}\n" if persona}

          HOW TO PLAY EACH TURN:
          - You get YOUR VIEW (only what you are allowed to know) and a numbered list of LEGAL MOVES.
          - Choose ONLY a number from LEGAL MOVES. Never invent cards or moves.
          - Do not assume anything about hidden cards beyond what YOUR VIEW says.
          - Keep a one-line plan and update it; your previous plan is shown to you.
          - RECENT EVENTS lines starting with BOT: or RNG: were moves made for you automatically, not by you.

          Reply with JSON only: {"choice": <number>, "reasoning": "<1-3 sentences>", "plan": "<one line>"}
        PROMPT
      end

      def menu_turn_prompt(view_text, labels, plan, recent, prompt_note)
        moves = labels.each_with_index.map { |label, i| "#{i + 1}. #{label}" }.join("\n")

        <<~PROMPT
          YOUR VIEW:
          #{view_text}

          RECENT EVENTS:
          #{recent.empty? ? '(none yet)' : recent.map { |r| "- #{r}" }.join("\n")}

          YOUR PLAN SO FAR: #{plan.to_s.empty? ? '(none yet)' : plan}
          #{"\nNOTE: #{prompt_note}\n" if prompt_note}
          LEGAL MOVES:
          #{moves}

          Reply with JSON only.
        PROMPT
      end

      def parse_menu_response(content)
        cleaned = content.gsub(/<think>.*?<\/think>/m, '').strip
        json    = cleaned[/\{.*\}/m]
        json && JSON.parse(json)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
