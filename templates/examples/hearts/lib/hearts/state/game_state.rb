module Hearts
  module State
    class GameState < PlaiTester::State::GameState
      def step   = @custom['step']
      def active = @custom['active']
      def trick  = @custom['trick'] ||= []
      def taken  = @custom['taken'] ||= {}

      private

      def custom_for(observer)
        @custom.except('passes', 'log').merge(
          'passed' => @custom.fetch('passes', {}).keys,
          'log'    => PlaiTester::EventLog.new(@custom.fetch('log', [])).visible_to(observer)
        )
      end
    end
  end
end
