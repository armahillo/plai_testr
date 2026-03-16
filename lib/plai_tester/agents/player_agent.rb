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

      # Called when another player has taken an action that may trigger a reaction.
      # The agent may respond with a reaction action or a no_op.
      def react_to(acting_player, triggering_action, game_state, available_reactions)
        messages = [
          { role: 'system', content: system_prompt },
          { role: 'user',   content: reaction_prompt(acting_player, triggering_action, game_state, available_reactions) }
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
        # Each turn entry now has an 'actions' array; summarize non-end_turn actions per turn
        recent = history.last(3).map do |t|
          played = t['actions'].reject { |a| a['action'] == 'end_turn' }.map { |a| a['action'] }.join(', ')
          "Turn #{t['turn']}: #{t['player']} played #{played}"
        end.join("\n")

        <<~PROMPT
          CURRENT GAME STATE:
          #{JSON.pretty_generate(game_state)}

          YOUR AVAILABLE ACTIONS THIS TURN:
          #{available_actions.map { |a| "- #{a}" }.join("\n")}

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

      def parse_response(content)
        json_str = content.match(/\{.*\}/m)&.to_s
        raise "No JSON found in player response: #{content.inspect}" unless json_str

        JSON.parse(json_str)
      end
    end
  end
end
