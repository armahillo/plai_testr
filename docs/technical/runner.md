# The runner

A game's runner subclasses `PlaiTestr::Session::Runner`. The gem owns the decision loop; the runner supplies the rules through *hooks*, public methods the loop calls.

## The decision loop

Each decision:

1. `next_player` says who acts.
2. `@rng` is reseeded for this decision (see [Randomness](#randomness)).
3. `legal_moves(player)` builds the menu, and `pick_range(player)` says whether it's a choose-one or choose-several decision. The gem checks the menu (see [Moves](#moves-and-actions)).
4. Someone decides:
   - A menu with one option is applied without asking anyone.
   - Otherwise the model gets the persona, rules text, view, recent events and the numbered menu, and replies with a choice, its reasoning and its plan. In `--mode hybrid`, an *obvious* bot move is played without asking the model. In `--mode bot` and botruns, the bot decides.
5. `apply_action_effects(player, action)` applies the chosen move.
6. The game is saved, and the loop repeats until `game_over?`.

Then each model player is debriefed (see [Debrief](debrief.md)) and the report is written.

Registration ties the runner to the game's other classes, in `lib/<name>.rb`:

```ruby
PlaiTestr.register('hearts',
                   runner_class:        Hearts::Session::Runner,
                   game_state_class:    Hearts::State::GameState,
                   botrun_report_class: Hearts::Reporter::BotrunReport,   # optional, see Reports
                   players:             ['Player 1', 'Player 2', 'Player 3', 'Player 4'],
                   recent_events:       12,                                # log lines per prompt (default 8)
                   max_decisions:       5_000,                             # this game's decision limit
                   model_settings:      { context_size: 12_288 })          # this game's model settings
```

`players` is the default seating when `rules.json` has no `player_count`. `comparison_class:` swaps in a subclass of `Reporter::ModelComparison` for `compare`.

## Hooks

| Hook | Required | Purpose |
|---|---|---|
| `setup` | yes | Build the starting state. Not called on resume. |
| `legal_moves(player)` | yes | The menu: an array of `option(...)` entries |
| `apply_action_effects(player, action)` | yes | Apply the chosen move's action to `@game_state` |
| `view_text_for(player)` | expected | The player's view of the game, as text |
| `debrief_facts(player)` | expected | Engine-counted facts for the debrief, as a Hash (default: `botrun_stats`; see [Debrief](debrief.md)) |
| `next_player` | | Who acts next (default: alternate) |
| `pick_range(player)` | | `[min, max]` to pick several options at once |
| `game_over?` | | Default: `status['game_over']` |
| `turn_phase(player)` | | Short step label for the console and report |
| `rules_text_for(player)` | | Rules text (default: the game's `data/rules.md`; call `super` to extend it) |
| `prompt_note_for(player)` | | A one-off note for this prompt |
| `recent_events_for(player)` | | Recent events from the event log (default: the last 8 this player may see; `recent_events:` in `register`) |
| `log_turn`, `log_turn_name` | | The number stamped on log entries and its name (default: the decision number) |
| `persona_for(player)` | | Strategy text for the system prompt (default: built from `personas.yml`) |
| `display_name(player)` | | Name in the console and reports (default: the persona's key, title-cased, else the player id) |
| `bot_choice(player, moves, pick: nil)` | | Bot rules (see [Personas and bots](personas-and-bots.md)) |
| `think_about?(player)` | | With `--think`: whether this turn gets thinking (default: every turn) |
| `debrief_questions(player)` | | End-of-game feedback questions |
| `debrief_view_for(player)` | | The final position the debrief reads (default: the result, final scores, `view_text_for` and the player's visible log) |
| `debrief_summary(player)` | | Built by the gem, not overridden: the summary that opens each debrief prompt |
| `report_sections`, `report_debrief?` | | Extra report sections; false to render the debrief yourself (see [Reports](reports.md)) |
| `botrun_stats` | | Game-specific numbers for one botrun game (see [Reports](reports.md)) |

Hooks are public, so specs can call them directly; the helpers below are private. Put your own helpers below `private` too. Avoid public helper names that could collide with future hooks.

### Helpers

Available inside hooks:

| Helper | |
|---|---|
| `option(label, public:, log:, **action)` | Build a menu entry (see below) |
| `menu(player)` | The menu as the runner sees it, after checking |
| `data` | `@game_state.data`, the game's own state |
| `log(text, to: nil)` | Add an event to the event log; `to:` makes it private to one player |
| `event_log` | The log itself |
| `players`, `pstate(player)` | Player names in seat order; one player's `PlayerState` |
| `whose(player, viewer)` | "You" when the player is the viewer, else the player's name, for view text |
| `tally(player, key, amount = 1)` | Count something per player in `data['tally']` (for facts and reports) |
| `sole_leader(scores = @game_state.scores)` | The single highest scorer, or `nil` on a tie |
| `persona(player)`, `persona_name(player)`, `bot_strategy_for(player)` | The player's persona key, its display name, its bot parameters |
| `@rng`, `@rules`, `@game_state`, `out` | Random generator, parsed `rules.json`, state, console output |

## Moves and actions

```ruby
def legal_moves(player)
  hand(player).map { |card| option("Play #{card['name']}", public: "played #{card['name']}", play: { value: card['uid'] }) }
end

def apply_action_effects(player, action)
  case action
  in { play: { value: uid } }  then play(player, uid)
  in { pass: { value: uids } } then pass(player, uids)
  end
end
```

- `label` (the first argument) is what the acting player sees; `public:` is what the others see; `log:` is a shorter console line.
- The action has exactly one name (`play:` above). `value:` is its main parameter; others sit beside it (`play: { value: uid, target: 2 }`).
- Moves and actions have symbol keys, so `apply_action_effects` and the bot can pattern-match them. A hand-written move with string keys is converted.
- On a pick turn (`pick_range` returns `[min, max]`) the chosen values arrive together: `{ pass: { value: [42, 17, 9] } }`.
- Every menu is checked before it's used. A misspelled key or a malformed action raises `PlaiTestr::MoveError` naming the hook, player, decision and option; repeated labels get a warning.

### Writing good menus

Small local models play well only when the engine does the bookkeeping:

- **The engine lists the legal moves; the model picks a number.** Never ask the model to name a card or check legality.
- **Put engine-computed facts on options, never advice.** "Discard 9♥ (deadwood after: 31)" is a fact; "Discard 9♥ (best)" decides for the model.
- **Generate views from state**, never hand-written summaries, which go stale or leak hidden information.
- **Keep menus short.** Merge equivalent options (identical cards, interchangeable targets); split a huge decision into steps.
- **Hide safety caps.** Turn or hand limits that stop runaway games must not appear in views or rules text, or models play for the cap.
- **Scope long rules.** Override `rules_text_for` to send only the sections the current step needs.

## Steps

Most games model a turn as a small state machine in `data['step']` (`draw` → `discard` → next player). `legal_moves` and `apply_action_effects` switch on the step, and `turn_phase` usually shows it. For decisions inside decisions (an attack the defender may answer, a triggered effect), use [FrameQueue](frame-queue.md).

## Ending the game

Set the status when the game ends:

```ruby
@game_state.apply_changes('status' => { 'game_over' => true, 'winner' => leader, 'end_reason' => 'points' })
```

`winner` is `nil` for a tie. `end_reason` is a short key, shown in reports and counted by botruns.

## Randomness

Use `@rng` for all randomness (`deck.shuffle(random: @rng)`, `@rng.rand(6) + 1`). It is reseeded for each decision from the game's seed and the decision number, so the same seed and the same choices always give the same game, interrupted or not. Any other source of randomness breaks replays and resume.

## Limits and fallbacks

- Every game stops at a decision limit, ending with `end_reason: 'decision_limit_reached'` and no winner, so a buggy game can't run forever. Set `max_decisions:` in `register`; otherwise the app's `max_decisions` applies.
- When the model never gives a valid answer after retries, the bot's choice is played instead (or a random legal move, from a separate generator, when the bot has none), and the turn is flagged in the report.
- A bot rule that raises in a model game is skipped with a warning; in a botrun it is recorded as a crash for that seed.

## The event log

`log(text)` records a public event; `log(text, to: player)` a private one ("You drew the 2♠"). Each entry is stamped with `log_turn`: the decision number by default. A game with rounds returns its round number, with `log_turn_name` its word for it ("round", "hand"). `recent_events_for` shows each player the last events they may see, and the debrief view shows the player's whole visible log.

## Checking a prompt

Read what the model sees before running a model game:

```ruby
# bundle exec ruby -e '...'
require 'plai_testr'
game   = PlaiTestr.load('hearts')
runner = game.runner_class.new(game: game, players: game.players, seed: 1, mode: 'bot', persist: false, out: StringIO.new)
runner.setup
5.times { runner.play_turn }
player = runner.next_player
puts runner.persona_for(player), runner.view_text_for(player), runner.menu(player).map { |m| m[:label] }

runner.play_turn until runner.game_over?
puts runner.debrief_summary(player), runner.debrief_view_for(player)
```
