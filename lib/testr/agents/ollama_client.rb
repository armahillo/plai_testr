module Testr
  module Agents
    class OllamaClient
      DEFAULT_HOST = 'localhost'
      DEFAULT_PORT = 11434
      READ_TIMEOUT = 300 # LLMs can be slow; 5 min ceiling per call

      def initialize(host: DEFAULT_HOST, port: DEFAULT_PORT)
        @host = host
        @port = port
      end

      def chat(model:, messages:, temperature: 0.7)
        post('/api/chat', {
          model: model,
          messages: messages,
          stream: false,
          options: { temperature: temperature }
        })
      end

      private

      def post(path, payload)
        http = Net::HTTP.new(@host, @port)
        http.read_timeout = READ_TIMEOUT

        request = Net::HTTP::Post.new(path, 'Content-Type' => 'application/json')
        request.body = JSON.generate(payload)

        response = http.request(request)
        raise "Ollama API error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end
    end
  end
end
