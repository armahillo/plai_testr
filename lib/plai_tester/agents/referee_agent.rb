module PlaiTester
  module Agents
    class RefereeAgent
      def initialize(model:, client:, rules:)
        @model  = model
        @client = client
        @rules  = rules
      end

      # Returns a hash with keys: "valid" (bool), "reason" (string), "state_changes" (hash),
      # and optionally "random_ops" (array) when the resolution requires randomness.
      def validate(player:, action:, game_state:)
        messages = [
          { role: 'system', content: system_prompt },
          { role: 'user',   content: validation_prompt(player, action, game_state) }
        ]

        # Low temperature: we want consistent, rule-bound rulings
        response = @client.chat(model: @model, messages: messages, temperature: 0.1)
        parse_response(response.dig('message', 'content'))
      end

      # Called by Runner after executing random_ops returned by validate.
      # Returns a hash with keys: "valid" (bool), "reason" (string), "state_changes" (hash).
      def resolve_random(random_results:, game_state:, action:)
        messages = [
          { role: 'system', content: system_prompt },
          { role: 'user',   content: resolve_random_prompt(random_results, action, game_state) }
        ]

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
          {"valid":true,"reason":"<explanation>","state_changes":{},"random_ops":[]}

          state_changes keys: "flags" (object), "custom" (object), "player_states" (object keyed by player name)

          random_ops is optional. Include it when resolving the action requires a random value
          (e.g. a die roll to break a tie). When random_ops is present, leave state_changes empty —
          you will be called again with the results to produce the final state_changes.

          Supported random_ops:
            {"op":"roll","sides":<integer>,"count":<integer>,"for":"<label>"}
            {"op":"coin_flip","for":"<label>"}

          The "for" label will be the key used to return each result to you.
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

      def resolve_random_prompt(random_results, action, game_state)
        <<~PROMPT
          CURRENT GAME STATE:
          #{JSON.pretty_generate(game_state)}

          ACTION being resolved:
          #{JSON.pretty_generate(action)}

          RANDOM RESULTS:
          #{JSON.pretty_generate(random_results)}

          The action was valid. Using these random results, what are the final state changes?
          Respond with JSON only: {"valid":true,"reason":"<explanation>","state_changes":{}}
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
