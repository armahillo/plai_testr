require 'spec_helper'

RSpec.describe PlaiTestr::Session::Runner do
  let(:tmp)     { Dir.mktmpdir('plai_runner_spec_') }
  let(:players) { ['Alice', 'Bob'] }
  let(:client)  { instance_double(PlaiTestr::Agents::OllamaClient, context_length: nil) }
  let(:out)     { StringIO.new }
  let(:game)    { build_game(game_class) }

  let(:game_class) do
    Class.new(described_class) do
      attr_accessor :moves, :pick, :script, :draws

      def bot_choice(_player, _moves, pick: nil) = script

      def setup = data.merge!('total' => 0, 'picked' => [])

      def legal_moves(_player) = moves

      def pick_range(_player) = pick

      def apply_action_effects(player, action)
        case action
        in { add: { value: amount } } then data['total'] += amount
        in { keep: { value: values } } then data['picked'].concat(values)
        end
        (self.draws ||= []) << @rng.rand(1000)
        log("#{player} acted")
        @game_state.apply_changes('status' => { 'game_over' => true, 'winner' => 'Alice' }) if data['total'] >= 3
      end
    end
  end

  def runner_for(models: { player: 'p-model' }, **options)
    game.runner_class.new(game: game, players: players, models: models, seed: 7, out: out, **options).tap do |r|
      r.moves = [r.option('Add one', public: 'added something', add: { value: 1 }), r.option('Add two', add: { value: 2 })]
    end
  end

  let(:runner) { runner_for }

  def chat(json) = { 'message' => { 'content' => json } }

  def report = File.read(File.join(PlaiTestr.reports_dir, "#{runner.session_id}.md"))

  before do
    PlaiTestr.games_dir     = File.join(tmp, 'games')
    PlaiTestr.sessions_dir  = File.join(tmp, 'sessions')
    PlaiTestr.reports_dir   = File.join(tmp, 'reports')
    allow(PlaiTestr::Agents::OllamaClient).to receive(:new).and_return(client)
    allow(client).to receive(:chat).and_return(chat('{"choice":2,"reasoning":"two is more","plan":"add fast"}'))
  end

  after do
    PlaiTestr.games_dir = nil
    PlaiTestr.reset_config!
    FileUtils.rm_rf(tmp)
  end

  it 'records the seed, player model and host for a new session' do
    expect(runner.data).to include('seed' => 7, 'player_model' => 'p-model', 'think' => false, 'host' => Socket.gethostname)
  end

  it 'builds a menu entry with option' do
    expect(runner.option('Play 3♣', public: 'played 3♣', play: { value: 42 }))
      .to eq(label: 'Play 3♣', public: 'played 3♣', action: { play: { value: 42 } })
  end

  it 'accepts hand-written moves with string keys and hands the action over with symbol keys' do
    runner.moves = [{ 'label' => 'Add one', 'action' => { 'add' => { 'value' => 1 } } }, { 'label' => 'Add two', 'action' => { 'add' => { 'value' => 2 } } }]
    runner.setup
    runner.play_turn

    expect(runner.data['total']).to eq(2)
    expect(runner.menu('Alice').first).to eq(label: 'Add one', action: { add: { value: 1 } })
  end

  it 'applies the chosen move and logs it with the reasoning and plan' do
    runner.setup
    runner.play_turn

    expect(runner.data['total']).to eq(2)
    expect(runner.turn_log.last).to include('player' => 'Alice', 'label' => 'Add two', 'choice' => 2, 'plan' => 'add fast', 'fallback' => false,
                                            'decider' => 'LLM', 'action' => { 'add' => { 'value' => 2 } })
  end

  it 'labels each turn with the phase the game reports, in the console and the log' do
    runner.define_singleton_method(:turn_phase) { |_p| 'Round 1 · draft' }
    runner.setup
    runner.play_turn

    expect(out.string).to match(/Turn 1 — Alice · Round 1 · draft \(2 options\)/)
    expect(runner.turn_log.last['phase']).to eq('Round 1 · draft')
  end

  it "logs a move's short log text instead of its full label when it has one" do
    runner.moves = [runner.option('Add one: a very long card text the model needs', log: '➕ one', add: { value: 1 }), runner.option('Add two', add: { value: 2 })]
    runner.setup
    allow(client).to receive(:chat).and_return(chat('{"choice":1,"reasoning":"r","plan":"p"}'))
    runner.play_turn

    expect(out.string).to match(/🧠 LLM -> ➕ one\n/)
    expect(runner.turn_log.last).to include('label' => 'Add one: a very long card text the model needs', 'log' => '➕ one')
  end

  it 'applies a single legal move without asking the model' do
    runner.moves = [runner.option('Add one', add: { value: 1 })]
    runner.setup

    expect(client).not_to receive(:chat)
    runner.play_turn

    expect(runner.turn_log.last).to include('label' => 'Add one', 'auto' => true, 'attempts' => 0)
  end

  it 'asks for several moves at once on a pick turn and applies their values together' do
    runner.moves = %w[a b c].map { |v| runner.option("Pick #{v}", keep: { value: v }) }
    runner.pick  = [1, 2]
    runner.setup
    allow(client).to receive(:chat).and_return(chat('{"choices":[3,1],"reasoning":"r","plan":"p"}'))
    runner.play_turn

    expect(runner.data['picked']).to eq(%w[c a])
    expect(runner.turn_log.last).to include('choice' => [3, 1], 'label' => 'Pick c; Pick a', 'action' => { 'keep' => { 'value' => %w[c a] } })
  end

  it 'takes every option without asking when a pick must take them all' do
    runner.moves = %w[a b].map { |v| runner.option(v, keep: { value: v }) }
    runner.pick  = [2, 2]
    runner.setup

    expect(client).not_to receive(:chat)
    runner.play_turn

    expect(runner.data['picked']).to eq(%w[a b])
  end

  it 'shows recent events from the event log' do
    runner.setup
    runner.play_turn

    expect(runner.recent_events_for('Bob')).to eq(['Alice acted'])
  end

  it 'asks each player the debrief questions once and stores the answers' do
    runner.define_singleton_method(:debrief_questions) { |_p| ['Any problems?'] }
    allow(client).to receive(:chat).with(hash_including(format: hash_including('required' => ['q1'])))
                                   .and_return(chat('{"q1":"none really"}'))

    runner.send(:run_debrief)
    runner.send(:run_debrief)

    expect(client).to have_received(:chat).with(hash_including(format: hash_including('required' => ['q1']))).twice
    expect(runner.data['debrief']['Alice']).to eq([{ 'question' => 'Any problems?', 'answer' => 'none really' }])
  end

  describe 'debrief summary' do
    before do
      runner.define_singleton_method(:debrief_questions) { |_p| ['Any problems?'] }
      runner.define_singleton_method(:botrun_stats) { { 'added' => { 'Alice' => 3 } } }
      allow(client).to receive(:chat).with(hash_including(format: hash_including('required' => ['q1']))).and_return(chat('{"q1":"none"}'))
    end

    def debrief_prompt(player)
      prompts = []
      allow(client).to receive(:chat).with(hash_including(format: hash_including('required' => ['q1']))) do |args|
        prompts << args[:messages].last[:content]
        chat('{"q1":"none"}')
      end
      runner.run
      prompts[runner.game_state.players.index(player)]
    end

    it 'puts the outcome, the game facts, and the player\'s own decisions and plans ahead of the final position' do
      prompt = debrief_prompt('Alice')

      expect(prompt).to include('OUTCOME:', 'You won', 'Final scores: You', 'GAME FACTS', "added:\n  Alice: 3", 'YOUR DECISIONS:', '1 decisions: 1 by you',
                                'YOUR PLAN AS IT CHANGED', 'add fast')
      expect(prompt.index('GAME SUMMARY')).to be < prompt.index('YOUR FINAL POSITION')
    end

    it 'debriefs with its own model and thinking when asked' do
      thinker = runner_for(models: { player: 'p-model', debrief: 'big-model', debrief_think: true })
      thinker.define_singleton_method(:debrief_questions) { |_p| ['Any problems?'] }
      thinker.run

      expect(client).to have_received(:chat).with(hash_including(model: 'big-model', think: true)).twice
      expect(thinker.data).to include('debrief_model' => 'big-model', 'debrief_think' => true)
      expect(File.read(File.join(PlaiTestr.reports_dir, "#{thinker.session_id}.md"))).to include('_Answered by big-model (thinking)._')
    end

    it 're-debriefs a completed session, keeping the earlier answers' do
      runner.run
      again = game.runner_class.redebrief(game, runner.session_id, models: { debrief: 'big-model' }, out: out)
      again.define_singleton_method(:debrief_questions) { |_p| ['Any problems?'] }
      again.debrief!

      checkpoint = JSON.parse(File.read(File.join(PlaiTestr.sessions_dir, runner.session_id, 'state.json')))
      expect(checkpoint['status']).to eq('completed')
      expect(checkpoint.dig('game_state', 'data', 'debrief_model')).to eq('big-model')
      expect(checkpoint.dig('game_state', 'data', 'debrief_history').first['debrief_model']).to eq('p-model')
      expect(report).to include('_Answered by big-model._')
    end

    it 'keeps the game\'s warnings when a re-debrief rebuilds the report' do
      runner.setup
      runner.send(:warning, 'menu had a duplicate option')
      runner.play_turn until runner.game_over?
      runner.send(:finish)

      again = game.runner_class.redebrief(game, runner.session_id, out: out)
      again.define_singleton_method(:debrief_questions) { |_p| ['Any problems?'] }
      again.debrief!

      expect(report).to include('menu had a duplicate option')
      expect(again.game_state.serialize_for('Alice')['data']).not_to have_key('warnings')
    end

    it 'refuses to re-debrief a session that is not complete' do
      runner.setup
      runner.play_turn
      runner.send(:save_checkpoint, 'interrupted')

      expect { game.runner_class.redebrief(game, runner.session_id) }.to raise_error(PlaiTestr::SessionError, /not complete/)
    end
  end

  it 'plays to the end, checkpoints as completed, and writes a report' do
    runner.run

    checkpoint = JSON.parse(File.read(File.join(PlaiTestr.sessions_dir, runner.session_id, 'state.json')))

    expect(runner.status).to eq('completed')
    expect(checkpoint['status']).to eq('completed')
    expect(checkpoint['turn_log'].first).not_to have_key('state_after')
    expect(report).to include('**Winner: Alice**', '## Model reliability', '## Speed', '## Turn log', '| **Model settings** | context_size 8192')
    expect(report).to match(/\| \*\*Wall time\*\* +\| 0m 0\ds +\|/)
  end

  it 'leaves the signal handlers as they were after a run' do
    handler = proc {}
    previous = trap('INT', handler)
    runner.run

    expect(trap('INT', previous)).to be(handler)
  end

  describe 'resuming' do
    it 'keeps the thinking setting of the session' do
      thinking = runner_for(models: { player: 'p-model', think: true })
      thinking.setup
      thinking.send(:save_checkpoint, 'interrupted')

      expect(PlaiTestr::Agents::PlayerAgent).to receive(:new).twice.with(hash_including(think: true)).and_call_original
      game_class.resume(game, thinking.session_id, out: out)
    end

    it 'restores the game without running setup again' do
      runner.setup
      runner.play_turn
      runner.send(:save_checkpoint, 'interrupted')

      resumed = game_class.resume(game, runner.session_id, out: out)

      expect(resumed.data['total']).to eq(2)
      expect(resumed.seed).to eq(7)
    end
    
    it 'adds the wall time of each sitting' do
      runner.setup
      runner.data['wall_seconds'] = 125
      runner.send(:save_checkpoint, 'interrupted')
    
      resumed = game_class.resume(game, runner.session_id, out: out)
      resumed.moves = runner.moves
      resumed.run
    
      expect(File.read(resumed.report_path)).to match(/\| \*\*Wall time\*\* +\| 2m 0[56]s +\|/)
      expect(resumed.game_state.serialize_for('Alice')['data']).not_to have_key('wall_seconds')
    end

    it 'refuses a session whose game has changed since it was saved' do
      runner.setup
      runner.send(:save_checkpoint, 'interrupted')
      File.write(File.join(game.data_dir, 'rules.json'), JSON.generate('game' => { 'name' => 'Counting Game', 'version' => '1.1' }))

      expect { game_class.resume(game, runner.session_id, out: out) }.to raise_error(PlaiTestr::SessionError, /has changed/)
    end

    it 'gives each decision the same random draws whether or not the game was interrupted' do
      allow(client).to receive(:chat).and_return(chat('{"choice":1,"reasoning":"r","plan":"p"}'))
      straight = runner_for
      straight.setup
      3.times { straight.play_turn }

      first = runner_for
      first.setup
      first.play_turn
      first.send(:save_checkpoint, 'interrupted')
      resumed = game_class.resume(game, first.session_id, out: out)
      resumed.moves = first.moves
      2.times { resumed.play_turn }

      expect(first.draws + resumed.draws).to eq(straight.draws)
    end
  end

  describe 'when the model never gives a valid answer' do
    before { allow(client).to receive(:chat).and_return(chat('nonsense')) }

    it "plays the bot's choice and tags the event for the acting player" do
      runner.script = { 'choice' => 1, 'rule' => 'take_one' }
      runner.setup
      runner.play_turn

      expect(runner.turn_log.last).to include('choice' => 1, 'decider' => 'BOT', 'rule' => 'take_one', 'fallback' => true)
      expect(runner.turn_log.last).not_to have_key('bot_rule')
      expect(runner.recent_events_for('Alice')).to eq(['BOT: Alice acted'])
      expect(runner.recent_events_for('Bob')).to eq(['Alice acted'])
    end

    it 'picks at random when there is no bot rule, without changing the game draws' do
      runner.setup
      runner.play_turn
      reference = runner_for(models: {}, mode: 'bot')
      reference.setup
      reference.play_turn

      expect(runner.turn_log.last).to include('decider' => 'RNG', 'fallback' => true)
      expect(runner.draws).to eq(reference.draws)
      expect(out.string).to include('🎲 RNG ->', '[FALLBACK]')
    end
  end

  describe 'menu checks' do
    before { runner.setup }

    it 'rejects a move with a misspelled key before asking the model' do
      runner.moves = [{ 'lable' => 'Oops', 'action' => { 'add' => { 'value' => 1 } } }, runner.option('Add one', add: { value: 1 })]

      expect(client).not_to receive(:chat)
      expect { runner.play_turn }.to raise_error(PlaiTestr::MoveError, /option 1: unknown key\(s\) :lable/)
    end

    it 'rejects an action that is not a single name with params' do
      runner.moves = [{ 'label' => 'Add', 'action' => { 'action' => 'add', 'parameters' => {} } }, runner.option('Add one', add: { value: 1 })]

      expect { runner.play_turn }.to raise_error(PlaiTestr::MoveError, /exactly one name with params/)
    end

    it 'needs a value in each move on a pick turn' do
      runner.moves = [runner.option('Keep a', keep: {}), runner.option('Keep b', keep: { value: 'b' })]
      runner.pick  = [1, 1]

      expect { runner.play_turn }.to raise_error(PlaiTestr::MoveError, /need a value/)
    end

    it 'warns about repeated labels without stopping' do
      runner.moves = [runner.option('Add', add: { value: 1 }), runner.option('Add', add: { value: 2 })]
      allow(runner).to receive(:warn)
      runner.play_turn

      expect(runner.warnings).to include(/repeats the label\(s\) "Add"/)
    end
  end

  describe 'the decision limit' do
    it "ends the game with no winner at the game's own limit" do
      limited = build_game(game_class, max_decisions: 1)
      capped  = game_class.new(game: limited, players: players, models: {}, seed: 7, mode: 'bot', persist: false, out: out)
      capped.moves = [capped.option('Add nothing', add: { value: 0 }), capped.option('Also nothing', add: { value: 0 })]
      capped.play_out

      expect(capped.game_state.status).to include('game_over' => true, 'winner' => nil, 'end_reason' => 'decision_limit_reached')
      expect(capped.botrun_result['decisions']).to eq(1)
    end

    it 'uses the app backstop when the game sets none' do
      PlaiTestr.configure { |c| c.max_decisions = 2 }
      capped = runner_for(models: {}, mode: 'bot', persist: false)
      capped.moves = [capped.option('Add nothing', add: { value: 0 }), capped.option('Also nothing', add: { value: 0 })]
      capped.play_out

      expect(capped.game_state.turn).to eq(2)
      expect(capped.game_state.status['end_reason']).to eq('decision_limit_reached')
    end
  end

  describe 'personas' do
    let(:game) do
      build_game(game_class, personas: <<~YAML)
        basic_strategy: &basics
          count: Count before you add.
        personas:
          patient:
            <<: *basics
            goal: Add one at a time.
          bold:
            <<: *basics
            count: Never count; add.
      YAML
    end

    it 'gives each player a persona and sends its strategy, with overrides, in the system prompt' do
      runner.run

      prompt = include(hash_including(content: include("YOUR STRATEGY (follow it in every decision): Patient\n- Count before you add.\n- Add one at a time.")))
      expect(client).to have_received(:chat).with(hash_including(messages: prompt)).at_least(:once)
      expect(runner.persona_for(runner.game_state.players.find { |p| runner.persona(p) == 'bold' })).to eq("Bold\n- Never count; add.")
      expect(report).to match(/\| \*\*Personas\*\* +\|/)
    end

    it 'shows persona names in the console and the report, and keeps player ids in the log data' do
      runner = runner_for(personas: %w[patient bold])
      runner.run

      expect(runner.display_names).to eq('Alice' => 'Patient', 'Bob' => 'Bold')
      expect(out.string).to include('Turn 1 — Patient')
      expect(File.read(runner.report_path)).to include('**Winner: Patient**', '**1. Patient:**').and match(/\| \*\*Players\*\* +\| Patient \(Alice\), Bold \(Bob\) +\|/)
      expect(runner.turn_log.first['player']).to eq('Alice')
    end

    it 'adds the player id when two players share a persona' do
      expect(runner_for(personas: %w[bold bold]).display_names).to eq('Alice' => 'Bold (Alice)', 'Bob' => 'Bold (Bob)')
    end

    it 'refuses an unknown persona' do
      expect { runner_for(personas: %w[timid *]) }.to raise_error(PlaiTestr::PersonaError, /Unknown persona "timid"/)
    end
  end

  describe 'modes' do
    def build(mode, persist: true)
      runner_for(mode: mode, persist: persist)
    end

    it 'plays an obvious scripted move in hybrid mode without asking the model' do
      hybrid = build('hybrid')
      hybrid.script = { 'choice' => 1, 'rule' => 'take_one', 'obvious' => true }
      expect(client).not_to receive(:chat)
      hybrid.setup
      hybrid.play_turn

      expect(hybrid.turn_log.last).to include('choice' => 1, 'decider' => 'BOT', 'rule' => 'take_one', 'obvious' => true)
    end

    it "marks each decision as the bot's or the model's in the console" do
      hybrid = build('hybrid')
      hybrid.setup
      hybrid.script = { 'choice' => 1, 'rule' => 'take_one', 'obvious' => true }
      hybrid.play_turn
      hybrid.script = nil
      hybrid.play_turn

      expect(out.string).to include('🤖 BOT -> Add one [rule: take_one]', '🧠 LLM -> Add two')
    end

    it "asks the model when the script is only a default, and records the bot's choice beside it" do
      hybrid = build('hybrid')
      hybrid.script = { 'choice' => 1, 'rule' => 'guess' }
      hybrid.setup
      hybrid.play_turn

      expect(hybrid.turn_log.last).to include('choice' => 2, 'decider' => 'LLM', 'bot_choice' => 1, 'bot_rule' => 'guess', 'bot_obvious' => false)
    end

    it 'never calls the model in bot mode, taking option 1 when there is no rule' do
      bot = build('bot', persist: false)
      expect(client).not_to receive(:chat)
      bot.play_out

      expect(bot.botrun_result).to include('seed' => 7, 'winner' => 'Alice', 'decisions' => 3, 'rules' => { 'none' => 3 })
      expect(Dir.exist?(File.join(PlaiTestr.sessions_dir, bot.session_id))).to be false
    end

    it 'lets the model decide when a bot rule fails, so one bad rule cannot end a model game' do
      hybrid = build('hybrid')
      hybrid.define_singleton_method(:bot_choice) { |*, **| raise 'bad rule' }
      allow(hybrid).to receive(:warn)
      hybrid.setup
      hybrid.play_turn

      expect(hybrid.turn_log.last).to include('choice' => 2, 'decider' => 'LLM')
      expect(hybrid.warnings.first).to include('bad rule')
    end

    it 'rejects an unknown mode' do
      expect { build('robot') }.to raise_error(PlaiTestr::UsageError, /Unknown mode "robot"/)
    end

    it 'reports how often the model agreed with the bot' do
      runner.script = { 'choice' => 2, 'rule' => 'take_two', 'obvious' => true }
      runner.run

      expect(report).to include('## Bot agreement').and match(/\| take_two +\| obvious +\| 2 +\| 2 +\| 100% +\|/)
    end
  end
end
