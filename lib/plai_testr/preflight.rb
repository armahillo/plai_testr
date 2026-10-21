module PlaiTestr
  class Preflight
    LINT_SEEDS    = (1..5).to_a.freeze
    PROMPT_LIMIT  = 0.9
    START_COMMAND = { /darwin/ => 'brew services start ollama', /linux/ => 'sudo systemctl start ollama' }.freeze

    def initialize(game:, players:, models:, personas: nil, out: $stdout)
      @game     = game
      @players  = players
      @models   = models
      @personas = personas
      @out      = out
      @client   = Agents::OllamaClient.new(out: out)
    end

    def run(seed)
      ollama!
      prompt_size!(seed)
      lint!
    end

    def ollama!
      available = begin
        @client.model_names
      rescue ModelError => e
        start = START_COMMAND.find { |platform, _| RUBY_PLATFORM.match?(platform) }&.last || 'ollama serve'
        raise ModelError, "#{e.message}\nStart it with: #{start}"
      end
      @out.puts "  Ollama at #{PlaiTestr.config.ollama_host}:#{PlaiTestr.config.ollama_port}: reachable"

      wanted.each do |model|
        @client.pull(model) unless available.include?(model) || available.include?("#{model}:latest")
        @client.chat(model: model, messages: [{ role: 'user', content: 'Reply with OK.' }], think: false, num_predict: 1, keep_alive: '30m')
        @out.puts "  #{model}: ready"
      end
    end

    def prompt_size!(seed)
      probe    = runner(seed)
      probe.setup
      player   = probe.next_player
      settings, = ModelSettings.resolve(@game.model_settings, model_max: @client.context_length(@models[:player]))
      agent    = Agents::PlayerAgent.new(name: player, model: @models[:player], client: @client, game_name: @game.rules.dig('game', 'name'),
                                         settings: settings, think: @models[:think] == true)
      used     = agent.prompt_tokens(rules_text: probe.rules_text_for(player), view_text: probe.view_text_for(player),
                                     labels: probe.menu(player).map { |m| m[:label] }, recent: probe.recent_events_for(player),
                                     prompt_note: probe.prompt_note_for(player), persona: probe.persona_for(player))
      limit    = agent.context_size

      if used > limit * PROMPT_LIMIT
        raise ModelError, "The first prompt needs #{used} tokens, over #{(PROMPT_LIMIT * 100).round}% of the #{limit}-token context. " \
                          "Raise context_size#{' (long_context_size with --think)' if @models[:think]} in config/plai_testr.rb or in the game's registration."
      end
      @out.puts "  First prompt: #{used} of #{limit} tokens"
    end

    def lint!
      LINT_SEEDS.each { |seed| runner(seed).play_out }
      @out.puts "  Lint: #{LINT_SEEDS.length} bot games played without errors"
    end

    private

    def wanted = @models.values_at(:player, :referee).compact.uniq

    def runner(seed)
      @game.runner_class.new(game: @game, players: @players, seed: seed, personas: @personas, mode: 'bot', persist: false, out: StringIO.new, echo_warnings: false)
    end
  end
end
