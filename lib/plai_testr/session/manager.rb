module PlaiTestr
  module Session
    class Manager
      attr_reader :session_id

      def initialize(session_id: nil, base_dir: PlaiTestr.sessions_dir, persist: true)
        # A timestamp: readable and sortable. A second session started within the same second
        # gets a counter suffix (-2, -3, …) so ids stay unique.
        @base_dir   = base_dir
        @session_id = (session_id || timestamp_id).to_s
        FileUtils.mkdir_p(session_dir) if persist
      end

      def save_checkpoint(game_state, turn_log, metadata = {})
        data = {
          'session_id'    => @session_id,
          'saved_at'      => Time.now.iso8601,
          'status'        => metadata['status'] || 'in_progress',
          'game'          => metadata['game'],
          'rules_version' => metadata['rules_version'],
          'fingerprint'   => metadata['fingerprint'],
          'game_state'    => game_state.serialize,
          'turn_log'      => turn_log
        }

        temp = "#{checkpoint_path}.tmp"
        File.open(temp, 'w') do |file|
          file.write(JSON.pretty_generate(data))
          file.fsync
        end
        File.rename(temp, checkpoint_path)
      end

      def load_checkpoint
        JSON.parse(File.read(checkpoint_path))
      rescue Errno::ENOENT
        raise SessionError, "No saved session #{@session_id} in #{@base_dir}"
      rescue JSON::ParserError => e
        raise SessionError, "Session #{@session_id} cannot be resumed: #{checkpoint_path} is unreadable (#{e.message.lines.first.strip})"
      end

      def append_transcript_entry(entry)
        File.open(transcript_path, 'a') { |f| f.puts(JSON.generate(entry)) }
      end

      def timestamp_id
        stamp = Time.now.strftime('%Y%m%d-%H%M%S')
        id    = stamp
        count = 1
        id    = "#{stamp}-#{count += 1}" while Dir.exist?(File.join(@base_dir, id))
        id
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

      def self.list(base_dir: PlaiTestr.sessions_dir)
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
