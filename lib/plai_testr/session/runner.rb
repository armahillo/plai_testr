module PlaiTestr
  module Session
    class Runner
      RECENT_EVENTS = 8
      DEBRIEF_LOG   = 300
      MAX_PLAN_CHANGES = 15
      MODES         = %w[llm hybrid bot].freeze
      MOVE_KEYS     = %i[label public log action].freeze

      attr_reader :seed, :out, :warnings, :game_state, :turn_log, :report_path

      # Status of the last run: 'completed' or 'interrupted'.
      attr_reader :status

      def self.resume(game, session_id, out: $stdout, verbose: false)
        checkpoint = Manager.new(session_id: session_id, persist: false).load_checkpoint
        raise SessionError, "Session #{session_id} is already complete; its report is in #{PlaiTestr.reports_dir}" if checkpoint['status'] == 'completed'
        unless checkpoint['fingerprint'] == game.fingerprint
          raise SessionError, "#{game.name} has changed since session #{session_id} was saved (its data, code or the gem version), " \
                              'so it cannot be resumed exactly. Start a new session with: play'
        end

        data   = checkpoint.dig('game_state', 'data')
        models = { player: data['player_model'], referee: data['referee_model'], think: data['think'] }
        runner = new(game: game, players: checkpoint.dig('game_state', 'players'), models: models, seed: data['seed'],
                     mode: data['mode'], session_id: session_id, out: out, verbose: verbose)
        runner.send(:restore, checkpoint)
        runner
      end

      def self.redebrief(game, session_id, models: {}, out: $stdout, verbose: false)
        checkpoint = Manager.new(session_id: session_id, persist: false).load_checkpoint
        raise SessionError, "Session #{session_id} is not complete (#{checkpoint['status']}); finish it with: resume #{session_id}" unless checkpoint['status'] == 'completed'

        data   = checkpoint.dig('game_state', 'data')
        runner = new(game: game, players: checkpoint.dig('game_state', 'players'), seed: data['seed'], mode: data['mode'], session_id: session_id,
                     models: { player: data['player_model'], debrief: models[:debrief] || data['player_model'], debrief_think: models[:debrief_think] },
                     out: out, verbose: verbose)
        runner.send(:restore, checkpoint)
        unless checkpoint['fingerprint'] == game.fingerprint
          runner.send(:warning, "#{game.name} has changed since session #{session_id} was played (data, code or gem version); " \
                                'the debrief reads the current rules text')
        end
        runner
      end

      def initialize(game:, players:, models: {}, seed: nil, mode: 'llm', personas: nil, persist: true, out: $stdout, verbose: false,
                     echo_warnings: true, session_id: nil)
        raise UsageError, "Unknown mode #{mode.inspect} (choose from #{MODES.join(', ')})" unless MODES.include?(mode)

        @game          = game
        @rules         = game.rules
        @personas      = game.personas
        @models        = models
        @mode          = mode
        @persist       = persist
        @out           = out
        @echo_warnings = echo_warnings
        @seed          = seed || Kernel.rand(1_000_000)
        @manager       = Manager.new(session_id: session_id, persist: persist)
        @game_state    = game.game_state_class.new(players: players)
        @turn_log      = []
        @warnings      = []
        @running       = true
        @started       = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @fingerprint   = game.fingerprint if persist
        @client        = Agents::OllamaClient.new(think_log: (think_log_path if persist), out: out, verbose: verbose)
        @settings      = resolve_settings
        @rng           = rng_for(0)
        build_agents

        data.merge!('seed' => @seed, 'mode' => @mode, 'player_model' => models[:player], 'referee_model' => models[:referee],
                    'think' => models[:think] == true, 'host' => Socket.gethostname)
        request = @personas.check_request(personas, players: players.length)
        data['personas'] = @personas.assign(players, request, rng_for('personas')) if @personas.any?
      end

      def session_id
        @manager.session_id
      end

      def run
        with_signal_traps do
          out.puts "Session #{session_id}"
          out.puts "Game:    #{@rules.dig('game', 'name')} v#{@rules.dig('game', 'version')}"
          out.puts "Players: #{@game_state.players.map { |p| display_name(p) }.join(', ')}"
          out.puts "Seed:    #{@seed}"
          out.puts "Press Ctrl+C to save state and exit.\n\n"

          fit_settings_to_model unless @mode == 'bot'
          setup unless @resumed
          until game_over? || !@running
            play_turn
            yield @game_state.turn if block_given?
          end
          run_debrief if game_over? && @running && @mode != 'bot'
        end
        finish
      rescue Interrupt
        finish
      end

      # Plays a whole game in memory with no checkpoints, transcript or report (used by botruns).
      def play_out
        setup
        play_turn until game_over?
        self
      end

      def play_turn
        player = next_player
        @game_state.current_player = player
        @rng   = rng_for(decision)
        moves  = menu(player)
        pick   = pick_range(player)
        check_menu(player, moves, pick)
        phase  = turn_phase(player)

        if pick
          play_pick_turn(player, moves, phase, *pick)
        elsif moves.length == 1
          play_forced_turn(player, moves.first, phase)
        else
          play_choice_turn(player, moves, phase)
        end
        stop_at_decision_limit
      end

      def menu(player_name) = legal_moves(player_name).map { |move| symbolize(move) }

      def botrun_result
        {
          'seed'       => @seed,
          'winner'     => @game_state.status['winner'],
          'end_reason' => @game_state.status['end_reason'],
          'names'      => display_names,
          'personas'   => data['personas'],
          'decisions'  => @turn_log.length,
          'rules'      => @turn_log.filter_map { |t| t['rule'] }.tally,
          'stats'      => botrun_stats,
          'warnings'   => @warnings
        }
      end

      def option(label, public: nil, log: nil, **action)
        { label: label, public: public, log: log, action: action }.compact
      end

      def data = @game_state.data

      def log(text, to: nil, turn: log_turn)
        player, decider = @acting
        tag = decider unless decider == 'LLM'
        event_log.add(text, turn: turn, to: to, actor: player, tag: tag)
      end

      def event_log = EventLog.new(data['log'] ||= [])

      def persona(player) = data.dig('personas', player)

      def persona_name(player) = persona(player)&.then { |key| @personas.name(key) }

      def bot_strategy_for(player) = @personas.bot(persona(player))

      def display_names
        @game_state.players.to_h { |p| [p, display_name(p)] }
      end

      # --- Game hooks ------------------------------------------------------------------
      # A move is { 'label' => String, 'action' => { name => params }, 'public' => String (optional),
      # 'log' => String (optional) }. 'label' is what the acting player sees; 'public' is what
      # opponents see; 'log' is the short text for the console and report.

      def setup
        raise NotImplementedError, "#{self.class} must implement #setup"
      end

      def legal_moves(_player_name)
        raise NotImplementedError, "#{self.class} must implement #legal_moves"
      end

      def apply_action_effects(_player_name, _action)
        raise NotImplementedError, "#{self.class} must implement #apply_action_effects"
      end

      # Who acts next. Default: strict alternation via GameState#advance_turn.
      def next_player
        @game_state.current_player
      end

      def pick_range(_player_name)
        nil
      end

      def game_over?
        @game_state.status['game_over'] == true
      end

      def turn_phase(_player_name)
        nil
      end

      def persona_for(player_name)
        key = persona(player_name) or return nil

        "#{persona_name(player_name)}\n#{@personas.strategy(key).map { |item| "- #{item}" }.join("\n")}"
      end

      def display_name(player_name)
        key = persona(player_name) or return player_name

        data['personas'].values.count(key) > 1 ? "#{persona_name(player_name)} (#{player_name})" : persona_name(player_name)
      end

      # Rules text for the menu system prompt: the game's data/rules.md, else its description.
      # Override to scope rules to the current step or to append generated text (a card list).
      def rules_text_for(_player_name)
        @rules_text ||= File.exist?(@game.rules_text) ? File.read(@game.rules_text) : @rules.dig('game', 'description').to_s
      end

      # What the player is allowed to see, as text. Override with a readable view.
      def view_text_for(player_name)
        JSON.pretty_generate(@game_state.serialize_for(player_name))
      end

      # Optional one-off note for this prompt (e.g. "your stack choice collided; choose again").
      def prompt_note_for(_player_name)
        nil
      end

      # Questions each player answers once after the game ends (designer feedback).
      # Return [] to skip the debrief.
      def debrief_questions(_player_name)
        []
      end

      # What a player reads after the debrief summary: the result, their final view and the
      # log entries they could see. Override for a richer final position.
      def debrief_view_for(player_name)
        entries = event_log.visible_to(player_name).last(DEBRIEF_LOG)
        [
          "The game is over: #{result_text(player_name)}.",
          view_text_for(player_name),
          ("GAME LOG ([#{log_turn_name}] event):\n#{entries.map { |e| "- [#{e['turn']}] #{'(private) ' if e['to']}#{e['text']}" }.join("\n")}" if entries.any?)
        ].compact.join("\n\n")
      end

      # The number stamped on each log entry, shown in recent events and the debrief log.
      # Defaults to the decision number; games with rounds return the round.
      def log_turn = decision

      def log_turn_name = 'decision'

      def report_sections
        []
      end

      def report_debrief? = true

      # The bot policy. Return nil (no opinion) or { 'choice' => n } ({ 'choices' => [n, ...] } when
      # pick is [min, max]) plus 'rule' => name and 'obvious' => true when the move is clearly best.
      # Mode 'hybrid' plays obvious moves without asking the model; mode 'bot' plays every scripted
      # move and option 1 when there is none. In 'llm' and 'hybrid' runs the turn log keeps what the
      # bot would have chosen, to compare with the model.
      def bot_choice(_player_name, _moves, pick: nil)
        nil
      end

      def think_about?(_player_name) = true

      # Game-specific numbers for one botrun game (see Reporter::BotrunReport).
      def botrun_stats
        {}
      end

      def debrief_facts(_player_name)
        botrun_stats
      end

      def debrief_summary(player_name)
        facts = debrief_facts(player_name)
        facts = facts.to_yaml.delete_prefix("---\n") if facts.is_a?(Hash)
        plans = plan_changes(player_name)

        [
          "OUTCOME:\n#{outcome_text(player_name)}",
          ("GAME FACTS (counted by the game engine):\n#{facts}" unless facts.to_s.strip.empty? || facts.strip == '{}'),
          "YOUR DECISIONS:\n#{decisions_text(player_name)}",
          ("YOUR PLAN AS IT CHANGED (decision · step: plan):\n#{plans.join("\n")}" if plans.any?)
        ].compact.join("\n\n")
      end

      def debrief!
        data['debrief_history'] = [*data['debrief_history'], data.slice('debrief', 'debrief_model', 'debrief_think')] if data['debrief']
        data.delete('debrief')
        fit_settings_to_model
        run_debrief
        save_checkpoint('completed')
        @report_path = generate_report
      end

      def recent_events_for(player_name)
        event_log.recent_for(player_name, @game.recent_events || RECENT_EVENTS)
      end

      private

      # --- Helpers for games -----------------------------------------------------------

      def players = @game_state.players

      def pstate(player_name) = @game_state.player_state(player_name)

      def whose(player_name, viewer) = player_name == viewer ? 'You' : player_name

      # Counts something per player in data['tally'] (checkpointed), for reports and debrief facts.
      def tally(player_name, key, amount = 1)
        counts = ((data['tally'] ||= {})[player_name] ||= {})
        counts[key] = counts.fetch(key, 0) + amount
      end

      # The one player with the top score, or nil on a tie.
      def sole_leader(scores = @game_state.scores)
        top = scores.values.max
        scores.key(top) if scores.values.count(top) == 1
      end

      def result_text(player_name)
        status = @game_state.status
        winner = status['winner']
        reason = status['end_reason'].to_s.tr('_', ' ')
        scores = @game_state.scores.map { |p, score| "#{whose(p, player_name)} #{score}" }.join(', ')

        "#{winner ? "#{winner == player_name ? 'you won' : "#{winner} won"}" : 'no winner'} (#{reason}). Final scores: #{scores}"
      end

      # --- Turns -----------------------------------------------------------------------

      def decision = @game_state.turn + 1

      def rng_for(key) = ::Random.new(Digest::SHA256.hexdigest("#{@seed}:#{key}").to_i(16))

      def max_decisions = @game.max_decisions || PlaiTestr.config.max_decisions

      def check_menu(player_name, moves, pick)
        raise MoveError, "#{self.class}#legal_moves(#{player_name.inspect}) returned no moves at decision #{decision}" if moves.empty? && pick.nil?

        moves.each_with_index do |move, i|
          problem = move_problem(move, pick)
          raise MoveError, "#{self.class}#legal_moves(#{player_name.inspect}), decision #{decision}, option #{i + 1}: #{problem}\n  #{move.inspect}" if problem
        end

        repeated = pick ? [] : moves.map { |m| m[:label] }.tally.select { |_, count| count > 1 }.keys
        warning("#{self.class}#legal_moves repeats the label(s) #{repeated.map(&:inspect).join(', ')}") if repeated.any?
      end

      def move_problem(move, pick)
        return 'a move must be a Hash' unless move.is_a?(Hash)

        unknown = move.keys - MOVE_KEYS
        return "unknown key(s) #{unknown.map(&:inspect).join(', ')} (allowed: #{MOVE_KEYS.join(', ')})" if unknown.any?
        return 'label must be a non-empty String' unless move[:label].is_a?(String) && !move[:label].strip.empty?

        action = move[:action]
        return 'action must have exactly one name with params: { play: { value: ... } }' unless action.is_a?(Hash) && action.length == 1 && action.values.first.is_a?(Hash)
        return "pick turns need a value in each action's params" if pick && !action.values.first.key?(:value)

        nil
      end

      def heading(player_name, phase)
        "Turn #{decision} — #{display_name(player_name)}#{" · #{phase}" if phase}"
      end

      # Menu turns cannot be illegal (every option is legal by construction), so there is no
      # referee call — an unparseable reply falls back to the bot's choice (or a random one) and is flagged.
      def play_choice_turn(player_name, moves, phase)
        out.puts "#{heading(player_name, phase)} (#{moves.length} options)"

        script = script_for(player_name, moves)
        result = scripted?(script) ? bot_result(script, 'choice' => 1) : ask(player_name, moves)
        result = fallback(result, script, 'choice' => fallback_rng.rand(moves.length) + 1) if result['fallback']
        move   = moves[result['choice'] - 1]
        out.puts "  #{decider_mark(result)} #{move[:log] || move[:label]}#{decider_note(result)}"

        apply(player_name, move[:action], result['decider'])
        record_turn(player_name, move[:action], { 'phase' => phase, 'label' => move[:label], 'log' => move[:log],
                                                  'public' => move[:public] || move[:label],
                                                   'options' => moves.length, 'choice' => result['choice'] }
                                                 .merge(model_fields(result), decider_fields(result, script, 'choice')))
      end

      def play_forced_turn(player_name, move, phase)
        out.puts "#{heading(player_name, phase)}: #{move[:log] || move[:label]} [only option]"

        apply(player_name, move[:action], nil)
        record_turn(player_name, move[:action], 'phase' => phase, 'label' => move[:label], 'log' => move[:log],
                                                'public' => move[:public] || move[:label],
                                                 'options' => 1, 'choice' => 1, 'attempts' => 0, 'fallback' => false, 'auto' => true)
      end

      def play_pick_turn(player_name, moves, phase, min, max)
        max = [max, moves.length].min
        min = [min, max].min

        if min == moves.length
          script = nil
          result = { 'choices' => (1..min).to_a, 'attempts' => 0, 'fallback' => false, 'auto' => true }
        else
          out.puts "#{heading(player_name, phase)} (pick #{min}-#{max} of #{moves.length})"
          script = script_for(player_name, moves, pick: [min, max])
          result = scripted?(script) ? bot_result(script, 'choices' => (1..min).to_a) : ask(player_name, moves, min: min, max: max)
          result = fallback(result, script, 'choices' => (1..moves.length).to_a.sample(min, random: fallback_rng)) if result['fallback']
        end

        chosen = result['choices'].map { |i| moves[i - 1] }
        label  = chosen.empty? ? '(none)' : chosen.map { |m| m[:label] }.join('; ')
        log    = chosen.empty? ? '(none)' : chosen.map { |m| m[:log] || m[:label] }.join('; ')
        name   = moves.empty? ? :pick : moves.first[:action].keys.first
        action = { name => { value: chosen.map { |m| m[:action].values.first[:value] } } }
        out.puts "  #{decider_mark(result)} #{log}#{decider_note(result)}" unless result['auto']

        apply(player_name, action, result['decider'])
        record_turn(player_name, action, { 'phase' => phase, 'label' => label, 'log' => log, 'public' => chosen.map { |m| m[:public] }.compact.join('; '),
                                           'options' => moves.length, 'choice' => result['choices'], 'auto' => result['auto'] || false }
                                         .merge(model_fields(result), result['auto'] ? {} : decider_fields(result, script, 'choices')))
      end

      def ask(player_name, moves, **pick)
        prompt = { rules_text: rules_text_for(player_name), view_text: view_text_for(player_name), labels: moves.map { |m| m[:label] },
                   plan: last_plan(player_name), recent: recent_events_for(player_name), prompt_note: prompt_note_for(player_name),
                   persona: persona_for(player_name), think: think_about?(player_name) }
        agent  = @agents[player_name]
        result = waiting_on_model { pick.empty? ? agent.choose(**prompt) : agent.choose_many(**prompt, **pick) }
        warning("context nearly full for #{player_name} at decision #{decision}; the prompt was probably truncated (raise context_size)") if result['context_full']

        result.merge('decider' => 'LLM')
      end

      def script_for(player_name, moves, pick: nil)
        bot_choice(player_name, moves, pick: pick)
      rescue StandardError => e
        raise if @mode == 'bot'

        warning("bot rule failed at decision #{decision}, the model decides: #{e.class}: #{e.message}")
        nil
      end

      def scripted?(script) = @mode == 'bot' || (@mode == 'hybrid' && script&.fetch('obvious', false))

      def bot_result(script, default)
        (script || default.merge('rule' => 'none')).merge('decider' => 'BOT', 'reasoning' => nil, 'plan' => nil, 'attempts' => 0, 'fallback' => false)
      end

      def fallback(result, script, random)
        source = script ? script.merge('decider' => 'BOT') : random.merge('decider' => 'RNG')
        result.merge(source.slice('choice', 'choices', 'rule', 'obvious', 'decider'))
      end

      def fallback_rng = rng_for("#{decision}:fallback")

      def model_fields(result)
        result.slice('reasoning', 'plan', 'attempts', 'fallback').merge(result['context_full'] ? { 'context_full' => true } : {})
      end

      def decider_fields(result, script, key)
        fields = { 'decider' => result['decider'] }
        fields.merge!('rule' => result['rule'], 'obvious' => result['obvious'] == true) if result['decider'] == 'BOT'
        fields.merge!('bot_choice' => script[key], 'bot_rule' => script['rule'], 'bot_obvious' => script['obvious'] == true) if script && result['decider'] == 'LLM'
        fields
      end

      def decider_mark(result) = "#{DECIDER_ICONS.fetch(result['decider'])} #{result['decider']} ->"

      def decider_note(result)
        notes = []
        notes << " [rule: #{result['rule']}]" if result['decider'] == 'BOT'
        notes << ' [FALLBACK]' if result['fallback']
        notes << " (#{result['attempts']} tries)" if result['attempts'] > 1
        notes.join
      end

      def apply(player_name, action, decider)
        @acting = [player_name, decider]
        apply_action_effects(player_name, action)
      ensure
        @acting = nil
      end

      def symbolize(move)
        return move unless move.is_a?(Hash)

        move   = move.transform_keys(&:to_sym)
        action = move[:action]
        move[:action] = action.to_h { |name, params| [name.to_sym, params.is_a?(Hash) ? params.transform_keys(&:to_sym) : params] } if action.is_a?(Hash)
        move
      end

      def record_turn(player_name, action, fields)
        entry = { 'turn' => decision, 'player' => player_name, 'action' => JSON.parse(JSON.generate(action)) }.merge(fields)

        @turn_log << entry
        @game_state.advance_turn
        return unless @persist

        @manager.append_transcript_entry(entry)
        save_checkpoint('in_progress')
      end

      def stop_at_decision_limit
        return if game_over? || @game_state.turn < max_decisions

        @game_state.apply_changes('status' => { 'game_over' => true, 'winner' => nil, 'end_reason' => 'decision_limit_reached' })
        out.puts "  Decision limit (#{max_decisions}) reached: the game ends with no winner."
      end

      def last_plan(player_name)
        @turn_log.reverse.find { |t| t['player'] == player_name && t['plan'] }&.fetch('plan')
      end

      # Stored in data['debrief'] so a resumed session does not ask a player twice.
      def run_debrief
        data.merge!('debrief_model' => debrief_model, 'debrief_think' => @models[:debrief_think] == true)
        @game_state.players.each do |player_name|
          questions = debrief_questions(player_name)
          next if questions.empty? || data.dig('debrief', player_name)

          out.puts "Debrief — #{display_name(player_name)}"
          answers = waiting_on_model do
            debrief_agent(player_name).debrief(rules_text: rules_text_for(player_name), view_text: debrief_view_for(player_name),
                                               summary: debrief_summary(player_name), questions: questions,
                                               persona: persona_for(player_name), think: @models[:debrief_think] == true)
          end
          data['debrief'] = (data['debrief'] || {}).merge(player_name => answers)
          save_checkpoint(@status || 'in_progress')
        end
      end

      def debrief_model = @models[:debrief] || @models[:player]

      def debrief_agent(player_name)
        return @agents[player_name] if debrief_model == @models[:player]

        Agents::PlayerAgent.new(name: player_name, model: debrief_model, client: @client, game_name: @rules.dig('game', 'name'), settings: @settings)
      end

      def outcome_text(player_name) = "#{result_text(player_name).sub(/\A./, &:upcase)}. #{@turn_log.length} decisions in all."

      def decisions_text(player_name)
        mine    = @turn_log.select { |t| t['player'] == player_name }
        model   = mine.select { |t| t['decider'] == 'LLM' }
        obvious = model.select { |t| t['bot_obvious'] }
        lines   = ["#{mine.length} decisions: #{model.length} by you, #{mine.count { |t| t['decider'] == 'BOT' }} by bot rules, " \
                   "#{mine.count { |t| t['auto'] }} with only one option."]
        lines << "Where one option was clearly best, you chose it #{obvious.count { |t| t['bot_choice'] == t['choice'] }} of #{obvious.length} times." if obvious.any?
        lines << "#{mine.count { |t| t['fallback'] }} of your replies were unusable and replaced." if mine.any? { |t| t['fallback'] }
        lines.join("\n")
      end

      def plan_changes(player_name)
        changes = @turn_log.select { |t| t['player'] == player_name && t['plan'].to_s.strip != '' }
                           .chunk_while { |a, b| a['plan'] == b['plan'] }.map(&:first)
        changes = changes.each_slice((changes.length / MAX_PLAN_CHANGES.to_f).ceil).map(&:first) if changes.length > MAX_PLAN_CHANGES
        changes.map { |t| "- #{t['turn']}#{" · #{t['phase']}" if t['phase']}: #{t['plan']}" }
      end

      def warning(text)
        warn "  [warning] #{text}" if @echo_warnings && !@warnings.include?(text)
        @warnings << text
        (data['warnings'] ||= []) << text
      end

      # --- Models ------------------------------------------------------------------------

      def resolve_settings(model_max: nil)
        settings, notes = ModelSettings.resolve(@game.model_settings, model_max: model_max)
        notes.each { |note| warning(note) }
        data['model_settings'] = settings.transform_keys(&:to_s)
        settings
      end

      def fit_settings_to_model
        model_max = @models.values_at(:player, :referee, :debrief).compact.uniq.filter_map { |model| @client.context_length(model) }.min or return
        @settings = resolve_settings(model_max: model_max)
        build_agents
      end

      def build_agents
        name     = @rules.dig('game', 'name')
        @referee = @models[:referee] && Agents::RefereeAgent.new(model: @models[:referee], client: @client, game_name: name, settings: @settings)
        @agents  = @game_state.players.to_h do |player|
          [player, Agents::PlayerAgent.new(name: player, model: @models[:player], client: @client, game_name: name, settings: @settings, think: @models[:think] == true)]
        end
      end

      def waiting_on_model
        @waiting = true
        yield
      ensure
        @waiting = false
      end

      # --- Persistence and reporting ---------------------------------------------------

      def restore(checkpoint)
        @game_state  = @game.game_state_class.from_h(checkpoint['game_state'])
        @turn_log    = checkpoint['turn_log']
        @warnings    = data.fetch('warnings', []).dup
        @fingerprint = checkpoint['fingerprint']
        @resumed     = true
      end

      def finish
        data['wall_seconds'] = data.fetch('wall_seconds', 0) + Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started
        if game_over? && @running
          @status = 'completed'
          save_checkpoint('completed')
          @report_path = generate_report
          out.puts "\nGame complete in #{Reporter::Duration.format(data['wall_seconds'])}. Report: #{@report_path}"
        else
          @status = 'interrupted'
          save_checkpoint('interrupted')
          out.puts "Saved after decision #{@game_state.turn}. Resume with: plai_testr #{@game.name} resume #{session_id}"
        end
      end

      def think_log_path
        File.join(@manager.session_dir, 'think.log')
      end

      def save_checkpoint(status)
        @manager.save_checkpoint(@game_state, @turn_log, {
          'status'        => status,
          'game'          => @game.name,
          'rules_version' => @rules.dig('game', 'version'),
          'fingerprint'   => @fingerprint
        })
      end

      def generate_report
        FileUtils.mkdir_p(PlaiTestr.reports_dir)
        Reporter::ReportBuilder.new(
          session_id: session_id,
          rules:      @rules,
          game_state: @game_state,
          turn_log:   @turn_log,
          think_log:  Reporter::ThinkLog.load(think_log_path),
          sections:   report_sections,
          names:      display_names,
          debrief:    report_debrief?,
          warnings:   @warnings
        ).build
      end

      # --- Signals -----------------------------------------------------------------------

      def with_signal_traps
        previous = %w[INT TERM].to_h { |signal| [signal, trap(signal) { interrupt! }] }
        yield
      ensure
        previous&.each { |signal, handler| trap(signal, handler || 'DEFAULT') }
      end

      # First Ctrl+C (or SIGTERM): stop after the move in progress and save. While the model is
      # still thinking nothing has changed yet, so that call is abandoned and the session saved now.
      # Second Ctrl+C: exit immediately — the checkpoint from the last completed decision is on disk.
      def interrupt!
        exit!(130) unless @running

        @running = false
        $stderr.puts "\n\nInterrupted — saving. Press Ctrl+C again to quit immediately."
        raise Interrupt if @waiting
      end
    end
  end
end
