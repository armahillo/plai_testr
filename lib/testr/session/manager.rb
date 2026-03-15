module Testr
  module Session
    class Manager
      attr_reader :session_id

      def initialize(session_id: nil, base_dir: Testr::SESSIONS_DIR)
        @session_id = session_id || SecureRandom.hex(8)
        @base_dir   = base_dir
        FileUtils.mkdir_p(session_dir)
      end

      def save_checkpoint(game_state, turn_log, metadata = {})
        data = {
          'session_id'    => @session_id,
          'saved_at'      => Time.now.iso8601,
          'status'        => metadata['status'] || 'in_progress',
          'game'          => metadata['game'],
          'rules_file'    => metadata['rules_file'],
          'rules_version' => metadata['rules_version'],
          'game_state'    => game_state.to_h,
          'turn_log'      => turn_log
        }

        File.write(checkpoint_path, JSON.pretty_generate(data))
      end

      def load_checkpoint
        raise "No checkpoint found for session #{@session_id}" unless File.exist?(checkpoint_path)

        JSON.parse(File.read(checkpoint_path))
      end

      def append_transcript_entry(entry)
        File.open(transcript_path, 'a') { |f| f.puts(JSON.generate(entry)) }
      end

      def session_dir
        File.join(@base_dir, @session_id)
      end

      def checkpoint_path
        File.join(session_dir, 'state.json')
      end

      def transcript_path
        File.join(session_dir, 'transcript.jsonl')
      end

      def self.list(base_dir: Testr::SESSIONS_DIR)
        return [] unless Dir.exist?(base_dir)

        Dir.glob(File.join(base_dir, '*', 'state.json')).filter_map do |path|
          JSON.parse(File.read(path)).slice('session_id', 'game', 'saved_at', 'status')
        rescue JSON::ParserError
          nil
        end.sort_by { |s| s['saved_at'] }.reverse
      end
    end
  end
end
