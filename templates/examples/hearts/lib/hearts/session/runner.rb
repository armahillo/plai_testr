module Hearts
  module Session
    class Runner < PlaiTester::Session::Runner
      include Policy

      RULES_PATH = File.expand_path('../../../data/rules.md', __dir__)
      RECENT_LOG = 12

      DEBRIEF_QUESTIONS = [
        'Which decision in this game mattered most, and why?',
        'Which rule or restriction was unclear or confusing?',
        'Which choices felt automatic (the choice did not matter)?'
      ].freeze

      private

      def setup
        custom.merge!('hand' => 0, 'log' => [], 'taken_total' => %w[hearts queen moons].to_h { |key| [key, players.to_h { |p| [p, 0] }] })
        deal
        puts "  Setup (seed #{@seed}): #{players.length} players; the game ends at #{limit} points."
      end

      def next_player = @game_state.active

      def legal_moves(player)
        case step
        when 'pass'
          hand(player).map { |card| move("Pass #{card['name']}", 'pass', card) }
        when 'play'
          playable(player).map do |card|
            move("Play #{card['name']}#{" (#{pts(Hearts.points(card))})" if Hearts.points(card).positive?}", 'play', card, public: "played #{card['name']}")
          end
        end
      end

      def pick_range(_player) = step == 'pass' ? [PASS_COUNT, PASS_COUNT] : nil

      def move(label, action, card, public: nil)
        { 'label' => label, 'public' => public, 'action' => { 'action' => action, 'parameters' => { 'value' => card['uid'] } } }.compact
      end

      def apply_action_effects(player, action)
        params = action['parameters']

        case action['action']
        when 'pass' then pass(player, params['values'])
        when 'play' then play(player, params['value'])
        end
      end

      def deal
        deck   = PlaiTester::Deck.build(@rules).shuffle(random: @rng)
        number = custom['hand'] + 1

        players.each { |p| hand(p).replace(sorted(deck.shift(HAND_SIZE))) }
        custom.merge!('hand' => number, 'pass' => PASSES[(number - 1) % PASSES.length], 'passes' => {},
                      'taken' => players.to_h { |p| [p, []] }, 'trick' => [], 'tricks' => 0, 'hearts_broken' => false)
        log("Hand #{number} dealt: pass #{custom['pass']}")

        if custom['pass'] == 'hold'
          start_tricks
        else
          custom.merge!('step' => 'pass', 'active' => players.first)
        end
      end

      def pass(player, uids)
        custom['passes'][player] = uids

        if custom['passes'].length == players.length
          exchange
        else
          custom['active'] = seat(player, 1)
        end
      end

      def exchange
        given = custom['passes'].to_h { |giver, uids| [giver, uids.map { |uid| take(giver, uid) }] }

        given.each do |giver, cards|
          receiver = seat(giver, SEAT_SHIFT.fetch(custom['pass']))
          hand(receiver).replace(sorted(hand(receiver) + cards))
          log("You passed #{list(cards)} to #{receiver}", to: giver)
          log("#{giver} passed you #{list(cards)}", to: receiver)
        end
        start_tricks
      end

      def start_tricks
        custom.merge!('step' => 'play', 'active' => players.find { |p| hand(p).any? { |c| c['name'] == OPENER } })
      end

      def play(player, uid)
        card = take(player, uid)
        trick << { 'player' => player, 'card' => card }
        custom['hearts_broken'] ||= card['suit'] == 'hearts'
        log("#{player} played #{card['name']}")

        if trick.length == players.length
          finish_trick
        else
          custom['active'] = seat(player, 1)
        end
      end

      def finish_trick
        winner = trick.select { |t| t['card']['suit'] == led_suit }.max_by { |t| t['card']['rank'] }['player']
        cards  = trick.map { |t| t['card'] }

        taken[winner].concat(cards)
        log("#{winner} took the trick (#{list(cards)})#{" for #{pts(points_in(cards))}" if points_in(cards).positive?}")
        custom.merge!('trick' => [], 'tricks' => custom['tricks'] + 1, 'active' => winner)
        score_hand if custom['tricks'] == HAND_SIZE
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
        log("Hand #{custom['hand']} scored: #{players.map { |p| "#{p} +#{points[p]}" }.join(', ')}#{" (#{shooter} shot the moon)" if shooter}")

        players.any? { |p| pstate(p).score >= limit } ? end_game : deal
      end

      def end_game
        low     = players.map { |p| pstate(p).score }.min
        winners = players.select { |p| pstate(p).score == low }

        @game_state.apply_changes('flags' => { 'game_over' => true, 'winner' => winners.join(' & '),
                                               'end_reason' => winners.one? ? 'fewest_points' : 'tied_for_fewest_points' })
      end

      def playable(player)
        cards = hand(player)

        if trick.empty?
          custom['tricks'].zero? ? cards.select { |c| c['name'] == OPENER } : leads(cards)
        else
          follows(cards)
        end
      end

      def leads(cards)
        safe = cards.reject { |c| c['suit'] == 'hearts' }
        custom['hearts_broken'] || safe.empty? ? cards : safe
      end

      def follows(cards)
        suited = cards.select { |c| c['suit'] == led_suit }
        clean  = cards.select { |c| Hearts.points(c).zero? }

        if suited.any? then suited
        elsif custom['tricks'].zero? && clean.any? then clean
        else cards
        end
      end

      def rules_text_for(_player) = @rules_text ||= File.read(RULES_PATH)

      def view_text_for(player)
        [
          "Hand #{custom['hand']}. Scores (lower is better; the game ends at #{limit}): #{per_player(player) { |p| pstate(p).score }}",
          ("Points taken this hand: #{per_player(player) { |p| points_in(taken[p]) }}. Hearts broken: #{custom['hearts_broken'] ? 'yes' : 'no'}." if step == 'play'),
          ("Current trick: #{trick_text(player)}" if step == 'play'),
          "Your hand: #{list(hand(player))}",
          '',
          instruction(player)
        ].compact.join("\n")
      end

      def trick_text(player)
        return 'none yet (you lead)' if trick.empty?

        "#{trick.map { |t| "#{whose(t['player'], player)}: #{t['card']['name']}" }.join(', ')} (#{led_suit} led)"
      end

      def instruction(player)
        case step
        when 'pass' then "Choose #{PASS_COUNT} cards to pass #{custom['pass']} to #{seat(player, SEAT_SHIFT.fetch(custom['pass']))}."
        when 'play' then trick.empty? ? 'Lead a card to start the trick.' : "Play a card. You must follow #{led_suit} if you can."
        end
      end

      def turn_phase(_player)
        step == 'pass' ? "hand #{custom['hand']} · pass #{custom['pass']}" : "hand #{custom['hand']} · trick #{custom['tricks'] + 1}"
      end

      def report_sections
        rows = players.map { |p| "| #{p} | #{pstate(p).score} | #{totals['hearts'][p]} | #{totals['queen'][p]} | #{totals['moons'][p]} |" }

        [<<~MD.strip]
          ## Hearts

          #{custom['hand']} hands played.

          | Player | Score | Hearts taken | Q♠ taken | Moons shot |
          |---|---|---|---|---|
          #{rows.join("\n")}
        MD
      end

      def botrun_stats = { 'hands' => custom['hand'], 'taken' => totals }

      def recent_events_for(player) = event_log.recent_for(player, RECENT_LOG)

      def debrief_questions(_player) = DEBRIEF_QUESTIONS

      def take(player, uid) = hand(player).delete_at(hand(player).index { |c| c['uid'] == uid })

      def sorted(cards) = cards.sort_by { |c| [SUITS.index(c['suit']), c['rank']] }

      def seat(player, shift) = players[(players.index(player) + shift) % players.length]

      def per_player(viewer) = players.map { |p| "#{whose(p, viewer)} #{yield p}" }.join(', ')

      def whose(player, viewer) = player == viewer ? 'You' : player

      def log(text, to: nil) = event_log.add(text, turn: custom['hand'], to: to)

      def event_log = PlaiTester::EventLog.new(custom['log'])

      def points_in(cards) = cards.sum { |c| Hearts.points(c) }
      def list(cards)      = cards.map { |c| c['name'] }.join(', ')
      def pts(points)      = points == 1 ? '1 pt' : "#{points} pts"
      def led_suit         = trick.first['card']['suit']
      def limit            = @rules.fetch('points_to_end')
      def custom           = @game_state.custom
      def step             = @game_state.step
      def trick            = @game_state.trick
      def taken            = @game_state.taken
      def totals           = custom['taken_total']
      def players          = @game_state.players
      def pstate(player)   = @game_state.player_state(player)
      def hand(player)     = pstate(player).hand
    end
  end
end
