require 'plai_testr'

# The checks every PlAI Testr game must pass, shipped with the gem so a gem upgrade brings
# new checks to every game without editing it. In a game's spec:
#
#   RSpec.describe MyGame::Session::Runner do
#     it_behaves_like 'a PlAI Testr game', 'my_game'
#   end
#
# Options: seeds: (default 1..3) games per player count; pending: 'reason' marks the checks
# pending while a new game is being built (the skeleton starts with it).
RSpec.shared_examples 'a PlAI Testr game' do |name, seeds: (1..3).to_a, pending: nil|
  before { skip(pending) if pending }

  let(:game) { PlaiTestr.load(name) }

  let(:seatings) do
    range = game.rules.dig('game', 'player_count')
    counts = range ? (range['min']..range['max']).to_a : [game.players.length]
    counts.map { |count| range ? Array.new(count) { |i| "Player #{i + 1}" } : game.players }
  end

  def plai_runner(players, seed)
    game.runner_class.new(game: game, players: players, seed: seed, mode: 'bot', persist: false, out: StringIO.new, echo_warnings: false)
  end

  def plai_label(players, seed) = "#{players.length} players, seed #{seed}"

  it 'plays bot games to an ending at every player count' do
    seatings.each do |players|
      results = PlaiTestr::Botrun.new(game: game, players: players, seeds: seeds).run

      results.each do |result|
        expect(result['error']).to be_nil, "#{plai_label(players, result['seed'])}: #{result['error']}"
        expect(result['end_reason']).not_to be_nil, "#{plai_label(players, result['seed'])}: no end_reason"
      end
    end
  end

  it 'builds every turn prompt and, at the end, every debrief prompt' do
    seatings.each do |players|
      seeds.each do |seed|
        runner = plai_runner(players, seed)
        runner.setup
        until runner.game_over?
          player = runner.next_player
          %i[rules_text_for view_text_for recent_events_for persona_for turn_phase prompt_note_for].each { |hook| runner.public_send(hook, player) }
          runner.play_turn
        end

        players.each do |player|
          facts = runner.debrief_facts(player)
          expect(facts).to be_a(Hash).and(satisfy { |f| f.any? }), "#{plai_label(players, seed)}: debrief_facts(#{player}) is empty"
          expect(runner.debrief_summary(player)).to include('GAME FACTS')
          runner.debrief_view_for(player)
        end
      end
    end
  end

  it 'keeps its state JSON-safe, so checkpoints save it exactly' do
    seatings.each do |players|
      runner = plai_runner(players, seeds.first)
      runner.setup
      until runner.game_over?
        runner.play_turn
        state = runner.game_state.serialize
        expect(JSON.parse(JSON.generate(state))).to eq(state), "#{plai_label(players, seeds.first)}: state changed in a JSON round trip at decision #{state['turn']}"
      end
    end
  end

  it 'resumes from a mid-game checkpoint to the same result' do
    seatings.each do |players|
      seed     = seeds.first
      straight = plai_runner(players, seed).play_out
      halfway  = straight.game_state.turn / 2

      first = plai_runner(players, seed)
      first.setup
      first.play_turn while first.game_state.turn < halfway && !first.game_over?
      checkpoint = JSON.parse(JSON.generate('game_state' => first.game_state.serialize, 'turn_log' => first.turn_log))

      resumed = plai_runner(players, seed)
      resumed.send(:restore, checkpoint)
      resumed.play_turn until resumed.game_over?

      expect([resumed.game_state.status, resumed.game_state.scores]).to eq([straight.game_state.status, straight.game_state.scores]),
                                                                       "#{plai_label(players, seed)}: resuming at decision #{halfway} changed the result"
    end
  end

  it "hides every player's hand from the others" do
    seatings.each do |players|
      runner = plai_runner(players, seeds.first)
      runner.setup
      [0, 5].each do |turns|
        turns.times { runner.play_turn unless runner.game_over? }
        players.each do |observer|
          (players - [observer]).each do |other|
            seen = runner.game_state.serialize_for(observer)['player_states'][other]
            expect(seen).not_to have_key('hand'), "#{observer} can see #{other}'s hand"
          end
        end
      end
    end
  end
end
