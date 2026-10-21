module PlaiTestr
  module Reporter
    class ThinkLog
      HEADER = /^\[(\S+)\] model=(\S+)(.*)$/

      def self.load(path)
        new(File.exist?(path) ? File.read(path) : '')
      end

      attr_reader :calls

      def initialize(text)
        @calls = text.scan(HEADER).map do |time, model, stats|
          stats.scan(/(\w+)=([\d.]+)/).to_h { |key, value| [key, value.to_f] }.merge('time' => Time.parse(time), 'model' => model)
        end
      end

      def values(key) = @calls.filter_map { |call| call[key] }

      def average(key)
        list = values(key)
        list.empty? ? nil : list.sum / list.length
      end

      def minutes
        return nil if @calls.length < 2

        (@calls.last['time'] - @calls.first['time']) / 60.0
      end
    end
  end
end
