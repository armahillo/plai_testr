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
      #
      # context is a Protocol::Context hash describing why validation is being requested
      # (turn_action vs. reaction), so the referee can apply the correct rules.
      def validate(player:, action:, game_state:, context: Protocol::Context.turn_action)
        messages = [
          { role: 'system', content: system_prompt },
          { role: 'user',   content: validation_prompt(player, action, game_state, context) }
        ]

        # Low temperature: we want consistent, rule-bound rulings
        response = @client.chat(model: @model, messages: messages, temperature: 0.1)
        parse_response(response.dig('message', 'content'))
      end

      # Called by Runner#setup before the game loop begins.
      # Returns a hash matching the apply_changes structure: "flags", "custom", "player_states".
      # Use a higher temperature than validate — we want varied initial distributions.
      def compute_initial_state(setup_steps:, components:, players:)
        messages = [
          { role: 'system', content: system_prompt },
          { role: 'user',   content: setup_prompt(setup_steps, components, players) }
        ]

        response = @client.chat(model: @model, messages: messages, temperature: 0.7)
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

      def validation_prompt(player, action, game_state, context)
        context_line = case context['type']
        when 'reaction'
          trigger = context['trigger']
          "CONTEXT: #{player} is reacting to #{trigger['player']}'s action:\n#{JSON.pretty_generate(trigger['action'])}"
        else
          "CONTEXT: #{player}'s regular turn action"
        end

        <<~PROMPT
          CURRENT GAME STATE:
          #{JSON.pretty_generate(game_state)}

          #{context_line}

          PROPOSED ACTION by #{player}:
          #{JSON.pretty_generate(action)}

          Is this action valid? If so, what are the state changes?
          Respond with JSON only.
        PROMPT
      end

      def setup_prompt(setup_steps, components, players)
        steps = setup_steps.map { |s| "#{s['step']}. #{s['description']}" }.join("\n")

        <<~PROMPT
          You are setting up a new game of #{@rules.dig('game', 'name')} for: #{players.join(', ')}.

          GAME COMPONENTS:
          #{JSON.pretty_generate(components)}

          SETUP STEPS:
          #{steps}

          Execute these setup steps to produce the starting game state.
          Use varied, realistic distributions (e.g. shuffle and deal cards randomly).

          Respond with JSON only — no prose, no markdown fences:
          {"flags":{},"custom":{},"player_states":{"#{players.first}":{"hand":[],"score":0,"flags":{}}}}

          player_states must contain exactly these keys: #{players.join(', ')}
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
