module PlaiTestr
  module Agents
    class RefereeAgent
      MAX_PARSE_RETRIES = 2
      TEMPERATURE       = 0.1

      RULING_SCHEMA = {
        'type'       => 'object',
        'properties' => {
          'met' => { 'type' => 'boolean' },
          'why' => { 'type' => 'string' }
        },
        'required' => %w[met why]
      }.freeze

      def initialize(model:, client:, game_name:, settings: PlaiTestr.config.model_settings)
        @model     = model
        @client    = client
        @game_name = game_name
        @options   = { temperature: TEMPERATURE, think: true, num_ctx: settings[:context_size], num_predict: settings[:referee_budget] }
      end

      def ruling(question:, facts:)
        messages = [
          { role: 'system', content: system_prompt },
          { role: 'user',   content: "QUESTION: #{question}\n\nFACTS:\n#{facts}\n\nReply with JSON only: {\"met\": true|false, \"why\": \"<1 sentence>\"}" }
        ]

        (MAX_PARSE_RETRIES + 1).times do
          response = @client.chat(model: @model, messages: messages, format: RULING_SCHEMA, **@options)
          parsed   = parse(response.dig('message', 'content').to_s)
          return { 'met' => parsed['met'], 'why' => parsed['why'].to_s, 'fallback' => false } if parsed && [true, false].include?(parsed['met'])
        end

        { 'met' => false, 'why' => 'fallback: no valid ruling after retries', 'fallback' => true }
      end

      private

      def system_prompt
        <<~PROMPT
          You are the rules referee for #{@game_name}.
          You answer ONE yes/no question about whether a rule or card condition is met.
          Use only the FACTS given. Do not assume anything that is not stated.
        PROMPT
      end

      def parse(content)
        json = content.gsub(/<think>.*?<\/think>/m, '')[/\{.*\}/m]
        json && JSON.parse(json)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
