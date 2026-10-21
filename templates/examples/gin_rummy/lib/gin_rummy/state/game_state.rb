module GinRummy
  module State
    class GameState < PlaiTestr::State::GameState
      def step         = @data['step']
      def active       = @data['active']
      def stock        = @data['stock'] ||= []
      def discard_pile = @data['discard'] ||= []

      private

      def data_for(observer)
        @data.except('stock', 'log').merge(
          'stock_size' => stock.length,
          'log'        => PlaiTestr::EventLog.new(@data.fetch('log', [])).visible_to(observer)
        )
      end
    end
  end
end
