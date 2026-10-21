module Hearts
  module Bot
    def bot_choice(player, moves, pick: nil)
      cards = moves.map { |m| hand(player).find { |c| c['uid'] == m[:action].values.first[:value] } }
      pick ? pass_policy(player, cards, pick.first) : play_policy(player, cards)
    end

    private

    def pass_policy(player, cards, count)
      ranked = cards.each_index.sort_by { |i| -danger(cards[i]) }
      return { 'choices' => ranked.first(count).map { |i| i + 1 }, 'rule' => 'pass_dangerous' } if bot_strategy_for(player)['pass_dangerous']

      { 'choices' => ranked.last(count).map { |i| i + 1 }, 'rule' => 'keep_dangerous' }
    end

    def play_policy(player, cards)
      if trick.empty? then choose(cards, cards.min_by { |c| [Hearts.points(c), c['rank']] }, 'lead_low')
      elsif cards.first['suit'] == led_suit then follow_policy(player, cards)
      else dump_policy(cards)
      end
    end

    def follow_policy(player, cards)
      high  = trick.select { |t| t['card']['suit'] == led_suit }.map { |t| t['card']['rank'] }.max
      under = cards.select { |c| c['rank'] < high }

      if under.any? then choose(cards, under.max_by { |c| c['rank'] }, 'duck')
      elsif last_to_play? && points_in(trick.map { |t| t['card'] }).zero? && bot_strategy_for(player)['win_clean_tricks']
        choose(cards, cards.reject { |c| c['name'] == QUEEN }.max_by { |c| c['rank'] } || cards.first, 'win_clean_trick')
      else choose(cards, cards.min_by { |c| c['rank'] }, 'play_low')
      end
    end

    def dump_policy(cards)
      worst = cards.max_by { |c| danger(c) }
      queen = worst['name'] == QUEEN
      choose(cards, worst, queen ? 'dump_queen' : 'dump_high', obvious: queen)
    end

    def danger(card)
      if card['name'] == QUEEN then 100
      elsif card['suit'] == 'spades' && card['rank'] > 12 then 50 + card['rank']
      elsif card['suit'] == 'hearts' then 20 + card['rank']
      else card['rank']
      end
    end

    def last_to_play? = trick.length == players.length - 1

    def choose(cards, card, rule, obvious: false) = { 'choice' => cards.index(card) + 1, 'rule' => rule, 'obvious' => obvious }
  end
end
