module Testr
  module Agents
    class RefereeAgent
      def initialize(model:, client:, rules:)
        @model  = model
        @client = client
        @rules  = rules
      end

      # Returns a hash with keys: "valid" (bool), "reason" (string), "state_changes" (hash)
      def validate(player:, action:, game_state:)
        messages = [
          { role: 'system', content: system_prompt },
          { role: 'user',   content: validation_prompt(player, action, game_state) }
        ]

        # Low temperature: we want consistent, rule-bound rulings
        response = @client.chat(model: @model, messages: messages, temperature: 0.1)
        parse_response(response.dig('message', 'content'))
      end

      private

      def system_prompt
        <<~PROMPT
          You are the rules referee for #{@rules.dig('game', 'name')}.

          COMPLETE RULES:
          #{JSON.pretty_generate(@rules)}

          Your role is to:
          1. Determine whether a proposed action is legal given the current game state and rules.
          2. If valid, calculate the resulting state changes.
          3. If invalid, explain why clearly so the player can try again.

          You MUST respond with valid JSON only — no prose, no markdown fences:
          {"valid":true,"reason":"<explanation>","state_changes":{}}

          state_changes keys: "flags" (object), "scores" (object), "custom" (object)
        PROMPT
      end

      def validation_prompt(player, action, game_state)
        <<~PROMPT
          CURRENT GAME STATE:
          #{JSON.pretty_generate(game_state)}

          PROPOSED ACTION by #{player}:
          #{JSON.pretty_generate(action)}

          Is this action valid? If so, what are the state changes?
          Respond with JSON only.
        PROMPT
      end

      def parse_response(content)
        json_str = content.match(/\{.*\}/m)&.to_s
        raise "No JSON found in referee response: #{content.inspect}" unless json_str

        JSON.parse(json_str)
      end
    end
  end
end
