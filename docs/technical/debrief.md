# Debrief

After a model game, each player answers the game's `debrief_questions`, and the answers go in the report. Small local models can't reliably recall a long game from its log, and they invent what they can't recall, so the gem gives them a summary of the facts first.

## The prompt

The gem builds the debrief prompt in a fixed order:

1. **`debrief_summary(player)`**, built by the gem (don't override it):
   - **Outcome**: winner, end reason, final scores
   - **Game facts**: `debrief_facts(player)`, shown as YAML
   - **Your decisions**: how many the model made, how often it chose the bot's obvious move, fallbacks
   - **Your plan as it changed**: the player's own `plan` each time it changed, with the decision and step
2. **`debrief_view_for(player)`**: the final position. Default: the result, final scores, `view_text_for` and the player's visible log.

The model is told to treat the summary as correct, to cite the round of any event it mentions, and to say when something isn't in the facts rather than guess.

The debrief uses the player model without thinking, unless `play` is given `--debrief-model` or `--debrief-think`.

## `debrief_facts`

Returns a Hash with plain-language keys:

```ruby
def debrief_facts(_player)
  {
    'how_it_ended' => "Player 3 reached 100 points after 9 hands",
    'players' => players.to_h do |p|
      [p, { 'final_score' => pstate(p).score, 'hearts_taken' => data.dig('tally', p, 'hearts'), 'moons_shot' => data.dig('tally', p, 'moons') }]
    end
  }
end
```

- **Count what the questions ask about.** Per player: final score and points by source, counts of key actions, races or majorities and who won them; and who ended the game, when and how.
- **Facts, not conclusions.** "Player 3 had 4 Candy Corn, the most" is a fact; "Candy Corn was the strongest card" answers the question for the model.
- **Compute only from saved state** (`data`, player state). `debrief <session_id>` rebuilds the facts from the checkpoint, possibly after the code changed, so instance variables are gone. Keep the counters the facts need in `data` as the game is played; `tally(player, key)` is made for this.

Without `debrief_facts`, the facts are `botrun_stats`. `check!`, run by every game command, warns when a game defines neither.

## `debrief_questions`

Ask about the player's own experience, pointed at something the facts or its own plans can answer:

- *Which of your decisions mattered most, and why? Name the round.*
- *Which of your plays scored less than you expected? What happened instead?*
- *Which rule was unclear or confusing when you had to use it? Name the situation.*

Avoid open questions with nothing behind them ("what felt pointless?"): models fill them with invented events. `debrief_questions(player)` takes the player, so questions can differ by persona.

## Checking and re-asking

- Preflight builds every player's debrief prompt after its lint games, and the [standard checks](specs.md) build them too, so a broken hook shows up before a model game.
- `debrief <session_id> [--model M] [--think]` re-asks a finished game's players and rebuilds the report, keeping earlier answers under `debrief_history` in the checkpoint. Use it to try better facts or questions, or a bigger model, on the same game without replaying it.
- Debrief answers are model opinions. Check a claim against the facts or the turn log before acting on it.
