module PlaiTestr
  # Keeps <app>/.plai_testr/gem pointing at the installed gem, so an app's CLAUDE.md can
  # `@`-import the guide (docs/AGENTS.md) and agents can open the gem's README, docs and
  # examples by a stable path that follows gem upgrades. Refreshed by `new`, every CLI
  # command and the app's spec_helper; copied instead where symlinks are unavailable.
  module Guide
    ROOT   = File.expand_path('../..', __dir__)
    LINK   = File.join('.plai_testr', 'gem')
    GUIDE  = File.join(LINK, 'docs', 'AGENTS.md')
    COPIED = %w[README.md CHANGELOG.md docs templates].freeze

    def self.link(app_root = File.dirname(PlaiTestr.games_dir))
      path = File.join(app_root, LINK)
      return path if File.symlink?(path) && File.readlink(path) == ROOT

      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.rm_rf(path)
      begin
        File.symlink(ROOT, path)
      rescue NotImplementedError, SystemCallError
        FileUtils.mkdir_p(path)
        COPIED.each { |entry| FileUtils.cp_r(File.join(ROOT, entry), path) }
      end
      path
    end
  end
end
