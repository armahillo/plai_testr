module PlaiTester
  class Botrun
    def initialize(runner_class:, game_state_class:, rules:, players:, seeds:, personas: nil)
      @runner_class     = runner_class
      @game_state_class = game_state_class
      @rules            = rules
      @players          = players
      @seeds            = seeds
      @personas         = personas
    end

    def run
      raise ArgumentError, 'This game defines no personas, so --personas all has nothing to cycle' if all_pairings? && pairings.empty?

      runner(@seeds.first, personas_for(0))
      @seeds.each_with_index.map do |seed, i|
        result = play(seed, personas_for(i))
        yield i + 1 if block_given?
        result
      end
    end

    private

    def runner(seed, personas)
      @runner_class.new(rules: @rules, players: @players, models: {}, game_state_class: @game_state_class,
                        seed: seed, personas: personas, mode: 'bot', persist: false)
    end

    def play(seed, personas)
      game     = runner(seed, personas)
      original = $stdout
      $stdout  = StringIO.new
      game.play_out
      game.botrun_result
    rescue StandardError => e
      { 'seed' => seed, 'personas_requested' => personas, 'error' => "#{e.class}: #{e.message}" }
    ensure
      $stdout = original
    end

    def all_pairings? = @personas == ['all']

    def personas_for(index) = all_pairings? ? pairings[index % pairings.length] : @personas

    def pairings
      @pairings ||= @runner_class.persona_names.permutation(@players.length).to_a
    end
  end
end
