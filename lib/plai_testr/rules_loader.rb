module PlaiTestr
  class RulesLoader
    def self.load(path)
      (@cache ||= {})[[File.expand_path(path), File.mtime(path)]] ||= parse(path)
    rescue Errno::ENOENT
      raise RulesError, "Rules file not found: #{path}"
    end

    def self.parse(path)
      rules  = JSON.parse(File.read(path))
      errors = validate(rules)
      raise RulesError, "Invalid rules file #{path}:\n#{errors.map { |e| "  - #{e}" }.join("\n")}" unless errors.empty?

      rules
    rescue Errno::ENOENT
      raise RulesError, "Rules file not found: #{path}"
    rescue JSON::ParserError => e
      raise RulesError, "#{path} is not valid JSON: #{e.message}"
    end

    def self.validate(rules)
      game = rules['game']
      return ["'game' must be an object with a name and version"] unless game.is_a?(Hash)

      errors = %w[name version].filter_map { |key| "game.#{key} is required" if game[key].to_s.empty? }
      errors << player_count_error(game['player_count']) if game.key?('player_count')
      rules.fetch('components', []).each do |component|
        errors << "components: #{component['name']} 'values' must be an array" if component['type'] == 'card_deck' && !component.fetch('values', []).is_a?(Array)
      end
      errors.compact
    end

    def self.player_count_error(range)
      min, default, max = range.is_a?(Hash) ? range.values_at('min', 'default', 'max') : []
      return nil if [min, default, max].all?(Integer) && min <= default && default <= max

      'game.player_count needs whole numbers with min <= default <= max'
    end
  end
end
