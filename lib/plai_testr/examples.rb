require 'yaml'

module PlaiTestr
  module Examples
    DIR     = File.expand_path('../../templates/examples', __dir__)
    STAMP   = '.plai_testr.yml'
    SKIPPED = %w[sessions reports].freeze

    def self.names = Dir.children(DIR).sort

    def self.checksum(dir)
      files  = Dir.glob('**/*', base: dir).reject { |path| SKIPPED.include?(path.split('/').first) }.select { |path| File.file?(File.join(dir, path)) }.sort
      digest = Digest::SHA256.new
      files.each { |path| digest << path << "\0" << File.binread(File.join(dir, path)) << "\0" }
      digest.hexdigest
    end

    def self.template_checksum(name) = checksum(File.join(DIR, name))

    def self.stamp(game_dir, name)
      File.write(File.join(game_dir, STAMP), <<~YAML)
        # Written by plai_testr when it copied this example game. A gem update replaces the game
        # only while its files still match this checksum; once edited, the new version goes alongside.
        #{YAML.dump('example' => name, 'version' => VERSION, 'checksum' => template_checksum(name)).delete_prefix("---\n").chomp}
      YAML
    end

    def self.stamp_for(game_dir) = YAML.safe_load_file(File.join(game_dir, STAMP))

    def self.replaceable?(game_dir) = stamp_for(game_dir)['checksum'] == checksum(game_dir)

    def self.current?(game_dir)
      stamp = stamp_for(game_dir)
      checksum(game_dir) == template_checksum(stamp['example'])
    end
  end
end
