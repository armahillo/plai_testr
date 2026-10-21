require 'yaml'

module PlaiTestr
  class Personas
    WILDCARD = '*'
    ALL      = 'all'

    def self.load(dir)
      personas_file = read(File.join(dir, 'personas.yml'))
      bots_file     = read(File.join(dir, 'bots.yml'))

      new(basic_strategy: section(personas_file, 'basic_strategy'), personas: section(personas_file, 'personas'),
          bot_strategy: section(bots_file, 'bot_strategy'), bots: section(bots_file, 'bots'))
    end

    def self.read(path)
      return {} unless File.exist?(path)

      content = YAML.safe_load_file(path, aliases: true) || {}
      raise PersonaError, "#{path}: expected keys at the top level, got #{content.class}" unless content.is_a?(Hash)

      content.merge('_path' => path)
    rescue Psych::SyntaxError => e
      raise PersonaError, "#{path}: #{e.message}"
    end

    def self.section(file, key)
      value = file[key] || {}
      raise PersonaError, "#{file['_path']}: '#{key}' must be a set of key: value entries, got #{value.class}" unless value.is_a?(Hash)

      value
    end

    attr_reader :basic_strategy, :bot_strategy

    def initialize(basic_strategy: {}, personas: {}, bot_strategy: {}, bots: {})
      @basic_strategy = basic_strategy
      @personas       = personas
      @bot_strategy   = bot_strategy
      @bots           = bots

      @personas.each do |key, persona|
        raise PersonaError, "personas.yml: persona '#{key}' must be a set of key: value entries" unless persona.is_a?(Hash)
      end
      orphans = @bots.keys - keys
      raise PersonaError, "bots.yml: bots #{orphans.join(', ')} match no persona in personas.yml (personas: #{keys.join(', ')})" if orphans.any?
    end

    def keys = @personas.keys

    def any? = @personas.any?

    def name(key) = key.split('_').map(&:capitalize).join(' ')

    def strategy(key) = @personas.fetch(key).values

    def bot(key) = @bots.fetch(key, @bot_strategy)

    def lint
      @personas.filter_map do |key, persona|
        missing = @basic_strategy.keys - persona.keys
        "personas.yml: persona '#{key}' is missing basic_strategy #{missing.join(', ')} (add <<: *basics?)" if missing.any?
      end
    end

    def check_request(request, players:, all: false)
      request = Array(request)
      return request if request.empty?
      raise PersonaError, 'This game defines no personas (add data/personas.yml)' unless any?
      return request if all && request == [ALL]
      raise PersonaError, "#{request.length} personas given for #{players} players" if request.length > players

      unknown = request - keys - [WILDCARD]
      raise PersonaError, "Unknown persona #{unknown.first.inspect} (choose from #{keys.join(', ')}, or #{WILDCARD})" if unknown.any?

      request
    end

    def assign(players, request, rng)
      request = Array(request)
      spare   = keys - request
      spare   = keys if spare.empty?
      pool    = []

      players.each_with_index.to_h do |player, i|
        key = request[i]
        if key.nil? || key == WILDCARD
          pool = spare.shuffle(random: rng) if pool.empty?
          key  = pool.shift
        end
        [player, key]
      end
    end

    def pairings(players) = keys.permutation(players).to_a
  end
end
