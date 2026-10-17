module GinRummy
  module Session
    class Runner < PlaiTester::Session::Runner
      include Policy

      RULES_PATH = File.expand_path('../../../data/rules.md', __dir__)
      PERSONAS   = YAML.load_file(File.expand_path('../../../data/personas.yml', __dir__)).freeze
      RECENT_LOG = 10

      DEBRIEF_QUESTIONS = [
        'Which decision in this game mattered most, and why?',
        'When did you choose to knock (or not), and was it the right call?',
        'Which choices felt automatic (the choice did not matter)?'
      ].freeze

      def initialize(personas: nil, **options)
        super
        persona_specs
      end

      def self.persona_names = PERSONAS['personas'].keys

      private

      def setup
        custom.merge!('hand' => 0, 'log' => [])
        assign_personas
        deal(players.last)
        puts "  Setup (seed #{@seed}): first to #{points_to_win} points; #{players.map { |p| display_name(p) }.join(' vs ')}."
      end

      def next_player = @game_state.active

      def legal_moves(player)
        case step
        when 'draw'    then draw_moves
        when 'discard' then discard_moves(player)
        end
      end

      def draw_moves
        [
          move('Draw the top card of the stock (face-down)', 'draw', { 'source' => 'stock' }, public: 'drew from the stock'),
          move("Take the #{top['name']} from the discard pile", 'draw', { 'source' => 'discard' }, public: "took the #{top['name']} from the discard pile")
        ]
      end

      def discard_moves(player)
        hand(player).reject { |c| c['uid'] == custom['taken'] }.flat_map do |card|
          deadwood = Melds.best(hand(player) - [card]).points
          params   = { 'value' => card['uid'], 'deadwood' => deadwood }

          [
            move("Discard #{card['name']} (deadwood after: #{deadwood})", 'discard', params, public: "discarded #{card['name']}"),
            (knock_move(card, params) if deadwood <= knock_limit)
          ].compact
        end
      end

      def knock_move(card, params)
        gin = params['deadwood'].zero?
        move(gin ? "Discard #{card['name']} and go gin" : "Discard #{card['name']} and knock with #{params['deadwood']} deadwood",
             'discard', params.merge('knock' => true), public: "discarded #{card['name']} and #{gin ? 'went gin' : 'knocked'}")
      end

      def move(label, action, parameters, public:)
        { 'label' => label, 'public' => public, 'action' => { 'action' => action, 'parameters' => parameters } }
      end

      def apply_action_effects(player, action)
        params = action['parameters']

        case action['action']
        when 'draw'    then draw(player, params['source'])
        when 'discard' then discard(player, params['value'], knock: params['knock'])
        end
      end

      def deal(dealer)
        deck = PlaiTester::Deck.build(@rules).shuffle(random: @rng)

        players.each { |p| hand(p).replace(sorted(deck.shift(HAND_SIZE))) }
        custom.merge!('hand' => custom['hand'] + 1, 'dealer' => dealer, 'discard' => [deck.shift], 'stock' => deck,
                      'step' => 'draw', 'active' => opponent(dealer), 'taken' => nil)
        log("Hand #{custom['hand']}: #{dealer} dealt; the upcard is #{top['name']}")
      end

      def draw(player, source)
        card = source == 'stock' ? stock.shift : discard_pile.pop

        hand(player).replace(sorted(hand(player) + [card]))
        custom.merge!('step' => 'discard', 'taken' => (card['uid'] if source == 'discard'))

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

        if knock then score_hand(player)
        elsif stock.length <= DEAD_STOCK then dead_hand
        else custom.merge!('step' => 'draw', 'active' => opponent(player), 'taken' => nil)
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
        custom['results'] = custom.fetch('results', {}).merge(result => custom.dig('results', result).to_i + 1)
        log("#{knocker} #{gin ? 'went gin' : "knocked with #{knock.points}"} (#{melds_text(knock)}); " \
            "#{defender} had #{Melds.points(left)} deadwood (#{melds_text(defense)}#{", laid off #{list(defense.deadwood - left)}" unless gin || left == defense.deadwood}). " \
            "#{winner} scores #{points}#{' for the undercut' if result == 'undercut'}.")

        if pstate(winner).score >= points_to_win then end_game(winner, "reached_#{points_to_win}")
        elsif custom['hand'] >= MAX_HANDS then end_game(players.max_by { |p| pstate(p).score }, 'hand_limit')
        else deal(winner)
        end
      end

      def dead_hand
        log("The stock is down to #{DEAD_STOCK} cards: hand #{custom['hand']} is a draw")
        custom['results'] = custom.fetch('results', {}).merge('draw' => custom.dig('results', 'draw').to_i + 1)
        custom['hand'] >= MAX_HANDS ? end_game(players.max_by { |p| pstate(p).score }, 'hand_limit') : deal(custom['dealer'])
      end

      def end_game(winner, reason)
        @game_state.apply_changes('flags' => { 'game_over' => true, 'winner' => winner, 'end_reason' => reason })
      end

      def rules_text_for(_player) = @rules_text ||= File.read(RULES_PATH)

      def view_text_for(player)
        best = Melds.best(hand(player))

        [
          "Hand #{custom['hand']}. Scores (first to #{points_to_win}): #{players.map { |p| "#{whose(p, player)} #{pstate(p).score}" }.join(', ')}",
          "Your hand: #{list(hand(player))}",
          "Your best melds: #{melds_text(best)}; deadwood #{best.points}",
          "Discard pile: #{top['name']} on top (#{discard_pile.length} cards). Stock: #{stock.length} cards. #{opponent(player)} holds #{hand(opponent(player)).length} cards.",
          '',
          instruction
        ].join("\n")
      end

      def instruction
        case step
        when 'draw' then 'Draw the top card of the stock, or take the top card of the discard pile.'
        when 'discard'
          "Discard one card. If your deadwood after discarding is #{knock_limit} or less you may knock; with 0 deadwood you go gin." \
            "#{" You cannot discard the #{hand(@game_state.active).find { |c| c['uid'] == custom['taken'] }['name']} you just took." if custom['taken']}"
        end
      end

      def turn_phase(_player) = "hand #{custom['hand']} · #{step}"

      def persona_for(player)
        persona = PERSONAS.dig('personas', custom.dig('personas', player))

        <<~TEXT.strip
          BASIC STRATEGY:
          #{PERSONAS['basic_strategy'].map { |rule| "- #{rule}" }.join("\n")}

          YOUR STYLE: #{persona['name']}
          #{persona['goal']}
        TEXT
      end

      def persona_specs
        names     = self.class.persona_names
        requested = Array(@persona_request)
        raise ArgumentError, "#{requested.length} personas given for #{players.length} players" if requested.length > players.length

        requested.map do |name|
          next if name == '*'
          raise ArgumentError, "Unknown persona #{name.inspect} (choose from #{names.join(', ')}, or *)" unless names.include?(name)

          name
        end
      end

      def assign_personas
        specs = persona_specs
        pool  = self.class.persona_names - specs.compact
        custom['personas'] = players.each_with_index.to_h { |p, i| [p, specs[i] || pool.delete(pool.sample(random: @rng))] }
      end

      def display_name(player)
        name = custom.dig('personas', player) or return player
        "#{name} (#{player})"
      end

      def recent_events_for(player) = event_log.recent_for(player, RECENT_LOG)

      def debrief_questions(_player) = DEBRIEF_QUESTIONS

      def melds_text(arrangement)
        melds = arrangement.melds.map { |m| "[#{list(m)}]" }.join(' ')
        "#{melds.empty? ? 'no melds' : melds}#{"; unmatched #{list(arrangement.deadwood)}" if arrangement.deadwood.any?}"
      end

      def take(player, uid) = hand(player).delete_at(hand(player).index { |c| c['uid'] == uid })

      def sorted(cards) = cards.sort_by { |c| [SUITS.index(c['suit']), c['rank']] }

      def opponent(player) = (players - [player]).first

      def whose(player, viewer) = player == viewer ? 'You' : player

      def log(text, to: nil) = event_log.add(text, turn: custom['hand'], to: to)

      def event_log = PlaiTester::EventLog.new(custom['log'])

      def list(cards)      = cards.map { |c| c['name'] }.join(', ')
      def top              = discard_pile.last
      def points_to_win    = @rules.fetch('points_to_win')
      def knock_limit      = @rules.fetch('knock_limit')
      def custom           = @game_state.custom
      def step             = @game_state.step
      def stock            = @game_state.stock
      def discard_pile     = @game_state.discard_pile
      def players          = @game_state.players
      def pstate(player)   = @game_state.player_state(player)
      def hand(player)     = pstate(player).hand
    end
  end
end
