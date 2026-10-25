# State

Everything a game knows lives in `@game_state` ([`game_state.rb`](../../lib/plai_testr/state/game_state.rb)), so the gem can save it after every decision and restore it exactly.

## Game state

`@game_state` holds:

- `turn`: decisions so far
- `players`: player names, in seat order
- `status`: owned by the runner. Set `game_over`, `winner` and `end_reason` when the game ends, with `@game_state.apply_changes('status' => {...})`.
- `data`: the game's own state

Each `player_state(name)` ([`player_state.rb`](../../lib/plai_testr/state/player_state.rb)), or `pstate(name)` in the runner, holds `score`, `hand` and its own `data`.

### Rules for `data`

- **Plain JSON values only**: hashes with string keys, arrays, strings, numbers, booleans, `nil`. Saving is a JSON dump, so anything else (symbols, objects, sets) breaks resume.
- **Stable ids.** Give every card a `uid` (`Deck.build` does) and keep pile and slot indexes fixed. Never re-index things players refer to.
- **Counters belong in `data` too**, so reports and debrief facts survive a resume (`tally` stores them in `data['tally']`).
- **No instance variables for game state.** They're gone after a resume or when `debrief` rebuilds a report.

### Naming your keys

Subclass `GameState` to give `data` keys readers:

```ruby
module Hearts
  module State
    class GameState < PlaiTestr::State::GameState
      def step  = @data['step']
      def trick = @data['trick'] ||= []
    end
  end
end
```

Register the subclass with `game_state_class:`.

## Hidden information

Each prompt is built from what that player may know. Two methods decide it:

- **`GameState#data_for(observer)`** (private) returns the `data` an observer may see. The default already hides the event log entries meant for other players and the game's internal warnings. Extend it to hide decks or secret choices:

  ```ruby
  def data_for(observer)
    super.except('deck', 'passes').merge('deck_size' => @data['deck'].length)
  end
  ```

- **`PlayerState#serialize_for(observer)`** shows a player their whole state and others only `name`, `score`, `hand_size` and `public_data`. Subclass `PlayerState` and override `public_data` to show opponents more (a face-up card, a pile size), and override `player_state_class` in your `GameState` to use it.

The [standard checks](specs.md) verify that no player's prompt shows another player's hand.

## Checkpoints and resume

After every decision the gem replaces `sessions/<id>/state.json` with the full state, the turn log, and a *fingerprint*: a hash of the game's `data/` and `lib/` files and the gem version. `resume` restores the state and continues from the next decision; since `@rng` is reseeded per decision, the game plays exactly as it would have without the interruption.

`resume` refuses when the fingerprint differs: changed code or data might replay differently, and a mismatched replay would make the report misleading. `debrief` warns instead, since it only rebuilds the debrief.
