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

      private

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
