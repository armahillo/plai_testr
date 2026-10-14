module PlaiTester
  module Agents
    class OllamaClient
      DEFAULT_HOST   = 'localhost'
      DEFAULT_PORT   = 11434
      READ_TIMEOUT   = 300
      MAX_RETRIES    = 3
      SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

      def initialize(host: DEFAULT_HOST, port: DEFAULT_PORT, think_log: nil)
        @host        = host
        @port        = port
        @think_log   = think_log
        @frame_index = 0
        @tty         = $stdout.tty?
      end

      # `think`, `format` and `keep_alive` are top-level request fields in Ollama's /api/chat;
      # only sampling/runtime settings belong in `options`. `format` may be "json" or a JSON schema.
      def chat(model:, messages:, temperature: 0.7, think: nil, num_predict: nil, num_ctx: nil, format: nil, keep_alive: nil)
        options = { temperature: temperature }
        options[:num_predict] = num_predict unless num_predict.nil?
        options[:num_ctx]     = num_ctx     unless num_ctx.nil?

        payload = { model: model, messages: messages, stream: true, options: options }
        payload[:think]      = think      unless think.nil?
        payload[:format]     = format     unless format.nil?
        payload[:keep_alive] = keep_alive unless keep_alive.nil?

        response = post('/api/chat', payload)
        warn_if_context_nearly_full(response, num_ctx)
        response
      end

      # Returns the names of locally pulled models, or raises if the server is unreachable.
      def model_names
        http              = Net::HTTP.new(@host, @port)
        http.open_timeout = 5
        http.read_timeout = 10
        response          = http.get('/api/tags')
        raise "Ollama API error #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body).fetch('models', []).map { |m| m['name'] }
      end

      private

      def post(path, payload)
        attempts = 0
        begin
          attempts += 1
          post_once(path, payload)
        rescue Net::ReadTimeout, Errno::ECONNRESET, EOFError => e
          clear_spinner
          raise e if attempts >= MAX_RETRIES
          wait = 2 ** attempts  # 2s, 4s
          $stderr.puts "  [connection error: #{e.class} — retrying in #{wait}s]" if @tty
          sleep wait
          retry
        end
      end

      def post_once(path, payload)
        http              = Net::HTTP.new(@host, @port)
        http.read_timeout = READ_TIMEOUT

        request           = Net::HTTP::Post.new(path, 'Content-Type' => 'application/json')
        request.body      = JSON.generate(payload)

        assembled_content = +''
        final_chunk       = nil

        http.request(request) do |response|
          unless response.is_a?(Net::HTTPSuccess)
            raise "Ollama API error #{response.code}: #{response.read_body}"
          end

          buffer = +''
          response.read_body do |chunk|
            buffer << chunk
            while (newline = buffer.index("\n"))
              line = buffer.slice!(0, newline + 1).chomp
              next if line.empty?

              begin
                data = JSON.parse(line)
              rescue JSON::ParserError
                next
              end

              assembled_content << data.dig('message', 'content').to_s
              final_chunk = data if data['done']
              advance_spinner
            end
          end

          # Process any final content not terminated by a newline
          unless buffer.strip.empty?
            begin
              data = JSON.parse(buffer.strip)
              assembled_content << data.dig('message', 'content').to_s
              final_chunk = data if data['done']
            rescue JSON::ParserError
              nil
            end
          end
        end

        clear_spinner
        raise 'Ollama API error: stream ended without a done chunk' unless final_chunk

        write_think_log(payload[:model], assembled_content, final_chunk['prompt_eval_count'])
        final_chunk.merge('message' => { 'role' => 'assistant', 'content' => assembled_content })
      end

      CONTEXT_WARN_RATIO = 0.9

      # Ollama silently truncates prompts that exceed num_ctx. prompt_eval_count tells us how
      # many prompt tokens were actually evaluated, so a value near the limit means truncation.
      def warn_if_context_nearly_full(response, num_ctx)
        used = response['prompt_eval_count']
        return unless used && num_ctx
        return if used < num_ctx * CONTEXT_WARN_RATIO

        message = "context nearly full: #{used}/#{num_ctx} prompt tokens (model=#{response['model']})"
        $stderr.puts "  [WARNING: #{message}]"
        File.open(@think_log, 'a') { |f| f.puts "[WARNING] #{message}\n---\n\n" } if @think_log
      end

      def write_think_log(model, content, prompt_tokens = nil)
        return unless @think_log

        File.open(@think_log, 'a') do |f|
          f.puts "[#{Time.now.utc.iso8601}] model=#{model}#{" prompt_tokens=#{prompt_tokens}" if prompt_tokens}"
          f.puts content
          f.puts '---'
          f.puts
        end
      end

      def advance_spinner
        return unless @tty

        print "\r  #{SPINNER_FRAMES[@frame_index % SPINNER_FRAMES.length]}"
        $stdout.flush
        @frame_index += 1
      end

      def clear_spinner
        return unless @tty

        print "\r   \r"
        $stdout.flush
      end
    end
  end
end
