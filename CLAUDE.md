# TESTR

*Last updated: 2026-03-14 20:57*

TESTR is a proposed applications that is intended to do board game playtesting autonomously. I would like to build this using locally-hosted agentic LLM models. The intended outcome is to have a platform I can run on my own computer (to keep costs down) that runs passively on a computer I don't use most of the day. This platform can be given a rules document in a computer-readable format, and then mediate a session of the game where the LLM agents play the game. The platform records the game, the thought process of the LLMs, and the outcome. This is then saved to a report and I then I can review how the games actually work.

## Background

I am a board game designer and a software developer who primarily uses Ruby for my day job. I am relatively new to doing custom LLM work and haven't used much beyond Claude.ai.

I have multiple board games in development, and I meet with some friends to do playtesting in person 2-3 times a month. I have a lot of ideas that need iteration more frequently, and having more granular data collection would be very helpful.

I have a computer I built relatively recently with an Intel Core2Power CPU, 32GB of DDR5 RAM, and an NVIDIA RTX3050 GPU. Most of the day this computer is unused, and I typically use it for gaming in my recreation time. I have already installed Ollama on it and have experimented a little bit with the qwen3 model. I proposed this idea to it and it gave me back a basic Ruby backbone and suggested some smaller models that I could use that is lightweight and would be suitable as the players. I believe it also required a third agent to also run as the rules enforcer.

My local qwen3 instance is useful but it is also pretty slow to do this kind of work with, so I'm wanting to have you help me to scaffold out this system.

If there is a better approach than the one I'm describing, I am open to

## Technical specification

Re-emphasizing that the goal here is to run this on my local computer. I am OK with it not being fast, so long as it is reliable, produces useful output, and can run steadily without needing me to attend to it while it's running test sessions.

I prefer to not use cloud-based LLM solutions, as great as they are, because this would be costly.

### Backend

I'd like to use ruby to build the software overseer that sits above this whole platform, handles disk I/O, etc. If needed I can setup a redis instance. Qwen3 suggested using a JSON payload to handle communication among the agents, this is fine. Data about the sessions can be persisted in JSON, YAML, or whatever format makes sense. Reports should be written in markdown. The reports should summarize the session, the outcome, and any abstracted data that would help me to assess balance and gameplay issues.

I would like a structured template for encoding rules into a format that an LLM can read and understand. I need to be able to either modify this directly, or write another document that is then "compiled" into this format.

I also need a structured template for how the LLMs communicate with the main driver, and a means for that main driver to consult with the rules enforcer.

## Game specifications

### Rules

The rules documents I use for my own reference are written in markdown format. My presumption is that I will need to codify these to something more structured / machine-readable for use in this platform. I am OK with that. I may need some assistance in planning this out.

### Player count

For now, let's start with a 2 player game. I have one that is fairly mature, and another that is published, and we can use those as test subjects. It would be nice to be able to eventually support 4 players, or maybe even 6, but that may require a more powerful computer. When writing any software, it should be written in such a way that it _could_ be adapted to handle N players, rather than always 2.

### Game complexity

The two games I have for starting are both card games, one of which does use two additional tokens to track a flag in game-state. Some of the other games I have also have tokens, point counters, and sometimes dice. If we need to create a local API as part of the platform to provide a random engine (for dice rolls, eg), that is fine.

### Ollama model plan

Honestly I'm not sure! I think the Qwen3 model suggested a much smaller model (llama:4b? It said it was very lightweight and didn't require a GPU) for the player agents, and then, I presume, a more complicated one for the rules enforcer. I am open to suggestions here.

### Session output

If turn-by-turn transcripts with reasoning are possible, that would be amazingly helpful. Saved separately would be preferable.

### Idempotency / resumability

If the session crashes mid-game, being able to resume would be ideal. I also need an emergency cut-off to interrupt and stop the game, should the agents get stuck in a loop, or if the game isn't trending towards completion, or just to be able to stop it if I need to power down the computer. Being able to save the current game state would be very helpful, in this case. 