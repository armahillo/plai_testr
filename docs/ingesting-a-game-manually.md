# Ingesting a game manually

This guide walks through building a harness for your game by hand: the order to work in and what each step produces. It assumes you can program and can look up Ruby syntax as you go. How each piece works is covered in the [technical reference](technical/); this guide links to it at each step. To have an AI assistant do this instead, see [Ingesting a game with an agent](ingesting-a-game-with-an-agent.md).

If writing the rules was "draw two circles", this is "now draw the rest of the owl". Expect it to take a while, with plenty of trial and error: a simple card game is an afternoon, a game with nested decisions or many card effects much longer. I applaud your curiosity and adventurous spirit!

The two approaches mix well, too: have an agent write the first version, then read and change it yourself. The standard checks catch most mistakes either way. Most of the time goes into the runner. The example games, `games/hearts` and `games/gin_rummy` in your app, are complete harnesses to read alongside this guide.

## How it fits together

The gem runs the game loop: it asks your code who acts next and what their legal moves are, shows the moves to a model or bot as a numbered menu, passes the chosen move back to your code to apply, saves the game, and repeats until your code says the game is over. Then it debriefs the model players and writes the report.

Your game supplies the rules: a **runner** (a subclass of `PlaiTestr::Session::Runner`) that builds menus and applies moves, a **state** class describing what is stored and who may see it, a **bot**, and **data files** for the rules text and components. See [The runner](technical/runner.md) for the loop in detail.

## Step 1: Generate the skeleton

```sh
bundle exec plai_testr generate game blackjack
```

```
games/blackjack/
  lib/blackjack.rb                   Requires the game's files and registers it with PlaiTestr.register
  lib/blackjack/session/runner.rb    The runner: every hook you must write, with comments
  lib/blackjack/state/game_state.rb  The GameState subclass
  lib/blackjack/bot.rb               bot_choice, included in the runner
  data/rules.json                    Name, version, player count; add the numbers your code uses
  data/rules.md                      Rules text the model players read
  data/components/cards.yml          A placeholder component file
  data/personas.yml, data/bots.yml   Empty, with the format in comments
  spec/session/runner_spec.rb        The standard checks, pending until the game can play itself
```

The generated runner raises `NotImplementedError` from each hook you still have to write, with a hint of what to return. Comments list the hooks the gem already implements, so you can see what not to write.

## Step 2: Rules and components

Write the rules text in `data/rules.md`. Put the game's numbers (points to win, hand size, limits) in `data/rules.json` so the code reads them instead of hard-coding them, and the components in `data/components/`, one file per component.

Read the rules as an implementer: list every gap or ambiguity, settle each one, and record the answer in a **Rulings** section at the end of `rules.md`. If the harness deliberately simplifies a rule, say so in a **Simplifications** section.

See [Rules and components](technical/rules-and-components.md).

## Step 3: State

Decide what your game stores: decks, hands, piles, scores, whose turn it is, and the current *step* (the point in a turn the game is at, such as `draw` or `discard`). It all goes in `data`, as plain JSON values, so saving and resuming need no extra code. Use stable ids for things players refer to, such as each card's `uid`.

Then decide what each player may see, and hide the rest in your `GameState` subclass.

See [State](technical/state.md).

## Step 4: The runner

Write the three required hooks:

- `setup`: build the starting state (shuffle, deal) with `@rng`.
- `legal_moves(player)`: the menu for the current step, built with `option(...)`.
- `apply_action_effects(player, action)`: apply the chosen move, advance the step, and end the game when it's over.

Then `view_text_for(player)`, which shows the player the game as text, and `turn_phase(player)`, a short label for the console. Add `next_player` if turns don't simply alternate, and `pick_range` for "choose N cards" decisions.

See [The runner](technical/runner.md). For attacks and responses, triggered effects or other decisions inside decisions, see [Nested decisions with FrameQueue](technical/frame-queue.md). For card conditions too awkward to code, see [Yes/no rulings with the referee](technical/referee.md).

## Step 5: Specs for the rules

Before any model plays, write specs that set up a situation and check the menu and the effects: "with a soft 17, the dealer must hit", "a bust ends the hand". Rules bugs are cheapest to find here.

```sh
bundle exec rspec games/blackjack/spec
```

See [Specs](technical/specs.md).

## Step 6: The bot

Write `bot_choice` in `lib/blackjack/bot.rb` so the game can play itself, then remove the `pending:` from the standard checks in `spec/session/runner_spec.rb`. Run a botrun:

```sh
bundle exec plai_testr blackjack botrun --games 1000
```

It should finish with no crashes and sensible endings. Add personas and per-persona bot settings if you want to compare play styles.

See [Personas and bots](technical/personas-and-bots.md).

## Step 7: The debrief

Write `debrief_questions` and `debrief_facts` together. The facts are numbers your code counts during the game (points by source, how often each key action happened, who ended the game), which keep the models' answers about the game accurate.

See [Debrief](technical/debrief.md).

## Step 8: Check the prompts

Read a turn prompt and a debrief prompt yourself before running a model. Check that every option states facts rather than advice, that nothing hidden leaks, and that the view has what a player needs to decide. [The runner](technical/runner.md#checking-a-prompt) shows a script that prints both.

## Step 9: Play

```sh
bundle exec plai_testr blackjack preflight
bundle exec plai_testr blackjack play --mode hybrid
bundle exec plai_testr blackjack play
```

`--mode hybrid` lets the bot play the moves it marks obvious, which makes a quicker first model game. See [Running playtests](running-playtests.md).

## Optional: Reports

Add sections to each session report, or numbers to the botrun report, for what you want to track in your game. See [Reports](technical/reports.md).

## Feedback

I welcome feedback on what more information or affordances would make this easier: [open an issue](https://github.com/armahillo/plai_testr/issues).
