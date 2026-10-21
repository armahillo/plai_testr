module PlaiTestr
  module Session
    module FrameQueue
      def frame_queue
        raise NotImplementedError, "#{self.class} must implement #frame_queue"
      end

      def schedule_frames
        raise NotImplementedError, "#{self.class} must implement #schedule_frames"
      end

      def halt_frames? = game_over?

      def intercept_frame(_frame) = false

      private

      def frame = frame_queue.last

      def frame_for(type, player = nil, **data)
        { 'type' => type, 'player' => player }.merge(data.transform_keys(&:to_s))
      end

      def resolve_frame(params)
        current = frame_queue.pop
        send("on_#{current['type']}", current, params)
        advance_frames
      end

      def advance_frames
        loop do
          return if halt_frames?

          schedule_frames if frame_queue.empty?
          current = frame

          if current['auto']
            frame_queue.pop
            send("on_#{current['type']}", current)
          elsif !intercept_frame(current)
            return
          end
        end
      end
    end
  end
end
