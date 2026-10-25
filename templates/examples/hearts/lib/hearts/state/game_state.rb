module Hearts
  module State
    class GameState < PlaiTestr::State::GameState
      def step   = @data['step']
      def active = @data['active']
      def trick  = @data['trick'] ||= []
      def taken  = @data['taken'] ||= {}

      private

      def data_for(observer)
        super.except('passes').merge('passed' => @data.fetch('passes', {}).keys)
      end
    end
  end
end
