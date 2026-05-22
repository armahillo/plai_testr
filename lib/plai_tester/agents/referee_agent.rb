module PlaiTester
  module Agents
    class RefereeAgent
      MAX_PARSE_RETRIES = 2

      def initialize(model:, client:, rules:)
        @model  = model
        @client = client
        @rules  = rules
      end

      # Returns {"valid": bool, "reason": string}.
      # State changes are the runner's responsibility; the referee only rules on legality.
      def validate(player:, action:, game_state:, context: Protocol::Context.turn_action)
        messages = [
          { role: 'system', content: system_prompt },
          { role: 'user',   content: validation_prompt(player, action, game_state, context) }
        ]

        # Low temperature: we want consistent, rule-bound rulings
        chat_with_json_retry(messages, temperature: 0.1)
      end

      # Called by Runner#setup before the game loop begins.
      # Returns a hash matching the apply_changes structure: "flags", "custom", "player_states".
      # Use a higher temperature than validate — we want varied initial distributions.
      def compute_initial_state(setup_steps:, components:, players:)
        messages = [
          { role: 'system', content: system_prompt },
          { role: 'user',   content: setup_prompt(setup_steps, components, players) }
        ]

        chat_with_json_retry(messages, temperature: 0.7)
      end

      private

      def system_prompt
        <<~PROMPT
          You are the rules referee for #{@rules.dig('game', 'name')}.

          COMPLETE RULES:
          #{JSON.pretty_generate(@rules)}

          Your role is to determine whether a proposed action is legal given the current game
          state and rules. You do NOT compute state changes — the game engine handles that.

          If the action is valid, say so and briefly explain why.
          If the action is invalid, explain clearly so the player can correct their next attempt.

          You MUST respond with valid JSON only — no prose, no markdown fences:
          {"valid":true,"reason":"<explanation>"}
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
          #{JSON.pretty_generate(compact_game_state(game_state))}

          #{context_line}

          PROPOSED ACTION by #{player}:
          #{JSON.pretty_generate(action)}

          Is this action legal given the current game state and rules?
          Respond with JSON only: {"valid":true,"reason":"<explanation>"}
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

      # Sends messages to the referee model (thinking disabled) and retries up to
      # MAX_PARSE_RETRIES times if the model doesn't return parseable JSON.
      def chat_with_json_retry(messages, temperature:)
        working = messages.dup

        (MAX_PARSE_RETRIES + 1).times do |i|
          response = @client.chat(model: @model, messages: working, temperature: temperature, think: false, num_predict: -1, num_ctx: 32768)
          content  = response.dig('message', 'content')
          begin
            return parse_response(content)
          rescue RuntimeError, JSON::ParserError => e
            raise e if i == MAX_PARSE_RETRIES

            excerpt = content.length > 500 ? "#{content[0, 300]}...[truncated]" : content
            working << { role: 'assistant', content: excerpt }

            # Distinguish truncation (long content that cut off mid-JSON) from malformed output.
            # Truncated responses need a brevity nudge; malformed ones need a format reminder.
            retry_msg = if e.is_a?(JSON::ParserError) && content.length > 400
                          'Your response was cut off before the JSON was complete. Respond with minimal JSON — use compact single-line values and omit optional fields like random_ops.'
                        else
                          'Your response was not valid JSON. Respond with a raw JSON object only — no prose, no markdown, no code fences.'
                        end
            working << { role: 'user', content: retry_msg }
          end
        end
      end

      # Strips verbose card fields (condition, effect) from game state before sending
      # to the referee. The referee already has full card text in its system prompt via
      # the rules JSON; duplicating it in every game state inflates the context window.
      def compact_game_state(obj)
        case obj
        when Array then obj.map { |v| compact_game_state(v) }
        when Hash
          if obj.key?('condition') || obj.key?('effect')
            obj.slice('name', 'element')
          else
            obj.transform_values { |v| compact_game_state(v) }
          end
        else obj
        end
      end

      def parse_response(content)
        # Strip qwen3-style thinking blocks before attempting extraction
        cleaned = content.gsub(/<think>.*?<\/think>/m, '').strip

        # Try markdown code fence (```json ... ``` or ``` ... ```)
        if (fenced = cleaned.match(/```(?:json)?\s*(\{.*?\})\s*```/m))
          return JSON.parse(fenced[1])
        end

        # Fall back to first top-level {...} block
        json_str = cleaned.match(/\{.*\}/m)&.to_s
        raise "No JSON found in referee response: #{content.inspect}" unless json_str

        JSON.parse(json_str)
      end
    end
  end
end
