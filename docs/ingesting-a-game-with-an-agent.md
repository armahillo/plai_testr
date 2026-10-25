# Ingesting a game with an agent

*Ingesting* a game means turning your rulebook into a *harness*: code that knows your game's rules well enough to deal the cards, list each player's legal moves, apply the one they pick, and tell when the game is over. Language models are unreliable at tracking a game's state over a long game, so the harness does the bookkeeping and the model only chooses.

You can have an AI coding assistant (an *agent*, such as [Claude Code](https://claude.com/claude-code)) write the harness for you. This guide covers what to prepare, how to ask, and how to check the result. It assumes you've finished [Getting started](getting-started.md). To write the harness yourself instead, see [Ingesting a game manually](ingesting-a-game-manually.md). The two mix well: have the agent write the first version, then read and change it yourself.

The examples below use Blackjack, whose [rules](https://bicyclecards.com/how-to-play/blackjack) are public domain.

## Step 1: Create the game's folder

From your app folder:

```sh
bundle exec plai_testr generate game blackjack
```

Game names are lowercase, with `_` instead of spaces. This creates `games/blackjack/` with a starting file for everything the harness needs:

```
games/blackjack/
  data/rules.md            The rules, as the model players will read them
  data/components/         Card lists and other components
  data/rules.json          The game's name, version, player count, and numbers the code uses
  data/personas.yml        Optional: strategies and play styles for the model players
  data/bots.yml            Optional: settings for the bots
  lib/                     The harness code (the agent writes this)
  spec/                    Automated checks (the agent writes these too)
```

You fill in the first two; the agent does the rest.

## Step 2: Write the rules

Put your rules in `games/blackjack/data/rules.md`, in [Markdown](https://www.markdownguide.org/basic-syntax/). There's no required format: write it the way you'd explain the game to a new player. The model players read this file every turn, so:

- Describe the procedure: setup, what happens on a turn, how the game ends, how scoring works.
- Long examples and flavor text can go; they cost the models reading time.
- Leave out house rules and variants you aren't testing.

Don't worry about gaps. The agent is told to find them and ask you.

## Step 3: List the components

Put every card, tile or token list in `games/blackjack/data/components/`, one file per kind of component. The file name becomes the component's name (`cards.csv` is "cards").

A file is a list with one row per component and a column for each thing about it. A spreadsheet saved as CSV works:

```csv
name,suit,rank
A♣,clubs,1
2♣,clubs,2
```

YAML works too, and suits cards with longer text:

```yaml
- name: Ambush
  cost: 2
  text: Play when an opponent attacks. Cancel the attack.
  copies: 3
```

A `copies` column makes that many identical copies. `games/hearts/data/components/cards.csv` is a complete standard deck.

Already have your components in another form (a spreadsheet, an export from a card tool, a PDF)? Point the agent at it instead; it will convert it and check the counts with you.

## Step 4 (optional): Sketch some personas

A *persona* is a play style: a strategy the model players follow, and settings that make the bots play differently. Botruns then compare how each style does.

Personas build on a *basic strategy* that every player follows. For Blackjack that might be "never hit on 21" and "always hit under 11". Each persona then adds its own approach: a `by_the_book` player who hits under 16 and stands on 16 or more, a `21_obsessed` player who always tries for exactly 21. It's a fun way to test design hypotheses, and to catch rules regressions later.

You don't need to write `personas.yml` yourself. Describing the styles in plain words to the agent is enough.

## Step 5: Ask the agent

The app comes with instructions for agents. Its `CLAUDE.md` pulls in PlAI Testr's [agent guide](AGENTS.md), which explains how the harness works, the order to build it in, and to ask you before guessing at a rule. Claude Code reads `CLAUDE.md` automatically when started in the app folder. With another agent, tell it to read `AGENTS.md` and `.plai_testr/gem/docs/AGENTS.md` first.

Start the agent in the app folder (for example, run `claude`) and give it a prompt like this:

```
I'm building a PlAI Testr harness for my game, blackjack. I ran `plai_testr generate game blackjack`, wrote the rules into @./games/blackjack/data/rules.md, and put the components in @./games/blackjack/data/components/.

Build out the rest of the harness so I can run botruns and model games:

  1. Read the rules and components closely. Before writing any code, list
     every gap, ambiguity or rule you'd have to guess at, and ask me about
     them. Record my answers in a Rulings section in rules.md.
  2. Fill in data/rules.json, then build the state, runner and bot following
     the order in the PlAI Testr agent guide, with specs for the rules as you go.
  3. Get `bundle exec plai_testr blackjack botrun --games 100` finishing
     with no crashes and sensible endings, and `bundle exec rspec
     games/blackjack/spec` passing.
  4. Write the player views, debrief facts and debrief questions, and show
     me one turn prompt and one debrief prompt to review.

Don't change the rules to make the harness easier. Don't run any model games
(play, preflight, resume, debrief) — stop and tell me when it's ready.
```

Add your personas to the prompt if you have them in mind ("Add three personas: …").

Expect rules questions. Answering them is often useful in itself: it has turned up ambiguities in my own rules I hadn't noticed. The answers go in a *Rulings* section at the end of `rules.md`, so the model players see them too. A small game like Blackjack typically takes a few minutes; a large one can take much longer.

## Step 6: Check the result

When the agent says it's ready:

1. **Run the checks.** `bundle exec rspec games/blackjack/spec` should pass. These include the standard checks every game gets: games reach an ending, saved games resume exactly, and no player can see another's hand.
2. **Run a botrun** and read the report:

   ```sh
   bundle exec plai_testr blackjack botrun --games 100
   ```

   Do the results make sense? A cautious persona that busts more often than the gambler, or games that all end the same unusual way, point to a bug. Describe what looks wrong to the agent.
3. **Read the prompts** the agent showed you. Is everything a player needs to decide there? Is anything there that the player shouldn't know, such as the dealer's face-down card? Does any option tell the model what to pick? Options should state facts ("Hit (your total: 14)"), never advice ("Hit (recommended)").
4. **Run a model game** when you're happy:

   ```sh
   bundle exec plai_testr blackjack preflight
   bundle exec plai_testr blackjack play
   ```

See [Running playtests](running-playtests.md) for the options and for reading reports.

## Asking for more

The agent guide stays with your app, so you can come back to the agent at any time. Some requests that work well:

- *Write bot rules for blackjack so the gambler persona plays differently, run a 1000-game botrun, and summarize the report.*
- *Read the newest report in games/blackjack/reports and tell me what it says about balance. Separate what might be the bot's habits from what might be the game.*
- *The model players in blackjack keep making the same bad choice. Show me the prompt they see and suggest how to make the menu clearer, without telling them what to pick.*
- *I've ruled that a tie goes to the dealer. Update the engine, add a spec, and record the ruling in data/rules.md.*
- *The debrief answers mention things that didn't happen. Add debrief facts for what the questions ask about.*
- *I've changed the rules in data/rules.md to version 0.4. Update the harness to match and tell me what changed.*

The agent guide tells the agent to ask before running model games, which can take a long time. Specs and botruns are fast, so it runs those freely.
