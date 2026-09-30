# Tortuga — High-Level Master Plan

Date: 2026-09-29  
Planning horizon: research through a complete offline and shared-campaign game  
Production baseline: solo owner with AI assistance

## Summary

Tortuga is a modern pirate adventure inspired primarily by the 2004 PC edition of *Sid Meier's Pirates!*, preserving its approachable naval action, open-ended captain's life, and interconnected Caribbean sandbox. Development begins with research and an offline naval MVP, introduces cooperative and competitive naval multiplayer immediately afterward, and then adds campaign features one at a time to both offline and shared-world play.

This is the project's master roadmap: it establishes direction, sequencing, dependencies, and completion gates. Each phase receives its own detailed specification and implementation plan in a later session.

▼

## Goals

- Preserve the spirit of *Pirates!*: freedom to choose a course, short adventures within a longer career, readable tactical choices, and consequences that connect otherwise simple activities.
- Deliver a classic-modernized experience: overhead sailing, captain-focused decisions, stylized swashbuckling, and modern usability.
- Support Windows, macOS, and Linux, with feasibility established early and actual platform verification throughout development.
- Deliver highly performant play, extremely fast loading, and tiny game files: responsive controls, smooth frame pacing, short waits to playable action, and a small total download and installed footprint. Treat these as first-class constraints on engine, asset, and feature choices.
- Make sailing and naval combat enjoyable before expanding the world or production scope.
- Support offline play as a complete experience, alongside a small-group shared campaign in which independent captains can cooperate and compete.
- Introduce exploration, ship variety, trade, crew management, faction relationships, quests, and captain progression in independently verifiable increments.
- Selectively revive signature activities, explicitly planning boarding duels and treasure hunting while evaluating other minigames on their merits.
- Keep the roadmap achievable for a solo/AI-assisted project through bounded scope, reusable content, and playtest-driven expansion.

▼

## Non-Goals

- Detailed mechanics, engine selection, networking protocols, code architecture, asset specifications, task estimates, or implementation tickets in this document.
- Recreating the entire 2004 game as the first MVP. The first MVP is deliberately naval-only.
- An MMO, a continuously running public world, or a live-service business model in the approved scope.
- Shared-ship player roles, seamless third-person town exploration, or a comprehensive naval/historical simulation.
- Automatic feature parity with every edition or port, or a commitment to every classic minigame.
- Fixed delivery dates or a promise that AI assistance removes the need for human design judgment, assets, and playtesting.

▼

## Design

### 1. Agreed direction

| Decision | Direction |
|---|---|
| Primary reference | 2004 PC *Sid Meier's Pirates!*; consult the 1987 original and *Pirates! Gold* for lineage and contrasts. |
| Research sources | Include Wikipedia, cross-check important mechanics with the official manual, and distinguish design testimony from reviews and interpretation. |
| First playable milestone | An offline naval MVP centered on sailing and ship combat against AI. |
| Multiplayer destination | Small-group shared Caribbean campaigns, each player an independent captain. |
| Phase 1 hosting direction | Dedicated server for 2–4 independent captains; game time pauses when empty. Offline play remains self-contained. |
| Multiplayer timing | Immediately after the offline naval MVP, starting with bounded naval sessions. |
| Presentation | Classic-modernized overhead adventure; light swashbuckling tone, readable action, and accessible interaction. |
| Development capacity | Solo/AI-assisted; production scope must account for art, animation, audio, content, and human testing. |
| Signature activities | Boarding duels and treasure hunting are planned; other classic activities require separate evaluation. |
| Planning method | One principal player-facing capability per phase, validated before adding the next. |

The master plan is detailed about outcomes and boundaries while remaining high-level about how to achieve them. The early naval multiplayer phases are stepping stones toward the shared campaign, not substitutes for it.

### 2. Research foundation

#### Scope and evidence

The initial desk-research pass reviewed Wikipedia's articles on the 1987 original and 2004 remake, the official PC manual, Sid Meier's account of the game's design intent, and contemporary PC and Xbox reviews. It establishes a foundation for this roadmap; it does not constitute hands-on playtesting or verification of every edition-specific mechanic. Phase 1 must turn this foundation into a concise reference dossier and investigate pacing and observable behavior through recorded 2004 PC gameplay, cross-checked against the manual. Reference-game input feel and enjoyment remain sourced testimony or hypotheses; Tortuga's feel and enjoyment require Phase 2 human playtests.

The manual describes intended mechanics; reviews describe the reviewers' experiences and judgments. Wikipedia supplies broad context and edition comparisons. None should be treated as an exact specification for Tortuga or as the sole source for historical accuracy.

#### What defines the reference game

| Reference system | Research finding | Implication for Tortuga |
|---|---|---|
| Open-ended captain's life | The player can pursue privateering, piracy, trade, exploration, personal quests, and status rather than follow a mandatory linear campaign. [R1–R3] | Preserve several viable motivations as the campaign develops. |
| Interconnected activities | Encounters lead to combat, prizes, port visits, repairs, recruitment, political consequences, and new leads. Their connections give simple activities lasting significance. [R3, R5] | Judge features by what they contribute to the whole voyage, not their isolated complexity. |
| Sailing | Wind, vessel characteristics, sail settings, crew, damage, and weather shape routes and engagements. [R3, pp. 17–31] | Keep tactical sailing legible; validate travel pacing before expanding the map. |
| Naval combat | Broadside positioning, reload timing, hull/sail/crew damage, and ammunition create tactical choices. Capturing a ship preserves value that sinking it destroys. [R3, pp. 32–39] | Prove maneuvering and firing first, then add persistent capture and economic consequences. |
| Ports and economy | Ports join repairs, upgrades, recruiting, trade, information, and political opportunities. Local conditions influence available goods and trade. [R2, R3, pp. 45–50, 111–112] | Ports become hubs for the emerging campaign; deeper dynamic trade is an explicit modernization goal. |
| Factions | English, French, Dutch, and Spanish interests create opportunities for privateering, rank, benefits, hostility, and changing allegiance. [R1–R3] | Reputation must change player opportunities, rather than exist only as a score. |
| Crew and voyages | Food, morale, crew size, accumulated loot, and dividing plunder govern the rhythm of expeditions. [R3, pp. 26–27, 79–82] | Build pressure to return to port and reasons to begin another voyage. |
| Progression and career | Starting skills, equipment, specialists, ships, rank, fame, and aging all affect the career. This is not simply a conventional experience-level skill tree. [R3] | Treat expanded skill development as a design choice; preserve meaningful trade-offs and accomplishments. |
| Adventures and discovery | Missions, moving villains, family quests, rival pirates, map fragments, and landmarks offer short- and long-term goals. [R3, pp. 51–55, 73–78] | Add missions before richer narrative chains and clue-driven treasure hunting. |
| Character activities | Duels, land battles, sneaking, romance, and dancing supplement naval play in the 2004 game. [R2, R3] | Restore selected activities one at a time, with their shared-world pacing explicitly designed. |
| Career closure | Dividing plunder, aging, retirement, and fame turn a sandbox into a remembered pirate career. [R3, pp. 79–83] | Include a meaningful career conclusion; decide the treatment of aging separately for solo and shared campaigns. |

#### Edition distinctions that matter

- **1987 original:** established the open-ended pirate-career sandbox and dynamic political/economic context. [R1]
- **Pirates! Gold (1993):** an intermediate remake with presentation and feature changes; useful comparative context, not a second parity target. [R1]
- **2004 PC remake:** the main reference. Its manual explicitly identifies removed sun sighting and ship-versus-land combat, plus additions such as dancing, equipment, crew specialists, action-based sneaking, and encounters involving an escorted ship. [R3, pp. 7–8]
- **Later ports:** differ from the PC game. In particular, the Xbox version already included up-to-four-player naval versus battles. That is distinct from Tortuga's intended shared campaign. [R2, R6]
- **Period setting:** the series spans multiple starting eras, not one exact historical snapshot. Choose one bounded Caribbean setting first; additional eras are optional future expansion. [R1, R3, pp. 85–96]

#### Lessons to carry forward

1. **Pirate fantasy before simulation complexity.** Meier described *Pirates!* as drawing on the fantasy of piracy rather than literal historical realism. The captain should remain at the center of interesting decisions. [R4]
2. **Simple controls can support rich consequences.** A modest set of actions becomes compelling when wind, resources, enemies, and opportunities interact. [R3, R5]
3. **Protect pacing.** The PC review praises the interplay of long- and short-term goals but criticizes repetitive activities and tedious upwind travel. Treat these as playtest hypotheses, not universal verdicts. [R5]
4. **More activities do not automatically mean more fun.** Every revived minigame must justify its production cost, repetition, accessibility, and multiplayer waiting time. [R5]
5. **Shared time is a major design change.** The PC game stops time in menus, duels, land combat, and trading; sailing and sea combat also use different time scales. These assumptions cannot simply be carried into an independently moving multiplayer world. [R3, pp. 12, 21, 82]

### 3. Development strategy and phase gates

Use a sequential, feature-by-feature roadmap. Broad release bundles would hide too much unproven work; separate offline and online development tracks would increase divergence for a solo project. Instead, after the naval multiplayer proof, every campaign feature must work in both modes before it is considered complete.

The default dependency is the previous phase's accepted outcome. Explicit dependencies below identify additional prerequisites. Dependencies allow a narrowly scoped precursor when needed—for example, encounter damage in the naval MVP before full crew management—but do not authorize pulling an entire later feature into the current phase.

Before starting each phase, create its detailed plan covering the player outcome, minimum scope, exclusions, unresolved decisions, production needs, and verification. End each development phase with a playable demonstration; Phase 1 concludes with its approved research and feasibility deliverables. At each gate, decide to proceed, iterate, reduce scope, or defer. No phase is complete solely because code exists.

#### Phase 1 — Research and direction

**Purpose:** Establish what Tortuga must preserve and what it should change before implementation begins.

**Detailed research brief:** [Phase 1: Research and direction — specification #1](https://github.com/dnldxn/tortuga/issues/1). **Status: accepted by the owner on 2026-09-30.** Findings, measurements, approved budgets, and the decision/risk register are in the [Phase 1 research dossier](docs/research/phase-1.md). Selected: Godot 4.7.2 with the Compatibility renderer; northern Leeward Islands c. 1660–1680; top-down 2D presentation. Carried into Phase 2 as gates: native runs on Windows and macOS, and a frame-time check on a real display.

**Scope:** Expand the reference research with observed play, map the main systems and their relationships, and make a preserve/modernize/defer assessment. Define the initial naval play area and art direction at a scope appropriate for one owner. Evaluate development tools and cross-platform feasibility. Resolve enough of the multiplayer session model—independent captains, intended group size, world time, encounters, and ownership—to avoid building an incompatible offline foundation. Establish an asset sourcing and production approach for Tortuga's own presentation.

**Performance and footprint brief:** Establish measurable budgets for frame time and pacing, memory use, cold-start time to playable action, encounter loading/replay time, compressed download size, and installed size. Define reference hardware, resolution, build configuration, and measurement conditions. Evaluate candidate tools and representative assets against these budgets in feasibility work; record measured evidence separately from estimates. Account for required runtime dependencies in the footprint.

**Dependencies:** README goals, interview decisions, and the research foundation above.

**Completion gate:** An approved reference dossier, design pillars, bounded naval-MVP brief, and feasibility findings sufficient to plan Phase 2, including agreed performance, loading-time, and file-size budgets and evidence that the proposed approach can plausibly meet them. Record and close foundational unknowns; retain later feature decisions for their owning phases.

#### Phase 2 — Offline naval MVP

**Purpose:** Prove that sailing and ship combat are enjoyable on their own.

**Scope:** A bounded sea area, readable wind and handling, a small selection of meaningfully different vessels, AI opposition, broadside combat, understandable damage and encounter outcomes, and quick replay. Use only the encounter-level crew/ammunition distinctions needed to test naval decisions. Establish usable controls, feedback, and basic audio/visual clarity.

**Dependencies:** Phase 1 direction and feasibility decisions.

**Completion gate:** A player can start, maneuver, fight, win or lose, and replay without guidance. Human playtests find meaningful choices rather than one dominant maneuver. A runnable naval build is verified on Windows, macOS, and Linux before this milestone closes.

**Boundary:** This is a naval MVP, not yet a pirate-career sandbox. Economy, persistent prizes, crew upkeep, and playable boarding duels belong to later phases. Phase planning chooses the initial weapon/ammunition variety needed to prove tactical choices; the broader selection grows in Phase 16.

#### Phase 3 — Cooperative naval sessions

**Purpose:** Prove the same naval experience with multiple independent human captains.

**Scope:** Private dedicated-server sessions, joining and leaving, cooperative encounters against AI, shared encounter outcomes, and clear behavior when a participant disconnects or the server stops. Finalize the initial player-count and session expectations within Phase 1's 2–4-captain envelope in this phase's detailed plan.

**Dependencies:** The enjoyable offline naval loop and Phase 1 multiplayer constraints.

**Completion gate:** The agreed small group can repeatedly join, fight together, and complete a session with consistent outcomes. Supported cross-platform combinations and representative connection conditions are exercised. Offline play remains fully usable.

#### Phase 4 — Competitive naval sessions

**Purpose:** Validate naval action when opponents are other players.

**Scope:** Explicit match rules, teams or free-for-all as selected during phase planning, balanced starting conditions, clear victory/defeat, and fair interpretation of combat outcomes. Test whether tactics that work against AI remain interesting against humans.

**Dependencies:** Cooperative session stability and the established naval mechanics.

**Completion gate:** Players can complete repeatable competitive matches and understand the outcomes. The game handles disagreement or interrupted participation clearly, and playtests reveal viable tactical alternatives.

**Boundary:** These matches do not yet establish campaign PvP rules, persistent loot loss, or faction competition.

#### Phase 5 — Caribbean exploration

**Purpose:** Turn naval scenarios into a persistent place to adventure.

**Scope:** A small Caribbean region with recognizable geography, navigable routes, destinations, and AI traffic. Establish independent player travel, entry into and exit from encounters, shared-world time, and what uninvolved players experience during battles. Introduce offline campaign saving and dedicated-server campaign saving and resuming, with clear player identities and ownership of ships. Shared campaign game time pauses when no players are connected.

**Dependencies:** Offline, cooperative, and competitive naval foundations.

**Completion gate:** Solo and multiplayer players can explore, encounter traffic, enter and leave battles, and resume the same world later without losing or duplicating campaign state. The region is engaging before its size is expanded.

**Boundary:** Phase planning must define temporary post-battle recovery and whether campaign PvP is enabled before Phase 7; persistent capture and property-loss rules remain owned by Phase 7.

#### Phase 6 — Ports and ship services

**Purpose:** Give voyages destinations and a reliable return-to-port loop.

**Scope:** Docking, a compact town interaction model, repairs, basic refitting and resupply, and readable ship condition. Add only the minimal money/resource bookkeeping needed for these services; cargo markets arrive in Phase 8. Define port safety and the behavior of players in town while others remain at sea.

**Dependencies:** Persistent exploration, damage, and campaign ownership.

**Completion gate:** Players can sail out, incur costs or damage, return, restore readiness, and set sail again in either mode. Service costs have a sustainable early source, and players can recover from a poor outing rather than become stuck.

#### Phase 7 — Capture and plunder

**Purpose:** Make piracy about taking valuable prizes as well as winning fights.

**Scope:** Ship surrender or bounded boarding resolution, loot, cargo capacity, prize ownership, and keeping, selling, or relinquishing captured vessels. Define cooperative reward allocation and the initial campaign rules for attacking other players and taking their property. Provide an understandable route back into play after defeat.

**Dependencies:** Combat, persistent ownership, ports, and minimal resource bookkeeping.

**Completion gate:** Capturing and sinking produce meaningfully different outcomes. Players can resolve, retain, and dispose of prizes; cooperative and competitive outcomes respect the agreed campaign rules. Loss and interruption do not corrupt or duplicate rewards.

**Boundary:** Boarding uses a simple resolution until Phase 14. Owning prizes does not imply a full fleet-command combat system.

#### Phase 8 — Trade and economy

**Purpose:** Connect ports and cargo through economic choices.

**Scope:** A small set of goods, buying and selling, limited market availability, and understandable price variation over location and time. Make trading and plunder feed the same economy. Introduce only the world influences needed for useful decisions; expand economic depth when playtests justify it.

**Dependencies:** Ports, cargo, persistent money, and prize disposal.

**Completion gate:** Players can identify and profit from a trade opportunity, understand why prices differ or change, and choose between trade and piracy. Shared markets remain coherent when multiple players trade, and the economy avoids trivial unlimited-profit loops.

#### Phase 9 — Crew management

**Purpose:** Give expeditions resource pressure and human stakes.

**Scope:** Recruitment, provisions, crew capacity, morale, and the relationship between crew condition and ship effectiveness. Develop clear warnings and recovery paths. Introduce specialists only if they materially improve the initial management loop.

**Dependencies:** Ports, earnings, cargo capacity, and voyage travel.

**Completion gate:** Crew decisions change how far and how aggressively a captain can operate. Solo and shared-session players can read, manage, and recover from shortages without excessive bookkeeping or disproportionate penalties for another player's delays.

#### Phase 10 — Factions and reputation

**Purpose:** Make target selection and allegiance consequential.

**Scope:** The principal colonial powers, faction standings, privateering opportunities, rewards, hostility, and an initially bounded model of changing relationships. Connect standings to port access and naval encounters. Decide how allied players with different reputations interact.

**Dependencies:** Exploration, ports, capture, trade, and crew recovery paths.

**Completion gate:** A captain can explain why an action changes standing and how that standing affects future opportunities. Cooperation and rivalry remain understandable even when captains support different factions.

#### Phase 11 — Missions and quests

**Purpose:** Layer directed adventures onto a self-directed world.

**Scope:** A small mission set using existing travel, combat, trade, and faction systems; readable objectives and rewards; and modest linked quests. Define shared versus personal objectives, participation credit, competing claims, and interruption or failure behavior.

**Dependencies:** A persistent world and the campaign systems that give objectives consequences.

**Completion gate:** Players can find, pursue, complete, fail or abandon, and resume objectives in both modes. Rewards are issued correctly, and authored goals coexist with spontaneous opportunities rather than forcing a single route through the game.

#### Phase 12 — Captain progression

**Purpose:** Give captains distinct identities and meaningful development.

**Scope:** A bounded progression model and skill choices spanning already-playable activities. Connect growth to accomplishments and meaningful decisions. Consider the reference game's equipment, specialists, reputation, and player mastery alongside any new skill system.

**Dependencies:** Enough activities to support different play styles and rewards.

**Completion gate:** Captains can develop viable specializations without making tactical skill irrelevant. Progress persists reliably, and mixed-progression friends can participate meaningfully under the campaign's cooperation and competition rules.

#### Phase 13 — Voyages and career

**Purpose:** Turn the growing sandbox into a complete pirate-career experience.

**Scope:** Dividing plunder, voyage transitions, recorded accomplishments, and a satisfying career conclusion or retirement. Decide how aging, passage of months, new captains, and ongoing shared worlds interact rather than copying single-player time jumps directly.

**Dependencies:** Economy, crew pressure, factions, goals, progression, and campaign persistence.

**Completion gate:** A player can live a coherent compact pirate career—from a beginning through setbacks and accomplishments to a conclusion—and choose to begin again. A captain's retirement or departure has defined consequences for companions and the shared world.

**Milestone:** This is the first complete compact offline/shared pirate-career game, distinct from the Phase 2 naval MVP.

#### Phase 14 — Boarding duels

**Purpose:** Add personal swashbuckling to consequential naval encounters.

**Scope:** A focused captain-versus-captain duel integrated with boarding, crew state, ship capture, and defeat. Establish the relationship between player ability, character progression, and accessibility. Resolve what other captains can do while a duel occurs.

**Dependencies:** Capture, crew, progression, and stable shared-world encounter rules.

**Completion gate:** Duels improve the adventure rather than become repetitive mandatory interruptions. Outcomes are understandable in solo, cooperative, and competitive situations, and uninvolved players are not left with unacceptable waiting time.

#### Phase 15 — Treasure hunting

**Purpose:** Reward curiosity, navigation, and interpreting clues.

**Scope:** Map fragments or comparable clues, recognizable landmarks, bounded shore exploration, discovery, and rewards. Define shared discoveries and ownership so cooperative exploration and rival claims have intentional outcomes.

**Dependencies:** Geography, persistence, quests, and reward rules.

**Completion gate:** Players can locate a treasure by interpreting clues rather than following only a waypoint. Discovery is satisfying, does not become a repetitive chore, and remains consistent when participants arrive or resume at different times.

#### Phase 16 — Broader Caribbean

**Purpose:** Expand a proven experience into the intended wider setting.

**Scope:** More geography, ports, vessels, weapon/ammunition variety, encounters, missions, and regional character. Expand variety and replayability using the existing systems. Review content production capacity and travel pacing before each geographic or content increase; additional historical eras require their own justification.

**Dependencies:** The complete compact career and proven signature activities.

**Completion gate:** The broader Caribbean offers meaningful differences and routes rather than empty travel or repeated chores. Performance, navigation clarity, content quality, and shared-session pacing remain acceptable on supported platforms.

#### Phase 17 — Release readiness

**Purpose:** Make the accumulated game dependable, learnable, and coherent.

**Scope:** Balance, onboarding, accessibility, interface consistency, cohesive art/audio, save reliability, multiplayer recovery, performance, packaging, and sustained cross-platform playtests. Set concrete release criteria in the phase's detailed plan using the actual game's scope and intended audience.

**Dependencies:** Accepted core phases, a stable release scope, and evidence from earlier platform and playability checks.

**Completion gate:** New players can learn and complete the game; returning groups can reliably resume it; offline play works without a multiplayer service dependency; and Windows, macOS, and Linux builds meet the agreed release criteria. Known limitations are explicit and compatible with that scope.

### 4. Optional expansion candidates

These are candidates, not hidden commitments or prerequisites for the core release. Evaluate each separately after the core campaign works; an accepted candidate becomes its own phase with a player outcome and completion gate.

| Candidate | Question it must answer |
|---|---|
| Land battles and town conquest | Does territorial conflict add worthwhile strategic choices without turning the project into a separate strategy game? |
| Stealth and infiltration | Does entering hostile towns create engaging choices that existing diplomacy, combat, or quests cannot provide? |
| Romance and social relationships | Can relationships strengthen the captain's story with enough variety and agency to justify their content cost? |
| Dancing or other social minigames | Is the activity enjoyable and accessible in repeated play, and does it fit shared-session pacing? |

Other ideas remain in an evaluated backlog. They do not enter the roadmap simply because the project is intended to become large.

### 5. Cross-cutting commitments

- **Offline independence:** The standalone game remains playable without joining or depending on a multiplayer service. Exact save portability between modes is a separate decision.
- **Shared-campaign consistency:** Each persistent feature defines ownership, simultaneous actions, participation, save/resume, and disconnection behavior when introduced.
- **Cooperation and competition:** Naval matches establish the combat proof; campaign phases progressively establish rewards, property loss, faction rivalry, quest credit, and progression fairness.
- **Player pacing:** Towns, battles, duels, and shore activities must account for independently moving captains. Resolve each transition before expanding the activity.
- **Cross-platform delivery:** Verify executable builds at the naval milestone and continue representative platform checks. Establish supported versions and hardware targets during detailed planning; do not defer portability discovery to release polish.
- **Performance, loading, and tiny files:** Set budgets in Phase 1 and verify them from the Phase 2 playable build onward on supported platforms. Track runtime performance, cold-start and encounter waits, and total compressed/download and installed sizes, including required dependencies. Recheck as content grows; a missed budget requires optimization, scope reduction, or an explicit approved revision before the milestone closes. Do not postpone these goals to release polish.
- **Production quality:** Start with clear placeholder presentation and a small content set. Build coherent art, animation, audio, interface, and content workflows as needed; final polish refines these rather than creating them from nothing.
- **Accessibility and usability:** Readability, remappable input expectations, understandable feedback, and appropriate difficulty are considered from the first playable milestone and revisited as activities expand.
- **Human verification:** AI-generated work still requires observed play, integration checks, and human judgment about whether the game is enjoyable.
- **Scope discipline:** Each phase adds one principal capability. Foundational work stays proportionate to the next playable milestone; later content and optional systems wait for demonstrated need.

#### Testing environment and headless validation

The current Linux development machine can support substantial automated testing without a full desktop environment. Its initial capability check found no active X11/Wayland display session, Intel UHD integrated graphics (CometLake-H GT2), and an NVIDIA RTX 2070. `vulkaninfo --summary` enumerated both GPUs, and `eglinfo -B` successfully created hardware-backed OpenGL contexts on both through EGL device access; NVIDIA surfaceless rendering was also available. These are graphics-stack findings, not proof that a selected game engine or Tortuga build renders correctly or meets performance targets. Recheck the environment and active renderer before future measurements.

| Validation area | Approach and limits |
|---|---|
| Simulation and server behavior | Run automated combat-rule, AI, save/load, connection, disconnect, and pause-when-empty checks without graphics as those systems become available. |
| Graphics and interface | Validate the selected engine's offscreen rendering or minimal virtual-display path, then capture frames and exercise scripted input. An engine's headless mode may disable rendering entirely; logic-only runs do not validate visuals. A full desktop is not inherently required. |
| Performance and loading | Explicitly select and record the Intel hardware renderer for the integrated-graphics baseline, with resolution, drivers, power mode, and workload. RTX 2070 results and CPU-based `llvmpipe` results are separate measurements, not substitutes. Offscreen timing does not fully validate display presentation, VSync, or input-to-display latency. |
| Packaging and resources | Measure download/installed sizes, required dependencies, CPU, and memory; measure graphical startup and loading only through a verified rendering path. |
| Desktop and human validation | Use real desktop sessions for fullscreen/focus, display scaling, controllers, audio experience, and human judgments of responsiveness and enjoyment. |
| Platform coverage | Linux and macOS testing access is available; Mac runs are user-assisted until another access method is established. Windows runtime access remains unresolved. Cross-compilation or a successful package export does not satisfy native runtime verification on any platform. |

Phase 1 should establish the minimal engine-compatible rendering setup rather than assume a full desktop installation is needed. Xorg and capture tools were present at the initial check; Xvfb was absent. Any virtual-display or offscreen setup must identify whether it uses hardware acceleration or software rendering. These host findings inform the feasibility probes; Phase 2 still requires runnable verification on Windows, macOS, and Linux, together with human playtests.

### 6. Main risks and responses

| Risk | Roadmap response |
|---|---|
| Early naval play is not compelling | Phase 2 is a real stop/iterate gate before investment in campaign breadth. |
| Multiplayer arrives early and slows progress | Limit Phases 3–4 to naval sessions; prove them before expanding persistent systems. |
| Solo pause/time assumptions conflict with independent captains | Address the session model in Phase 1, shared-world time in Phase 5, and activity-specific pacing when each activity arrives. |
| The game becomes a naval arena and loses the captain's-life identity | Preserve the campaign phases and their links; Phase 13 explicitly gates a complete pirate career. |
| The project accumulates too many minigames or too much content | Selective revival, one-feature phases, and a bounded region precede expansion. |
| Progression, trade, or PvP create dominant strategies | Playtest player choices and consequences at the owning phase, including mixed progression and simultaneous actions. |
| Asset production exceeds solo capacity | Research production scope early, use small representative sets, and expand only after the content workflow is practical. |
| Engine overhead or growing assets undermine fast loading and tiny files | Establish budgets and representative feasibility measurements in Phase 1; check packaged builds from Phase 2 onward before increasing content scope. |
| Platform or persistence problems emerge late | Verify portability early and campaign saving when persistent exploration is introduced. |

### 7. Research sources

All sources below were consulted for this planning pass on 2026-09-29. Manual references use printed page numbers, not PDF sheet numbers.

- **[R1] Wikipedia — *Sid Meier's Pirates!* (1987).** Series origins, open-ended gameplay, dynamic setting, career structure, and *Pirates! Gold* context. <https://en.wikipedia.org/wiki/Sid_Meier%27s_Pirates!>
- **[R2] Wikipedia — *Sid Meier's Pirates!* (2004 video game).** Edition and port distinctions, main gameplay systems, and reception overview. <https://en.wikipedia.org/wiki/Sid_Meier%27s_Pirates!_(2004_video_game)>
- **[R3] Official PC manual, distributed through Steam.** Primary reference for intended game rules, especially pp. 7–8, 10–12, 17–55, 56–83, and the ship/crew/commodity reference sections. <https://store.steampowered.com/manual/3920>
- **[R4] The Guardian — Sid Meier interview, “Learning is part of any good video game” (2015).** First-person design testimony about pirate fantasy and centering the player's enjoyable role. <https://www.theguardian.com/technology/2015/feb/27/civilization-sid-meier-interview-starships>
- **[R5] Eurogamer — Kieron Gillen's PC review.** Analysis of interconnected short/long-term goals, naval tactics, repetition, and travel pacing; used as critical perspective, not universal player consensus. <https://www.eurogamer.net/r-pirates-pc>
- **[R6] Eurogamer — Tom Bramwell's Xbox review.** Contemporary description of the up-to-four-player naval versus mode, distinct from a shared campaign. <https://www.eurogamer.net/r-pirates-x>
- **[R7] Steam product page.** Publisher-provided description of the pirate-life fantasy and the PC product's single-player feature listing. <https://store.steampowered.com/app/3920/Sid_Meiers_Pirates/>

Further Phase 1 reading: the original manual and Captain's Broadsheet are available through the C64Sets archive. The archive index was checked, but its manual contents were not reviewed in this pass: <https://www.c64sets.com/set.html?id=24>.

▼

## Open Questions

These are deliberately deferred decisions with an owning phase. Resolve each before its dependent work begins; do not turn the master plan into a detailed feature specification to answer them now.

| Decision | Owning phase / latest resolution point |
|---|---|
| ~~Which initial Caribbean region and bounded historical period fit the compact adventure?~~ Resolved in Phase 1: northern Leeward Islands, c. 1660–1680. | Verify historical island ownership and refine geography for Phase 5. |
| ~~Which engine, tools, and asset approach meet the solo workflow and three-platform target?~~ Resolved in Phase 1: Godot 4.7.2, top-down 2D sprites, CC0 or original assets. | Windows and macOS runtime still unverified; Phase 2 gate. |
| What are the minimum hardware, OS, and initial input targets? | Hardware floor set in Phase 1: a 2020-class Intel UHD laptop at 1080p. OS versions, a Mac baseline, and input devices remain for Phase 2 verification. |
| ~~What frame-time, memory, loading-time, download-size, and installed-size budgets apply?~~ Resolved in Phase 1: see the approved budgets table in the dossier. | Verify from Phase 2 onward and revisit explicitly when scope changes. |
| What server operating requirements and participant persistence support the agreed dedicated-server, 2–4-captain envelope? | Phase 1 found a Linux headless server feasible at under 100 MB for 4 clients; persistence was not exercised. Finalize session rules for Phase 3. |
| How do shared time, independent movement, encounter boundaries, and campaign ownership work? | Phase 1 constraints recorded in the dossier; finalize and validate in Phase 5. |
| What happens when a participant disconnects or the dedicated server stops, and what is required of reconnect/resume? | Phase 3 session rules; Phase 5 persistent-world rules. |
| Can an offline campaign later become multiplayer, or move between servers? | Phase 5; offline and multiplayer support alone does not promise save conversion. |
| What are the port safety, campaign PvP consent, loot-sharing, and loss/recovery rules? | Phase 6 for port safety; Phase 7 for prizes and player property. |
| How much economic simulation is useful before it becomes work rather than adventure? | Phase 8. |
| Which faction changes are simulated, and how does divided allegiance affect a group? | Phase 10. |
| How should character growth coexist with player skill and mixed-progression friends? | Phase 12. |
| Should aging be mandatory, optional, or replaced, and how does one captain retire without ending everyone else's game? | Phase 13. |
| How should duels and treasure discoveries handle uninvolved or competing players? | Phases 14 and 15 respectively. |
| What release audience, distribution approach, budget, and presentation bar are realistic? | Establish production assumptions in Phase 1; revisit before Phase 16 expansion and Phase 17 release planning. |

**Next step:** Phase 1 is accepted. Write the Phase 2 specification and implementation plan for the offline naval MVP from the brief in the [dossier](docs/research/phase-1.md). This master plan does not authorize immediate implementation of every listed feature.
