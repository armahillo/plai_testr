module PlaiTestr
  module Reporter
    module Duration
      def self.format(seconds)
        seconds = seconds.round
        return "#{seconds / 3600}h #{(seconds % 3600 / 60).to_s.rjust(2, '0')}m" if seconds >= 3600

        "#{seconds / 60}m #{(seconds % 60).to_s.rjust(2, '0')}s"
      end
    end
  end
end
