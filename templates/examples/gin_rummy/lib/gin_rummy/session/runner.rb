module GinRummy
  module Session
    class Runner < PlaiTestr::Session::Runner
      include Bot

      DEBRIEF_QUESTIONS = [
        'Which of your decisions mattered most, and why? Name the hand.',
        'When did you choose to knock (or not), and was it the right call?',
        'When did taking from the discard pile help or hurt you? Name the hand.',
        'Did your strategy work? Use GAME FACTS to say what helped it and what got in the way.'
      ].freeze

      def setup
        data.merge!('hand' => 0, 'log' => [])
        deal(players.last)
        out.puts "  Setup (seed #{@seed}): first to #{points_to_win} points; #{players.map { |p| display_name(p) }.join(' vs ')}."
      end

      def next_player = @game_state.active

      def legal_moves(player)
        case step
        when 'draw'    then draw_moves(player)
        when 'discard' then discard_moves(player)
        end
      end

      def apply_action_effects(player, action)
        case action
        in { draw: { source: } }              then draw(player, source)
        in { discard: { value:, knock: true } } then discard(player, value, knock: true)
        in { discard: { value: } }            then discard(player, value, knock: false)
        end
      end

      def view_text_for(player)
        best = Melds.best(hand(player))

        [
          "Hand #{data['hand']}. Scores (first to #{points_to_win}): #{players.map { |p| "#{whose(p, player)} #{pstate(p).score}" }.join(', ')}",
          "Your hand: #{list(hand(player))}",
          "Your best melds: #{melds_text(best)}; deadwood #{best.points}",
          "Discard pile: #{top ? "#{top['name']} on top (#{discard_pile.length} cards)" : 'empty'}. Stock: #{stock.length} cards. #{opponent(player)} holds #{hand(opponent(player)).length} cards.",
          '',
          instruction
        ].join("\n")
      end

      def turn_phase(_player) = "hand #{data['hand']} · #{step}"

      def debrief_questions(_player) = DEBRIEF_QUESTIONS

      def debrief_facts(_player)
        {
          'how_it_ended' => "#{@game_state.status['winner']} won (#{@game_state.status['end_reason'].to_s.tr('_', ' ')}) after #{data['hand']} hands",
          'hand_results' => data.fetch('results', {}),
          'players' => players.to_h { |p| [p, { 'final_score' => pstate(p).score, 'hands_won' => data.dig('hand_wins', p) || {} }] }
        }
      end

      private

      def draw_moves(player)
        now  = Melds.best(hand(player)).points
        with = hand(player).map { |c| Melds.best(hand(player) + [top] - [c]).points }.min

        [
          option('Draw the top card of the stock (face-down)', public: 'drew from the stock', draw: { source: 'stock', deadwood: now }),
          option("Take the #{top['name']} from the discard pile (best deadwood after your discard: #{with}; now: #{now})",
                 public: "took the #{top['name']} from the discard pile", draw: { source: 'discard', deadwood: with })
        ]
      end

      def discard_moves(player)
        hand(player).reject { |c| c['uid'] == data['taken'] }.flat_map do |card|
          deadwood = Melds.best(hand(player) - [card]).points
          params   = { value: card['uid'], deadwood: deadwood }

          [
            option("Discard #{card['name']} (deadwood after: #{deadwood})", public: "discarded #{card['name']}", discard: params),
            (knock_option(card, params) if deadwood <= knock_limit)
          ].compact
        end
      end

      def knock_option(card, params)
        gin = params[:deadwood].zero?
        option(gin ? "Discard #{card['name']} and go gin" : "Discard #{card['name']} and knock with #{params[:deadwood]} deadwood",
               public: "discarded #{card['name']} and #{gin ? 'went gin' : 'knocked'}", discard: params.merge(knock: true))
      end

      def deal(dealer)
        deck = PlaiTestr::Deck.build(@rules).shuffle(random: @rng)

        players.each { |p| hand(p).replace(sorted(deck.shift(HAND_SIZE))) }
        data.merge!('hand' => data['hand'] + 1, 'dealer' => dealer, 'discard' => [deck.shift], 'stock' => deck,
                    'step' => 'draw', 'active' => opponent(dealer), 'taken' => nil, 'turns' => 0)
        log("Hand #{data['hand']}: #{dealer} dealt; the upcard is #{top['name']}")
      end

      def draw(player, source)
        card = source == 'stock' ? stock.shift : discard_pile.pop

        hand(player).replace(sorted(hand(player) + [card]))
        data.merge!('step' => 'discard', 'taken' => (card['uid'] if source == 'discard'))

        if source == 'stock'
          log("#{player} drew from the stock")
          log("You drew the #{card['name']}", to: player)
        else
          log("#{player} took the #{card['name']} from the discard pile")
        end
      end

      def discard(player, uid, knock:)
        card = take(player, uid)
        discard_pile << card
        log("#{player} discarded #{card['name']}")

        data['turns'] += 1

        if knock then score_hand(player)
        elsif stock.length <= DEAD_STOCK then dead_hand('draw', "The stock is down to #{DEAD_STOCK} cards: hand #{data['hand']} is a draw")
        elsif data['turns'] >= MAX_TURNS then dead_hand('turn_cap', "Hand #{data['hand']} is a draw")
        else data.merge!('step' => 'draw', 'active' => opponent(player), 'taken' => nil)
        end
      end

      def score_hand(knocker)
        defender = opponent(knocker)
        knock    = Melds.best(hand(knocker))
        defense  = Melds.best(hand(defender))
        gin      = knock.deadwood.empty?
        left     = gin ? defense.deadwood : Melds.lay_off(defense.deadwood, knock.melds)
        margin   = Melds.points(left) - knock.points

        winner, points, result =
          if gin then [knocker, margin + @rules.fetch('gin_bonus'), 'gin']
          elsif margin.positive? then [knocker, margin, 'knock']
          else [defender, @rules.fetch('undercut_bonus') - margin, 'undercut']
          end

        pstate(winner).apply_changes('score' => pstate(winner).score + points)
        data['results'] = data.fetch('results', {}).merge(result => data.dig('results', result).to_i + 1)
        wins = (data['hand_wins'] ||= {})[winner] ||= {}
        wins[result] = wins[result].to_i + 1
        log("#{knocker} #{gin ? 'went gin' : "knocked with #{knock.points}"} (#{melds_text(knock)}); " \
            "#{defender} had #{Melds.points(left)} deadwood (#{melds_text(defense)}#{", laid off #{list(defense.deadwood - left)}" unless gin || left == defense.deadwood}). " \
            "#{winner} scores #{points}#{' for the undercut' if result == 'undercut'}.")

        if pstate(winner).score >= points_to_win then end_game(winner, "reached_#{points_to_win}")
        elsif data['hand'] >= MAX_HANDS then end_game(players.max_by { |p| pstate(p).score }, 'hand_limit')
        else deal(winner)
        end
      end

      def dead_hand(result, text)
        log(text)
        data['results'] = data.fetch('results', {}).merge(result => data.dig('results', result).to_i + 1)
        data['hand'] >= MAX_HANDS ? end_game(players.max_by { |p| pstate(p).score }, 'hand_limit') : deal(data['dealer'])
      end

      def end_game(winner, reason)
        @game_state.apply_changes('status' => { 'game_over' => true, 'winner' => winner, 'end_reason' => reason })
      end

      def instruction
        case step
        when 'draw' then 'Draw the top card of the stock, or take the top card of the discard pile.'
        when 'discard'
          "Discard one card. If your deadwood after discarding is #{knock_limit} or less you may knock; with 0 deadwood you go gin." \
            "#{" You cannot discard the #{hand(@game_state.active).find { |c| c['uid'] == data['taken'] }['name']} you just took." if data['taken']}"
        end
      end

      def melds_text(arrangement)
        melds = arrangement.melds.map { |m| "[#{list(m)}]" }.join(' ')
        "#{melds.empty? ? 'no melds' : melds}#{"; unmatched #{list(arrangement.deadwood)}" if arrangement.deadwood.any?}"
      end

      def take(player, uid) = hand(player).delete_at(hand(player).index { |c| c['uid'] == uid })

      def sorted(cards) = cards.sort_by { |c| [SUITS.index(c['suit']), c['rank']] }

      def opponent(player) = (players - [player]).first

      def list(cards)      = cards.map { |c| c['name'] }.join(', ')
      def top              = discard_pile.last
      def points_to_win    = @rules.fetch('points_to_win')
      def knock_limit      = @rules.fetch('knock_limit')
      def step             = @game_state.step
      def stock            = @game_state.stock
      def discard_pile     = @game_state.discard_pile
      def hand(player)     = pstate(player).hand
    end
  end
end
