module GinRummy
  module State
    class GameState < PlaiTester::State::GameState
      def step         = @custom['step']
      def active       = @custom['active']
      def stock        = @custom['stock'] ||= []
      def discard_pile = @custom['discard'] ||= []

      private

      def custom_for(observer)
        @custom.except('stock', 'log').merge(
          'stock_size' => stock.length,
          'log'        => PlaiTester::EventLog.new(@custom.fetch('log', [])).visible_to(observer)
        )
      end
    end
  end
end
