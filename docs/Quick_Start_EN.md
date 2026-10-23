# Illuminati — Basic Rules

A two-player strategy card game. Lead a secret society, build your network, and defeat your rival.

## Playing Online

Choose **Play with a friend**. Create a room and share its 6-digit code, or enter your friend's code. Both players press **Ready to play**, then choose their starting cards independently. No account is needed.

Starting selections allow 60 seconds per step. Each turn allows 120 seconds. Every battle or counter response gets a fresh **15 seconds** when the response passes to you. Circular clocks show both players' time; the last seconds pulse and play a quiet cue.

Online matches always use full animations. Both players finish the presentation before the server opens the next operation and starts its clock. Language, volume, and layout remain personal settings and never change the rules or dice. Inspecting cards, opening Settings, or using **View Battlefield** keeps your online clock running.

If a response expires, the game passes or accepts the Plot. Required choices are completed automatically; an expired turn ends. Two entire turns without input count as a loss. Disconnections pause play and reconnect automatically, with 90 seconds of total grace per player per match. Leaving an ongoing room counts as resigning. After the result, both players can request another game in the same room.

## Setup

Choose an Illuminati faction. Each player gets 2 Plot cards and 5 Group cards. Pick 1 Group as your starting subordinate and keep the rest. Then choose 1 Resource from 5 random candidates to keep in your hand. Group and Resource selections each allow up to 2 redraws.

Roll two dice each. The higher total goes first; the second player draws 1 extra Plot. Both players share the Group, Resource, and Plot decks.

## Your Turn

**Draw → Refresh Actions → Main Phase → End Turn**

You may draw 1 Group and 1 Plot, then refill eligible cards to their action limit (normally 1). In the main phase, recruit, attack, play Plots, use abilities, or rearrange your network. There is no fixed number of actions per turn.

- **Automatic Takeover:** Spend your Illuminati's action to recruit a Group from your hand into a free slot without rolling.
- **Resources:** Keep up to 2 in play, beside your Illuminati. They use no control slots and do not count as Groups. Deployment and Automatic Takeover are each limited to once per turn, independently. Pay the relevant action cost for each.
- **Extra draw:** Spend your Illuminati's action to draw 1 card from any deck. Resources are not drawn automatically; your Resource hand normally holds up to 2.

New recruits and newly deployed action-based Resources start with **0 actions** and cannot be readied that turn.

Your normal Plot hand limit is **5**, including at most **1 Goal Plot**; card effects may change limits. There is no normal Group hand limit. Discard excess Plots when prompted.

## Card Values, Alignments, and Tags

- **P — Power:** Used to lead attacks, provide eligible support, and self-defend.
- **GP — Global Power:** Used for support when the group does not qualify to use P. Never add P and GP together.
- **R — Resistance:** The target's base defense against Control attacks.
- **Slots:** The number of direct subordinates a card can control, up to 3.

A group may have several **alignments**. They describe its political or social character and affect combat:

| Alignment | Theme | Opposes |
|---|---|---|
| Government | State institutions and public authority | Corporate |
| Corporate | Business and commercial interests | Government |
| Liberal | Reform and social openness | Conservative |
| Conservative | Tradition and established values | Liberal |
| Peaceful | Nonviolent methods | Violent |
| Violent | Force and coercion | Peaceful |
| Straight | Conventional, mainstream society | Weird |
| Weird | Unconventional people and ideas | Straight |
| Criminal | Illegal activity and the underworld | None |
| Fanatic | Uncompromising devotion to a cause | Fanatic |

These are game categories, independent of tags. **Fanatic opposes itself and never counts as a shared alignment**, unless a card explicitly says otherwise.

When comparing the attack leader with the target:

- **Control:** +4 strength per shared alignment; −4 per opposing pair.
- **Destroy:** −4 strength per shared alignment; +4 per opposing pair.

Example: Government/Violent attacking Government/Peaceful has one shared alignment and one opposing pair. Its alignment modifiers cancel out.

**Tags** are separate from alignments. Examples include Military, Computer, Science, Magic, Communist, Celebrity, Place, Huge, and Coastal. Tags have no automatic alignment bonus; they matter when a rule or card names them. **Place** marks locations, **Huge** marks large locations (currently at least 1 million km²), and **Coastal** means having a coastline.

## Attacks

Spend a group's action to lead an attack. A player is protected until they complete their first turn, unless they attack the opponent first:

- **Control:** Recruit from your hand or seize an enemy group and all its descendants. The leader needs a free slot.
- **Destroy:** Destroy an enemy group; its descendants return to their owner's hand.

Start with the leader's **P**. Subtract the target's **R** for Control, or usually its **P** for Destroy, then apply modifiers.

After confirmation, the camera frames the leader and follows a labeled arrow to the target: teal for Control, coral for Destroy. A recruit from hand appears as a temporary public card; it joins your network on success or returns to your hand on failure. Support briefly highlights both participating cards and shows the actual bonus. These cues finish before the action is committed. Automatic Takeover does not use an attack arrow.

Players alternate support and Plot responses. When both pass, roll two dice: a total **at or below the final strength succeeds**. **11 or 12 always fails.** Strength below 2 fails without rolling.

### Defense and Support

In addition to base defense:

- **Loyalty:** +4 per alignment shared with the target's direct parent. Opposing alignments do not subtract loyalty; Fanatic is excluded. Applies only against Control.
- **Position:** Direct subordinates of the Illuminati have +10 defense; the next level has +5; deeper groups have +0. Applies against Control and Destroy.
- **Self-defense:** The target may spend its action for an extra **2 × its effective P** defense. This is separate from its base defense.

Ordinary support costs the supporter's action. **Compare the supporter with the attacked target**, using this table:

| Supporting… | Use P when… | Otherwise |
|---|---|---|
| A Control attack | Supporter and target share an alignment, excluding Fanatic | Use GP |
| A Destroy attack | Supporter and target have opposing alignments | Use GP |
| The defense | Supporter and target share an alignment, excluding Fanatic, or are direct parent and child | Use GP |

Use only one value, P or GP. Card abilities may override support eligibility or add bonuses. Combat Plots may also affect eligible supporting groups; they do not have to target the attack leader.

**Disasters** are special attacks against Places. They ignore alignment, loyalty, and position; only the defender can provide ordinary support. The target normally loses its action before responses. A devastated Place has halved P/GP, cannot act, and does not count toward victory until rebuilt. Rebuilding during your main phase costs 1 group action, or 2 different groups’ actions for a Huge Place, unless a card says otherwise.

**Country** is a tag for national Places, excluding states, cities, and ports. The United Nations gains +1 GP for each direct Country subordinate, up to its P.

## Winning

Meet your Illuminati's victory condition at turn end, once both players have completed a turn. A Goal Plot must instead be played during your main phase after meeting its condition and the first full round, and can be countered.

You also win by eliminating all enemy groups once the opponent has completed at least 3 turns.

**Safe House** can be scrapped during a normal control attack against one of your Groups. Return that Group and its entire branch to your hand and cancel the attack. Attachments are discarded. Paid costs stay spent; no dice are rolled and no attack success, failure, or post-battle recovery abilities trigger.

A Group exposed for recruitment must be discarded at turn end if recruitment still failed. Read cards for special rules. Hover, right-click, or long-press to inspect them.
