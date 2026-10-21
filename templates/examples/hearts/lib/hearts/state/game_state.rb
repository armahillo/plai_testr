module Hearts
  module State
    class GameState < PlaiTestr::State::GameState
      def step   = @data['step']
      def active = @data['active']
      def trick  = @data['trick'] ||= []
      def taken  = @data['taken'] ||= {}

      private

      def data_for(observer)
        @data.except('passes', 'log').merge(
          'passed' => @data.fetch('passes', {}).keys,
          'log'    => PlaiTestr::EventLog.new(@data.fetch('log', [])).visible_to(observer)
        )
      end
    end
  end
end
