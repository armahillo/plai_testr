module PlaiTester
  module Agents
    class PlayerAgent
      MAX_PARSE_RETRIES = 2

      def initialize(name:, model:, client:, rules:, think: false)
        @name   = name
        @model  = model
        @client = client
        @rules  = rules
        @think  = think
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

      MENU_CHAT_OPTIONS     = { temperature: 0.6, think: false, num_ctx: 8192, num_predict: 512 }.freeze
      THINKING_CHAT_OPTIONS = { temperature: 0.6, think: true, num_ctx: 16384, num_predict: 8192 }.freeze
      UNTHINKING_CHAT_OPTIONS = { temperature: 0.6, think: false, num_ctx: 16384, num_predict: 512 }.freeze

      # Menu turn: the game supplies the rules text, a human-readable view, and a numbered list
      # of legal moves; the model only has to return the number of one of them.
      #
      # Returns { 'choice' => Integer (1-based, always valid), 'reasoning', 'plan',
      #           'attempts' => Integer, 'fallback' => Boolean }.
      # Invalid or out-of-range replies are re-prompted; after MAX_PARSE_RETRIES the first option
      # is chosen and flagged as a fallback so the report can measure reliability.
      def choose(rules_text:, view_text:, labels:, plan: nil, recent: [], prompt_note: nil, persona: nil, think: true)
        messages = [
          { role: 'system', content: menu_system_prompt(rules_text, persona) },
          { role: 'user',   content: menu_turn_prompt(view_text, labels, plan, recent, prompt_note) }
        ]

        (MAX_PARSE_RETRIES + 1).times do |i|
          response = @client.chat(model: @model, messages: messages, format: MENU_SCHEMA, **chat_options(think))
          content  = response.dig('message', 'content').to_s
          parsed   = parse_menu_response(content)
          choice   = parsed.is_a?(Hash) && parsed['choice'].to_s =~ /\A\d+\z/ ? parsed['choice'].to_i : nil

          if choice && choice.between?(1, labels.length)
            return parsed.slice('reasoning', 'plan').merge('choice' => choice, 'attempts' => i + 1, 'fallback' => false)
          end

          messages += [
            { role: 'assistant', content: content[0, 300] },
            { role: 'user',      content: "That was not a valid choice. Reply with JSON whose \"choice\" is a number from 1 to #{labels.length}." }
          ]
        end

        { 'choice' => 1, 'reasoning' => 'fallback: no valid choice after retries', 'plan' => plan,
          'attempts' => MAX_PARSE_RETRIES + 1, 'fallback' => true }
      end

      def choose_many(rules_text:, view_text:, labels:, min:, max:, plan: nil, recent: [], prompt_note: nil, persona: nil, think: true)
        rule     = min == max ? "exactly #{min}" : "between #{min} and #{max}"
        note     = [prompt_note, "Choose #{rule} different options. Reply with JSON: {\"choices\": [<numbers>], \"reasoning\": \"...\", \"plan\": \"...\"}"].compact.join("\n")
        messages = [
          { role: 'system', content: menu_system_prompt(rules_text, persona) },
          { role: 'user',   content: menu_turn_prompt(view_text, labels, plan, recent, note) }
        ]

        (MAX_PARSE_RETRIES + 1).times do |i|
          response = @client.chat(model: @model, messages: messages, format: PICK_SCHEMA, **chat_options(think))
          content  = response.dig('message', 'content').to_s
          parsed   = parse_menu_response(content)
          choices  = parsed.is_a?(Hash) && Array(parsed['choices']).map { |c| Integer(c, exception: false) }

          if choices && choices.none?(&:nil?) && choices.uniq.length == choices.length &&
             choices.length.between?(min, max) && choices.all? { |c| c.between?(1, labels.length) }
            return parsed.slice('reasoning', 'plan').merge('choices' => choices, 'attempts' => i + 1, 'fallback' => false)
          end

          messages += [
            { role: 'assistant', content: content[0, 300] },
            { role: 'user',      content: "That was not valid. \"choices\" must list #{rule} different numbers from 1 to #{labels.length}." }
          ]
        end

        { 'choices' => (1..min).to_a, 'reasoning' => 'fallback: no valid choice after retries', 'plan' => plan,
          'attempts' => MAX_PARSE_RETRIES + 1, 'fallback' => true }
      end

      DEBRIEF_CHAT_OPTIONS = { temperature: 0.6, think: false, num_ctx: 16384, num_predict: 1024 }.freeze

      # Asked once per player after the game, instead of collecting design notes every turn
      # (per-turn notes were either filler or, from larger models, always empty).
      #
      # Returns [{ 'question' => String, 'answer' => String }] in question order. A missing or
      # unparseable answer becomes an empty string; the debrief never raises on bad output.
      def debrief(rules_text:, view_text:, questions:, persona: nil)
        keys     = questions.each_index.map { |i| "q#{i + 1}" }
        schema   = { 'type' => 'object', 'properties' => keys.to_h { |k| [k, { 'type' => 'string' }] }, 'required' => keys }
        messages = [
          { role: 'system', content: debrief_system_prompt(rules_text, persona) },
          { role: 'user',   content: debrief_prompt(view_text, questions, keys) }
        ]

        parsed = {}
        (MAX_PARSE_RETRIES + 1).times do
          response = @client.chat(model: @model, messages: messages, format: schema, **DEBRIEF_CHAT_OPTIONS)
          parsed   = parse_menu_response(response.dig('message', 'content').to_s)
          break if parsed.is_a?(Hash) && keys.any? { |k| !parsed[k].to_s.strip.empty? }
        end
        parsed = {} unless parsed.is_a?(Hash)

        questions.zip(keys).map { |q, k| { 'question' => q, 'answer' => parsed[k].to_s.strip } }
      end

      private

      def chat_options(think)
        return MENU_CHAT_OPTIONS unless @think

        think ? THINKING_CHAT_OPTIONS : UNTHINKING_CHAT_OPTIONS
      end

      def debrief_system_prompt(rules_text, persona)
        <<~PROMPT
          You are #{@name}. You just finished a playtest of the board game #{@rules.dig('game', 'name')}.
          Now you are a playtester giving the game designer honest feedback.

          #{rules_text}
          #{"\nTHE STRATEGY YOU PLAYED:\n#{persona}\n" if persona}

          HOW TO ANSWER:
          - Be specific: name actual cards, rules, and decisions from your game.
          - Stick to the facts under YOUR FINAL POSITION. Describe a card by the text given there, not from memory,
            and check the log before saying something did or did not happen.
          - 1-3 sentences per answer. Criticism is welcome; the designer wants to find problems.
          - If nothing applies, answer "nothing" rather than inventing a problem.

          Reply with JSON only.
        PROMPT
      end

      def debrief_prompt(view_text, questions, keys)
        list = questions.zip(keys).map { |q, k| "#{k}: #{q}" }.join("\n")

        <<~PROMPT
          YOUR FINAL POSITION:
          #{view_text}

          QUESTIONS:
          #{list}

          Reply with JSON only: {#{keys.map { |k| "\"#{k}\": \"<answer>\"" }.join(', ')}}
        PROMPT
      end

      def menu_system_prompt(rules_text, persona)
        <<~PROMPT
          You are #{@name}, a player in a playtest of the board game #{@rules.dig('game', 'name')}. Play to win.

          #{rules_text}
          #{"\nYOUR STRATEGY (follow it in every decision, from the first draft pick to the last attack):\n#{persona}\n" if persona}

          HOW TO PLAY EACH TURN:
          - You get YOUR VIEW (only what you are allowed to know) and a numbered list of LEGAL MOVES.
          - Choose ONLY a number from LEGAL MOVES. Never invent cards or moves.
          - Do not assume anything about hidden cards beyond what YOUR VIEW says.
          - Keep a one-line plan and update it; your previous plan is shown to you.

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
