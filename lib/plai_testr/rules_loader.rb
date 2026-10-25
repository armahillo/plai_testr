module PlaiTestr
  class RulesLoader
    COMPONENT_FILES = '*.{yml,yaml,json,csv}'

    def self.load(path)
      key = [File.expand_path(path), File.mtime(path), *component_files(path).map { |file| [file, File.mtime(file)] }]
      (@cache ||= {})[key] ||= parse(path)
    rescue Errno::ENOENT
      raise RulesError, "Rules file not found: #{path}"
    end

    def self.parse(path)
      rules = JSON.parse(File.read(path))
      rules['components'] = rules.fetch('components', []) + component_files(path).map { |file| component(file) }
      errors = validate(rules)
      raise RulesError, "Invalid rules file #{path}:\n#{errors.map { |e| "  - #{e}" }.join("\n")}" unless errors.empty?

      rules
    rescue Errno::ENOENT
      raise RulesError, "Rules file not found: #{path}"
    rescue JSON::ParserError => e
      raise RulesError, "#{path} is not valid JSON: #{e.message}"
    end

    def self.component_files(path) = Dir.glob(File.join(File.dirname(path), 'components', COMPONENT_FILES)).sort

    def self.component(file)
      values = case File.extname(file)
               when '.csv'  then CSV.read(file, headers: true, converters: :numeric, header_converters: ->(h) { h.to_s.strip }, skip_blanks: true)
                                 .map { |row| row.to_h.compact }.reject(&:empty?)
               when '.json' then JSON.parse(File.read(file))
               else YAML.safe_load_file(file, aliases: true)
               end
      { 'name' => File.basename(file, '.*'), 'type' => 'card_deck', 'values' => values, 'file' => file }
    rescue JSON::ParserError, Psych::SyntaxError, CSV::MalformedCSVError => e
      raise RulesError, "#{file}: #{e.message}"
    end

    def self.validate(rules)
      game = rules['game']
      return ["'game' must be an object with a name and version"] unless game.is_a?(Hash)

      errors = %w[name version].filter_map { |key| "game.#{key} is required" if game[key].to_s.empty? }
      errors << player_count_error(game['player_count']) if game.key?('player_count')
      components = rules.fetch('components', [])
      components.group_by { |c| c['name'] }.each { |name, list| errors << "components: #{list.length} components are named #{name}" if list.length > 1 }
      components.select { |c| c['type'] == 'card_deck' }.each { |deck| errors.concat(deck_errors(deck)) }
      errors.compact
    end

    def self.deck_errors(deck)
      label  = deck['file'] || "components: #{deck['name']}"
      values = deck.fetch('values', [])
      return ["#{label}: must be a list of cards (each with its fields), got #{values.class}"] unless values.is_a?(Array)

      values.each.with_index(1).filter_map do |card, i|
        if !card.is_a?(Hash) then "#{label}: entry #{i} must have fields (like name: ...), got #{card.inspect}"
        elsif card.key?('copies') && !(card['copies'].is_a?(Integer) && card['copies'].positive?) then "#{label}: entry #{i} copies must be a whole number above 0"
        end
      end
    end

    def self.player_count_error(range)
      min, default, max = range.is_a?(Hash) ? range.values_at('min', 'default', 'max') : []
      return nil if [min, default, max].all?(Integer) && min <= default && default <= max

      'game.player_count needs whole numbers with min <= default <= max'
    end
  end
end
