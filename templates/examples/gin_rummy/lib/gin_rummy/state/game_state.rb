module GinRummy
  module State
    class GameState < PlaiTestr::State::GameState
      def step         = @data['step']
      def active       = @data['active']
      def stock        = @data['stock'] ||= []
      def discard_pile = @data['discard'] ||= []

      private

      def data_for(observer)
        super.except('stock').merge('stock_size' => stock.length)
      end
    end
  end
end
