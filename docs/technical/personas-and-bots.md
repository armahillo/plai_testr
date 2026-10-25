# Personas and bots

A **persona** is a play style. For model players it is strategy text in the system prompt; for bots, a set of parameters the bot rules read. Each player gets one persona per game, so a botrun or a set of model games can compare styles. A **bot** is the game's scripted decision-maker, `bot_choice`.

Both are optional: a game without personas plays everyone the same way, and a game without a bot can't botrun (and model games fall back to random moves when a model never answers validly).

## `data/personas.yml`

```yaml
basic_strategy: &basics
  pass_dangerous: Pass away the Q♠, high spades (A♠, K♠) and high hearts unless you have many low spades to protect them.
  duck: Play just under the winning card to avoid taking tricks that carry points.

personas:
  safe_player:
    <<: *basics
    goal: Take as few points as you can in every hand. Never win a trick you could lose.
  moon_shooter:
    <<: *basics
    goal: Watch for a hand strong enough to take every heart and the Q♠. Go for it when you can; otherwise play safe.
    pass_dangerous: Keep high hearts and the Q♠ when your hand is strong enough to take every trick.
```

- `basic_strategy` is advice every player gets. `<<: *basics` merges it into each persona.
- Each key under `personas` is a persona's name, used with `--personas`. Every field under it is shown to the model. Reusing a `basic_strategy` key overrides that item; a new key adds one.
- The gem reads only `basic_strategy` and `personas`. Other top-level keys are yours, for a custom `persona_for`.
- The default `persona_for(player)` builds the system prompt's strategy text from this file; `display_name` shows the persona's name, title-cased, in the console and reports.

Personas are assigned per game: `--personas a,b` in seat order (`*` for random), otherwise at random from the seed. `botrun --personas all` cycles every arrangement of personas across seats, and needs at least as many personas as seats.

Personas shape debrief answers as well as play: a player told to favor a card will praise it. Compare debriefs across personas before concluding anything.

## `data/bots.yml`

```yaml
bot_strategy: &bot_defaults
  pass_dangerous: true
  win_clean_tricks: true

bots:
  safe_player:
    <<: *bot_defaults
    win_clean_tricks: false
```

`bot_strategy` holds the defaults; `bots` holds per-persona overrides, keyed by the persona names in `personas.yml` (an unknown name is an error). The bot reads them with `bot_strategy_for(player)`. The model never sees this file.

## `bot_choice`

`bot_choice(player, moves, pick: nil)` lives in `lib/<name>/bot.rb`, a module included in the runner. It gets the checked menu and returns `nil` (no rule applies) or:

```ruby
{ 'choice' => 2, 'rule' => 'duck', 'obvious' => false }        # choice is 1-based
{ 'choices' => [1, 4, 5], 'rule' => 'pass_dangerous', 'obvious' => false }   # pick turns
```

- **`rule`** names the idea behind the move (`duck`, `dump_queen`, `shed_deadwood`). Botrun reports count how often each rule was used; `none` means the bot had no rule and took option 1.
- **`obvious`** marks a move that is never worse than any alternative. `--mode hybrid` plays obvious moves without asking the model, and every model game's report scores the model against them (*Bot agreement*). Mark a move obvious only when it really is; a wrong mark skews both.
- Find options by pattern-matching their actions, and return a 1-based choice: `i = moves.index { |m| m[:action] in { play: { value: ^uid } } }` then `{ 'choice' => i + 1, ... }`.

Keep the bot simple and readable. It is a baseline for balance numbers and a crash test, not a strong player. Bot results describe the bot's strategy; confirm a surprising one with a few model games.

### Where the bot is used

- **Botruns and `--mode bot`**: the bot makes every decision.
- **`--mode hybrid`**: the bot makes its obvious decisions; the model makes the rest.
- **Model games**: the turn log records the bot's choice next to the model's, for *Bot agreement*. When the model never answers validly, the bot's choice is played.
