$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'testr'

PLAYER_MODEL  = ENV.fetch('TESTR_PLAYER_MODEL',  'llama3.2:3b')
REFEREE_MODEL = ENV.fetch('TESTR_REFEREE_MODEL', 'qwen3:8b')
OLLAMA_HOST   = ENV.fetch('TESTR_OLLAMA_HOST',   'localhost')
OLLAMA_PORT   = ENV.fetch('TESTR_OLLAMA_PORT',   '11434').to_i

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)

namespace :check do
  desc 'Verify Ollama is reachable and required models are available'
  task :system do
    errors = []

    # --- Ollama reachability ---
    print "Ollama at #{OLLAMA_HOST}:#{OLLAMA_PORT} ... "
    tags_response = begin
      http = Net::HTTP.new(OLLAMA_HOST, OLLAMA_PORT)
      http.open_timeout = 5
      http.read_timeout = 5
      response = http.get('/api/tags')
      raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    rescue => e
      errors << "Cannot reach Ollama: #{e.message}"
      puts "FAIL (#{e.message})"
      nil
    end
    puts "OK" if tags_response

    # --- Model availability ---
    if tags_response
      available = Array(tags_response['models']).map { |m| m['name'] }

      [PLAYER_MODEL, REFEREE_MODEL].uniq.each do |model|
        print "Model #{model} ... "
        # Ollama model names may include tags like "llama3.2:3b" or just "llama3.2"
        found = available.any? { |a| a == model || a.start_with?("#{model}:") || a == "#{model}:latest" }
        if found
          puts "OK"
        else
          errors << "Model '#{model}' is not pulled. Run: ollama pull #{model}"
          puts "MISSING"
        end
      end
    end

    # --- Inference smoke test ---
    if errors.empty?
      client = Testr::Agents::OllamaClient.new(host: OLLAMA_HOST, port: OLLAMA_PORT)

      [
        { label: "Player model (#{PLAYER_MODEL})",   model: PLAYER_MODEL },
        { label: "Referee model (#{REFEREE_MODEL})", model: REFEREE_MODEL }
      ].uniq { |e| e[:model] }.each do |entry|
        print "Inference #{entry[:label]} ... "
        begin
          response = client.chat(
            model:    entry[:model],
            messages: [{ role: 'user', content: 'Reply with the single word: OK' }],
            temperature: 0.0
          )
          content = response.dig('message', 'content').to_s.strip
          puts "OK (response: #{content.slice(0, 60).inspect})"
        rescue => e
          errors << "Inference failed for #{entry[:model]}: #{e.message}"
          puts "FAIL (#{e.message})"
        end
      end
    else
      puts "\nSkipping inference test — fix connectivity issues above first."
    end

    # --- Summary ---
    puts
    if errors.empty?
      puts "All checks passed. TESTR is ready."
    else
      puts "#{errors.length} issue(s) found:"
      errors.each { |e| puts "  - #{e}" }
      exit 1
    end
  end
end

desc 'Run system check (alias for check:system)'
task check: 'check:system'
