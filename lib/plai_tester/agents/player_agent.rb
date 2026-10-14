module PlaiTester
  module Agents
    class PlayerAgent
      MAX_PARSE_RETRIES = 2

      def initialize(name:, model:, client:, rules:)
        @name   = name
        @model  = model
        @client = client
        @rules  = rules
      end

      def take_turn(game_state, available_actions, history)
        messages = [
          { role: 'system', content: system_prompt },
          { role: 'user',   content: turn_prompt(game_state, available_actions, history) }
        ]
        chat_with_json_retry(messages)
      end

      # Called when another player has taken an action that may trigger a reaction.
      # The agent may respond with a reaction action or a no_op.
      def react_to(acting_player, triggering_action, game_state, available_reactions)
        messages = [
          { role: 'system', content: system_prompt },
          { role: 'user',   content: reaction_prompt(acting_player, triggering_action, game_state, available_reactions) }
        ]
        chat_with_json_retry(messages)
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

      MENU_CHAT_OPTIONS = { temperature: 0.6, think: false, num_ctx: 8192, num_predict: 512 }.freeze

      # Menu turn: the game supplies the rules text, a human-readable view, and a numbered list
      # of legal moves; the model only has to return the number of one of them.
      #
      # Returns { 'choice' => Integer (1-based, always valid), 'reasoning', 'plan',
      #           'attempts' => Integer, 'fallback' => Boolean }.
      # Invalid or out-of-range replies are re-prompted; after MAX_PARSE_RETRIES the first option
      # is chosen and flagged as a fallback so the report can measure reliability.
      def choose(rules_text:, view_text:, labels:, plan: nil, recent: [], prompt_note: nil)
        messages = [
          { role: 'system', content: menu_system_prompt(rules_text) },
          { role: 'user',   content: menu_turn_prompt(view_text, labels, plan, recent, prompt_note) }
        ]

        (MAX_PARSE_RETRIES + 1).times do |i|
          response = @client.chat(model: @model, messages: messages, format: MENU_SCHEMA, **MENU_CHAT_OPTIONS)
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

      DEBRIEF_CHAT_OPTIONS = { temperature: 0.6, think: false, num_ctx: 8192, num_predict: 1024 }.freeze

      # Asked once per player after the game, instead of collecting design notes every turn
      # (per-turn notes were either filler or, from larger models, always empty).
      #
      # Returns [{ 'question' => String, 'answer' => String }] in question order. A missing or
      # unparseable answer becomes an empty string; the debrief never raises on bad output.
      def debrief(rules_text:, view_text:, questions:)
        keys     = questions.each_index.map { |i| "q#{i + 1}" }
        schema   = { 'type' => 'object', 'properties' => keys.to_h { |k| [k, { 'type' => 'string' }] }, 'required' => keys }
        messages = [
          { role: 'system', content: debrief_system_prompt(rules_text) },
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

      def debrief_system_prompt(rules_text)
        <<~PROMPT
          You are #{@name}. You just finished a playtest of the board game #{@rules.dig('game', 'name')}.
          Now you are a playtester giving the game designer honest feedback.

          #{rules_text}

          HOW TO ANSWER:
          - Be specific: name actual cards, rules, and decisions from your game.
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

      def menu_system_prompt(rules_text)
        <<~PROMPT
          You are #{@name}, a player in a playtest of the board game #{@rules.dig('game', 'name')}. Play to win.

          #{rules_text}

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

      def system_prompt
        action_list = @rules['actions'].map { |a| format_action_summary(a) }.join("\n")
        phase_list  = @rules['turn_structure'].map.with_index(1) { |p, i| "#{i}. #{p['name']}: #{p['description']}" }.join("\n")
        win_list    = @rules['win_conditions'].map { |w| "- #{w['description']}" }.join("\n")

        <<~PROMPT
          You are playing a board game called #{@rules.dig('game', 'name')}. You are #{@name}.
          Your goal is to win by making strategic decisions within the rules.

          TURN PHASES:
          #{phase_list}

          AVAILABLE ACTIONS:
          #{action_list}

          WIN CONDITIONS:
          #{win_list}

          You MUST respond with valid JSON only — no prose, no markdown fences:
          {"action":"<action_type>","parameters":{},"reasoning":"<1-2 sentences>"}
        PROMPT
      end

      def turn_prompt(game_state, available_actions, history)
        # Each turn entry now has an 'actions' array; summarize non-end_turn actions per turn
        recent = history.last(3).map do |t|
          played = t['actions'].reject { |a| a['action'] == 'end_turn' }.map { |a| a['action'] }.join(', ')
          "Turn #{t['turn']}: #{t['player']} played #{played}"
        end.join("\n")

        <<~PROMPT
          CURRENT GAME STATE:
          #{JSON.pretty_generate(game_state)}

          YOUR AVAILABLE ACTIONS THIS TURN:
          #{format_available_actions(available_actions)}

          Declare "end_turn" when you have no more actions to take this turn.

          RECENT HISTORY:
          #{recent.empty? ? '(game just started)' : recent}

          Choose your action and respond with JSON only.
        PROMPT
      end

      def reaction_prompt(acting_player, triggering_action, game_state, available_reactions)
        <<~PROMPT
          CURRENT GAME STATE:
          #{JSON.pretty_generate(game_state)}

          #{acting_player} has just played:
          #{JSON.pretty_generate(triggering_action)}

          This action may allow you to react. You are not taking your turn — only responding to this action.

          YOUR AVAILABLE REACTIONS:
          #{available_reactions.empty? ? '(none)' : available_reactions.map { |a| "- #{a}" }.join("\n")}

          If you have no reaction or choose not to use one, respond with:
          {"action":"no_op","parameters":{},"reasoning":"<brief reason>"}

          Otherwise respond with your chosen reaction as JSON only.
        PROMPT
      end

      def format_action_summary(action)
        parts = ["- #{action['type']}"]
        parts << "(parameters: #{action['parameters'].join(', ')})" if action['parameters']&.any?
        parts << "— #{action['description']}" if action['description']
        parts.join(' ')
      end

      def format_available_actions(available_actions)
        available_actions.map do |type|
          rule  = @rules['actions']&.find { |a| a['type'] == type }
          params = rule&.fetch('parameters', []) || []
          params.any? ? "- #{type} (required params: #{params.join(', ')})" : "- #{type}"
        end.join("\n")
      end

      def chat_with_json_retry(messages)
        working = messages.dup

        (MAX_PARSE_RETRIES + 1).times do |i|
          response = @client.chat(model: @model, messages: working, num_predict: -1)
          content  = response.dig('message', 'content')
          begin
            return parse_response(content)
          rescue RuntimeError, JSON::ParserError => e
            raise e if i == MAX_PARSE_RETRIES

            excerpt = content.length > 500 ? "#{content[0, 300]}...[truncated]" : content
            working << { role: 'assistant', content: excerpt }
            working << { role: 'user', content: 'Your response was not valid JSON. Respond with a raw JSON object only — no prose, no markdown, no code fences.' }
          end
        end
      end

      def parse_response(content)
        cleaned = content.gsub(/<think>.*?<\/think>/m, '').strip

        if (fenced = cleaned.match(/```(?:json)?\s*(\{.*?\})\s*```/m))
          return normalize_action(JSON.parse(fenced[1]))
        end

        # Scan line-by-line and return the first line that parses as a complete JSON object.
        # This handles models that output multiple JSON objects or trailing prose after the action.
        cleaned.each_line do |line|
          stripped = line.strip
          next unless stripped.start_with?('{')
          begin
            return normalize_action(JSON.parse(stripped))
          rescue JSON::ParserError
            next
          end
        end

        raise "No JSON found in player response: #{content.inspect}"
      end

      # LLMs sometimes return "params", "required_params", or nest parameters directly
      # on the action object. Normalize everything to the canonical "parameters" key.
      def normalize_action(parsed)
        unless parsed.key?('parameters')
          params = parsed.delete('params') ||
                   parsed.delete('required_params') ||
                   parsed.slice('stack_id', 'chosen_card_name', 'card_id', 'card_ids', 'stance_arrangement')
          parsed['parameters'] = params.is_a?(Hash) ? params : {}
        end
        parsed
      end
    end
  end
end
