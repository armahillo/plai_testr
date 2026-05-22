module PlaiTester
  module Compiler
    class RulesLoader
      def self.schema_path = File.join(PlaiTester.rules_dir, 'schema.json')
      REQUIRED_KEYS  = %w[game components setup turn_structure actions win_conditions].freeze

      def self.load(path)
        raise "Rules file not found: #{path}" unless File.exist?(path)

        rules = JSON.parse(File.read(path))

        errors = validate(rules)
        raise "Invalid rules file (#{path}):\n#{errors.map { |e| "  - #{e}" }.join("\n")}" unless errors.empty?

        rules['_source_file'] = File.expand_path(path)
        rules
      end

      def self.validate(rules)
        REQUIRED_KEYS.filter_map do |key|
          "Missing required top-level key: '#{key}'" unless rules.key?(key)
        end
      end
    end
  end
end
