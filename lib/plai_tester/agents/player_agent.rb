module PlaiTester
  module Agents
    class PlayerAgent
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

        response = @client.chat(model: @model, messages: messages)
        parse_response(response.dig('message', 'content'))
      end

      private

      def system_prompt
        action_list = @rules['actions'].map { |a| "- #{a['type']}: #{a['description']}" }.join("\n")
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
        recent = history.last(3).map { |t| "Turn #{t['turn']}: #{t['player']} played #{t['action']}" }.join("\n")

        <<~PROMPT
          CURRENT GAME STATE:
          #{JSON.pretty_generate(game_state)}

          YOUR AVAILABLE ACTIONS THIS TURN:
          #{available_actions.map { |a| "- #{a}" }.join("\n")}

          RECENT HISTORY:
          #{recent.empty? ? '(game just started)' : recent}

          Choose your action and respond with JSON only.
        PROMPT
      end

      def parse_response(content)
        json_str = content.match(/\{.*\}/m)&.to_s
        raise "No JSON found in player response: #{content.inspect}" unless json_str

        JSON.parse(json_str)
      end
    end
  end
end
