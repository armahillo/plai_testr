# Gin Rummy

v1.0.0

A card game for 2 players. Form melds, keep your unmatched cards (deadwood) low, and knock before your opponent does. The first player to 100 points wins.

## Cards

A standard 52-card deck. Aces are low: A-2-3 is a run, Q-K-A is not. Face cards count 10, aces 1, and number cards their number.

## Melds

- **Set:** 3 or 4 cards of the same rank (7♣ 7♦ 7♥).
- **Run:** 3 or more cards in a row of the same suit (4♠ 5♠ 6♠).

A card can belong to only one meld. Cards that are in no meld are **deadwood**.

## Each hand

1. **Deal.** Each player gets 10 cards. The next card is turned face up to start the discard pile; the rest is the face-down stock. The player who did not deal goes first.
2. **Turn.** Draw one card, either the top card of the stock or the top card of the discard pile. Then discard one card face up. You may not discard the card you just took from the discard pile.
3. **Knock.** Instead of a plain discard, you may discard and **knock** if your deadwood after discarding totals 10 or less. Knocking with 0 deadwood is **going gin**.
4. **Lay off.** After a knock, the knocker shows their melds. The other player shows theirs and may lay off deadwood cards onto the knocker's melds (adding to a set or extending a run). No laying off against gin.
5. **Dead hand.** If the stock is down to 2 cards after a discard and nobody knocked, the hand is a draw and is dealt again.

## Scoring

- **Knock:** if the knocker has less deadwood, they score the difference.
- **Undercut:** if the other player's deadwood (after laying off) is equal or less, they score the difference plus 25.
- **Gin:** the knocker scores the other player's deadwood plus 25.

The winner of a hand deals the next one. The first player to reach 100 points wins the game.

## Simplifications in this version

- Melds and lay-offs are arranged automatically to give each player the lowest deadwood.
- There is no special first-turn offer of the upcard; the first player simply draws.
- No box, line or game bonuses, and no Big Gin.

## Strategy notes

- Early on, keep cards that are close to melds (pairs, two cards in a row of one suit).
- Taking from the discard pile tells your opponent what you are collecting.
- Discard high deadwood (face cards) first; knock early when your deadwood is low.
