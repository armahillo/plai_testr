# Specs

Each game's specs are in `games/<name>/spec/` and run with [RSpec](https://rspec.info):

```sh
bundle exec rspec                       # every game
bundle exec rspec games/hearts/spec     # one game
```

They need no model and run in seconds, so run them after every change.

## The standard checks

Every game includes the gem's shared checks (from `plai_testr/rspec`, which the app's `spec_helper` requires):

```ruby
RSpec.describe Hearts::Session::Runner do
  it_behaves_like 'a PlAI Testr game', 'hearts'
end
```

At every player count in `rules.json`, over a few seeds, they check that:

- bot games reach an ending
- every turn prompt builds, and every debrief prompt at the end (botruns never build prompts, so this is the only check before a model game)
- state survives a JSON round trip
- resuming from a mid-game checkpoint gives the same result
- no player's prompt shows another player's hand

Options: `seeds: [1, 2, 3]` sets which games are played; `pending: 'reason'` holds the checks while a new game is being built (the generated spec starts with it).

The checks come from the installed gem, so upgrading the gem adds checks without editing the game. Don't copy them into a game.

## Rules specs

Rules specs drive the runner directly. Build it without saving anything, set up a situation, and check the menu or the effects:

```ruby
RSpec.describe Hearts::Session::Runner do
  let(:game)   { PlaiTestr.load('hearts') }
  let(:runner) { described_class.new(game: game, players: game.players, seed: 1, mode: 'bot', persist: false, out: StringIO.new) }
  let(:state)  { runner.game_state }
  let(:deck)   { PlaiTestr::Deck.build(game.rules) }

  def cards(*names) = names.map { |name| deck.find { |c| c['name'] == name } }

  def labels(player) = runner.legal_moves(player).map { |m| m[:label] }

  before { runner.setup }

  it 'follows the suit led when it can' do
    state.data.merge!('step' => 'play', 'tricks' => 1, 'active' => 'Player 2', 'trick' => [{ 'player' => 'Player 1', 'card' => cards('9♣').first }])
    state.player_state('Player 2').hand.replace(cards('5♥', '7♣', 'K♣'))

    expect(labels('Player 2')).to eq(['Play 7♣ (stays under the 9♣)', 'Play K♣ (wins the trick so far)'])
  end
end
```

Hooks are public, so specs call them directly (the runner's private helpers such as `pstate` aren't; use `runner.game_state`). `runner.play_turn` and `runner.play_out` play one decision or the rest of the game. Write rules specs before any model plays: rules bugs are cheapest here.

Add specs for what's specific to the game too: card counts, report sections, bot rules (`spec/bot_spec.rb`). If `data/` is copied from another repository, add a spec that fails when the copy is behind.
