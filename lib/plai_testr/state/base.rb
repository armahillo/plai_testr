module PlaiTestr
  module State
    class Base
      def serialize
        raise NotImplementedError, "#{self.class} must implement #serialize"
      end

      def serialize_for(observer)
        raise NotImplementedError, "#{self.class} must implement #serialize_for"
      end
    end
  end
end
