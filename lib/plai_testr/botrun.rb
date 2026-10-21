module PlaiTestr
  class Botrun
    attr_reader :planned

    def initialize(game:, players:, seeds:, personas: nil, out: nil)
      @game     = game
      @players  = players
      @seeds    = seeds
      @personas = personas
      @out      = out
      @planned  = seeds.length
    end

    def run
      catalog = @game.personas
      catalog.check_request(@personas, players: @players.length, all: true)
      pairings = all_pairings? ? catalog.pairings(@players.length) : []
      raise PersonaError, "--personas all needs at least #{@players.length} personas to pair up" if all_pairings? && pairings.empty?

      results = []
      with_signal_traps do
        @seeds.each_with_index do |seed, i|
          break if @stopping

          results << play(seed, all_pairings? ? pairings[i % pairings.length] : @personas)
          yield results.length if block_given?
        end
      end
      results
    end

    def stopped_early? = @stopping == true

    private

    def all_pairings? = @personas == [Personas::ALL]

    def play(seed, personas)
      game = @game.runner_class.new(game: @game, players: @players, seed: seed, personas: personas, mode: 'bot', persist: false,
                                    out: @out || StringIO.new, echo_warnings: false)
      game.play_out
      game.botrun_result
    rescue StandardError => e
      { 'seed' => seed, 'personas_requested' => personas, 'error' => "#{e.class}: #{e.message}" }
    end

    def with_signal_traps
      previous = %w[INT TERM].to_h do |signal|
        [signal, trap(signal) do
          exit!(130) if @stopping
          @stopping = true
          $stderr.puts "\n\nInterrupted — finishing this game, then reporting. Press Ctrl+C again to quit immediately."
        end]
      end
      yield
    ensure
      previous&.each { |signal, handler| trap(signal, handler || 'DEFAULT') }
    end
  end
end
