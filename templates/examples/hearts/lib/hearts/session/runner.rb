module Hearts
  module Session
    class Runner < PlaiTestr::Session::Runner
      include Bot

      DEBRIEF_QUESTIONS = [
        'Which of your passes or plays mattered most, and why? Name the hand.',
        'When did you take points you meant to avoid? What happened?',
        'Which rule or restriction was unclear when you had to follow it? Name the situation.',
        'Did your strategy work? Use GAME FACTS to say what helped it and what got in the way.'
      ].freeze

      def setup
        data.merge!('hand' => 0, 'log' => [], 'taken_total' => %w[hearts queen moons].to_h { |key| [key, players.to_h { |p| [p, 0] }] })
        deal
        out.puts "  Setup (seed #{@seed}): #{players.length} players; the game ends at #{limit} points."
      end

      def next_player = @game_state.active

      def legal_moves(player)
        case step
        when 'pass'
          hand(player).map { |card| option("Pass #{card['name']}#{" (#{pts(Hearts.points(card))})" if Hearts.points(card).positive?}", pass: { value: card['uid'] }) }
        when 'play'
          playable(player).map do |card|
            facts = [(pts(Hearts.points(card)) if Hearts.points(card).positive?), (outcome(card) unless trick.empty?)].compact
            option("Play #{card['name']}#{" (#{facts.join('; ')})" if facts.any?}", public: "played #{card['name']}", play: { value: card['uid'] })
          end
        end
      end

      def pick_range(_player) = step == 'pass' ? [PASS_COUNT, PASS_COUNT] : nil

      def apply_action_effects(player, action)
        case action
        in { pass: { value: uids } } then pass(player, uids)
        in { play: { value: uid } }  then play(player, uid)
        end
      end

      def view_text_for(player)
        [
          "Hand #{data['hand']}. Scores (lower is better; the game ends at #{limit}): #{per_player(player) { |p| pstate(p).score }}",
          ("Points taken this hand: #{per_player(player) { |p| points_in(taken[p]) }}. Hearts broken: #{data['hearts_broken'] ? 'yes' : 'no'}." if step == 'play'),
          ("Current trick: #{trick_text(player)}" if step == 'play'),
          "Your hand: #{list(hand(player))}",
          '',
          instruction(player)
        ].compact.join("\n")
      end

      def turn_phase(_player)
        step == 'pass' ? "hand #{data['hand']} · pass #{data['pass']}" : "hand #{data['hand']} · trick #{data['tricks'] + 1}"
      end

      def report_sections
        rows = players.map { |p| "| #{p} | #{pstate(p).score} | #{totals['hearts'][p]} | #{totals['queen'][p]} | #{totals['moons'][p]} |" }

        [<<~MD.strip]
          ## Hearts

          #{data['hand']} hands played.

          | Player | Score | Hearts taken | Q♠ taken | Moons shot |
          |---|---|---|---|---|
          #{rows.join("\n")}
        MD
      end

      def botrun_stats = { 'hands' => data['hand'], 'taken' => totals }

      def debrief_facts(_player)
        {
          'how_it_ended' => "#{@game_state.status['end_reason'].to_s.tr('_', ' ')} after #{data['hand']} hands, when " \
                            "#{players.select { |p| pstate(p).score >= limit }.join(' and ')} reached #{limit} points (lower scores are better)",
          'players' => players.to_h do |p|
            [p, { 'final_score' => pstate(p).score, 'hearts_taken' => totals['hearts'][p], 'queen_of_spades_taken' => totals['queen'][p],
                  'moons_shot' => totals['moons'][p] }]
          end
        }
      end

      def debrief_questions(_player) = DEBRIEF_QUESTIONS

      private

      def deal
        deck   = PlaiTestr::Deck.build(@rules).shuffle(random: @rng)
        number = data['hand'] + 1

        players.each { |p| hand(p).replace(sorted(deck.shift(HAND_SIZE))) }
        data.merge!('hand' => number, 'pass' => PASSES[(number - 1) % PASSES.length], 'passes' => {},
                    'taken' => players.to_h { |p| [p, []] }, 'trick' => [], 'tricks' => 0, 'hearts_broken' => false)
        log("Hand #{number} dealt: pass #{data['pass']}")

        if data['pass'] == 'hold'
          start_tricks
        else
          data.merge!('step' => 'pass', 'active' => players.first)
        end
      end

      def pass(player, uids)
        data['passes'][player] = uids

        if data['passes'].length == players.length
          exchange
        else
          data['active'] = seat(player, 1)
        end
      end

      def exchange
        given = data['passes'].to_h { |giver, uids| [giver, uids.map { |uid| take(giver, uid) }] }

        given.each do |giver, cards|
          receiver = seat(giver, SEAT_SHIFT.fetch(data['pass']))
          hand(receiver).replace(sorted(hand(receiver) + cards))
          log("You passed #{list(cards)} to #{receiver}", to: giver)
          log("#{giver} passed you #{list(cards)}", to: receiver)
        end
        start_tricks
      end

      def start_tricks
        data.merge!('step' => 'play', 'active' => players.find { |p| hand(p).any? { |c| c['name'] == OPENER } })
      end

      def play(player, uid)
        card = take(player, uid)
        trick << { 'player' => player, 'card' => card }
        data['hearts_broken'] ||= card['suit'] == 'hearts'
        log("#{player} played #{card['name']}")

        if trick.length == players.length
          finish_trick
        else
          data['active'] = seat(player, 1)
        end
      end

      def finish_trick
        winner = trick.select { |t| t['card']['suit'] == led_suit }.max_by { |t| t['card']['rank'] }['player']
        cards  = trick.map { |t| t['card'] }

        taken[winner].concat(cards)
        log("#{winner} took the trick (#{list(cards)})#{" for #{pts(points_in(cards))}" if points_in(cards).positive?}")
        data.merge!('trick' => [], 'tricks' => data['tricks'] + 1, 'active' => winner)
        score_hand if data['tricks'] == HAND_SIZE
      end

      def score_hand
        points  = players.to_h { |p| [p, points_in(taken[p])] }
        shooter = points.key(MOON)
        points  = players.to_h { |p| [p, p == shooter ? 0 : MOON] } if shooter

        players.each do |p|
          pstate(p).apply_changes('score' => pstate(p).score + points[p])
          totals['hearts'][p] += taken[p].count { |c| c['suit'] == 'hearts' }
          totals['queen'][p]  += 1 if taken[p].any? { |c| c['name'] == QUEEN }
        end
        totals['moons'][shooter] += 1 if shooter
        log("Hand #{data['hand']} scored: #{players.map { |p| "#{p} +#{points[p]}" }.join(', ')}#{" (#{shooter} shot the moon)" if shooter}")

        players.any? { |p| pstate(p).score >= limit } ? end_game : deal
      end

      def end_game
        low     = players.map { |p| pstate(p).score }.min
        winners = players.select { |p| pstate(p).score == low }

        @game_state.apply_changes('status' => { 'game_over' => true, 'winner' => winners.join(' & '),
                                                'end_reason' => winners.one? ? 'fewest_points' : 'tied_for_fewest_points' })
      end

      def playable(player)
        cards = hand(player)

        if trick.empty?
          data['tricks'].zero? ? cards.select { |c| c['name'] == OPENER } : leads(cards)
        else
          follows(cards)
        end
      end

      def leads(cards)
        safe = cards.reject { |c| c['suit'] == 'hearts' }
        data['hearts_broken'] || safe.empty? ? cards : safe
      end

      def follows(cards)
        suited = cards.select { |c| c['suit'] == led_suit }
        clean  = cards.select { |c| Hearts.points(c).zero? }

        if suited.any? then suited
        elsif data['tricks'].zero? && clean.any? then clean
        else cards
        end
      end

      def trick_text(player)
        return 'none yet (you lead)' if trick.empty?

        points = points_in(trick.map { |t| t['card'] })
        "#{trick.map { |t| "#{whose(t['player'], player)}: #{t['card']['name']}" }.join(', ')} (#{led_suit} led; #{points.zero? ? 'no points' : pts(points)} in it so far)"
      end

      def outcome(card)
        best = trick.map { |t| t['card'] }.select { |c| c['suit'] == led_suit }.max_by { |c| c['rank'] }

        if card['suit'] != led_suit then 'cannot win this trick'
        elsif card['rank'] < best['rank'] then "stays under the #{best['name']}"
        elsif last_to_play? then 'wins the trick'
        else 'wins the trick so far'
        end
      end

      def instruction(player)
        case step
        when 'pass' then "Choose #{PASS_COUNT} cards to pass #{data['pass']} to #{seat(player, SEAT_SHIFT.fetch(data['pass']))}."
        when 'play' then play_instruction(player)
        end
      end

      def play_instruction(player)
        if trick.empty?
          "You lead this trick.#{' Hearts are not broken, so you may not lead a heart unless you have only hearts.' unless data['hearts_broken']}"
        elsif hand(player).any? { |c| c['suit'] == led_suit }
          "You are following, not leading: you must play one of your #{led_suit}."
        else
          "You are following, not leading. You have no #{led_suit}, so you may play any card#{', but not a heart or the Q♠ unless you have nothing else' if data['tricks'].zero?}."
        end
      end

      def take(player, uid) = hand(player).delete_at(hand(player).index { |c| c['uid'] == uid })

      def sorted(cards) = cards.sort_by { |c| [SUITS.index(c['suit']), c['rank']] }

      def seat(player, shift) = players[(players.index(player) + shift) % players.length]

      def per_player(viewer) = players.map { |p| "#{whose(p, viewer)} #{yield p}" }.join(', ')

      def points_in(cards) = cards.sum { |c| Hearts.points(c) }
      def list(cards)      = cards.map { |c| c['name'] }.join(', ')
      def pts(points)      = points == 1 ? '1 pt' : "#{points} pts"
      def led_suit         = trick.first['card']['suit']
      def limit            = @rules.fetch('points_to_end')
      def step             = @game_state.step
      def trick            = @game_state.trick
      def taken            = @game_state.taken
      def totals           = data['taken_total']
      def hand(player)     = pstate(player).hand
    end
  end
end
