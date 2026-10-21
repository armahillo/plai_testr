module PlaiTestr
  module Agents
    class OllamaClient
      READ_TIMEOUT       = 300
      MAX_RETRIES        = 3
      CONTEXT_WARN_RATIO = 0.9
      SPINNER_FRAMES     = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze
      UNREACHABLE        = [Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::EADDRNOTAVAIL, SocketError, Net::OpenTimeout].freeze

      def initialize(host: PlaiTestr.config.ollama_host, port: PlaiTestr.config.ollama_port, think_log: nil, out: $stdout, verbose: false)
        @host        = host
        @port        = port
        @think_log   = think_log
        @out         = out
        @verbose     = verbose
        @frame_index = 0
        @tty         = out.tty?
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
        used     = response['prompt_eval_count']
        return response unless used && num_ctx && used >= num_ctx * CONTEXT_WARN_RATIO

        File.open(@think_log, 'a') { |f| f.puts "[WARNING] context nearly full: #{used}/#{num_ctx} prompt tokens (model=#{model})\n---\n\n" } if @think_log
        response.merge('context_full' => true)
      end

      def model_names
        request(Net::HTTP::Get.new('/api/tags')) { |response| JSON.parse(response.body) }.fetch('models', []).map { |m| m['name'] }
      end

      def context_length(model)
        info = request(json_post('/api/show', model: model)) { |response| JSON.parse(response.body) }.fetch('model_info', {})
        info["#{info['general.architecture']}.context_length"]
      end

      def pull(model)
        request(json_post('/api/pull', model: model, stream: true), read_timeout: nil) do |response|
          each_line(response) do |data|
            raise ModelError, "Pulling #{model} failed: #{data['error']}" if data['error']

            @out.print "\r  Pulling #{model}: #{data['status']}#{" #{(100.0 * data['completed'] / data['total']).round}%" if data['total'].to_i.positive? && data['completed']}\e[K"
          end
        end
        @out.puts
      end

      private

      def json_post(path, payload)
        Net::HTTP::Post.new(path, 'Content-Type' => 'application/json').tap { |r| r.body = JSON.generate(payload) }
      end

      def request(req, read_timeout: 10, &block)
        http              = Net::HTTP.new(@host, @port)
        http.open_timeout = 5
        http.read_timeout = read_timeout
        http.request(req) do |response|
          raise ModelError, "Ollama API error #{response.code} for #{req.path}: #{response.read_body}" unless response.is_a?(Net::HTTPSuccess)

          return block.call(response)
        end
      rescue *UNREACHABLE => e
        raise ModelError, "Cannot reach Ollama at #{@host}:#{@port} (#{e.class}: #{e.message})"
      end

      def each_line(response)
        buffer = +''
        response.read_body do |chunk|
          buffer << chunk
          while (newline = buffer.index("\n"))
            data = parse_line(buffer.slice!(0, newline + 1))
            yield data if data
          end
        end
        data = parse_line(buffer)
        yield data if data
      end

      def parse_line(line)
        JSON.parse(line) unless line.strip.empty?
      rescue JSON::ParserError
        nil
      end

      def post(path, payload)
        attempts = 0
        begin
          attempts += 1
          post_once(path, payload)
        rescue Net::ReadTimeout, Errno::ECONNRESET, EOFError => e
          clear_spinner
          raise ModelError, "Ollama stopped responding (#{e.class}) after #{attempts} tries" if attempts >= MAX_RETRIES

          wait = 2**attempts
          warn "  [connection error: #{e.class} — retrying in #{wait}s]"
          sleep wait
          retry
        end
      end

      def post_once(path, payload)
        content     = +''
        thinking    = +''
        final_chunk = nil

        request(json_post(path, payload), read_timeout: READ_TIMEOUT) do |response|
          each_line(response) do |data|
            piece = data.dig('message', 'content').to_s
            content  << piece
            thinking << data.dig('message', 'thinking').to_s
            final_chunk = data if data['done']
            @verbose ? @out.print(piece) : advance_spinner
          end
        end

        clear_spinner
        raise ModelError, 'Ollama API error: stream ended without a done chunk' unless final_chunk

        @out.puts "\n  [#{format_stats(final_chunk).strip}]" if @verbose
        write_think_log(payload[:model], thinking.empty? ? content : "<think>\n#{thinking.strip}\n</think>\n#{content}", final_chunk)
        final_chunk.merge('message' => { 'role' => 'assistant', 'content' => content })
      end

      def write_think_log(model, content, stats = {})
        return unless @think_log

        File.open(@think_log, 'a') do |f|
          f.puts "[#{Time.now.utc.iso8601}] model=#{model}#{format_stats(stats)}"
          f.puts content
          f.puts '---'
          f.puts
        end
      end

      def format_stats(stats)
        nanos = 1_000_000_000.0
        rate  = ->(count, duration) { count && duration.to_i.positive? ? (count / (duration / nanos)).round(1) : nil }
        {
          'prompt_tokens' => stats['prompt_eval_count'],
          'prompt_tps'    => rate.call(stats['prompt_eval_count'], stats['prompt_eval_duration']),
          'eval_tokens'   => stats['eval_count'],
          'eval_tps'      => rate.call(stats['eval_count'], stats['eval_duration']),
          'load_s'        => stats['load_duration'] && (stats['load_duration'] / nanos).round(2),
          'total_s'       => stats['total_duration'] && (stats['total_duration'] / nanos).round(2)
        }.filter_map { |key, value| " #{key}=#{value}" unless value.nil? }.join
      end

      def advance_spinner
        return unless @tty

        @out.print "\r  #{SPINNER_FRAMES[@frame_index % SPINNER_FRAMES.length]}"
        @out.flush
        @frame_index += 1
      end

      def clear_spinner
        return unless @tty

        @out.print "\r   \r"
        @out.flush
      end
    end
  end
end
