module GinRummy
  module Bot
    def bot_choice(player, moves, pick: nil)
      params = moves.map { |m| m[:action].values.first }
      step == 'draw' ? draw_policy(params) : discard_policy(player, params)
    end

    private

    def draw_policy(params)
      params[1][:deadwood] < params[0][:deadwood] ? choose(1, 'take_useful_discard') : choose(0, 'draw_stock')
    end

    def discard_policy(player, params)
      options = params.each_index
      gin     = options.find { |i| params[i][:knock] && params[i][:deadwood].zero? }
      knock   = options.select { |i| params[i][:knock] }.min_by { |i| params[i][:deadwood] }
      shed    = options.reject { |i| params[i][:knock] }.min_by do |i|
        [params[i][:deadwood], -Melds.value(hand(player).find { |c| c['uid'] == params[i][:value] })]
      end

      if gin then choose(gin, 'gin', obvious: true)
      elsif knock && knock_now?(player, params[knock][:deadwood]) then choose(knock, 'knock')
      else choose(shed, 'shed_deadwood')
      end
    end

    def knock_now?(player, deadwood)
      deadwood <= bot_strategy_for(player)['knock_at'] || stock.length <= LATE_STOCK
    end

    def choose(index, rule, obvious: false) = { 'choice' => index + 1, 'rule' => rule, 'obvious' => obvious }
  end
end
