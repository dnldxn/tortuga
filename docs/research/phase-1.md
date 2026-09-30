# Phase 1 — evidence setup, Linux inventory, and naval desk research

**Status: Phase 1 accepted by the owner on 2026-09-30.** Reference footage was visually observed (no audio heard). Godot 4.7.2 was probed and measured on Linux and is the selected engine; the budgets below are approved. Nothing has run on Windows or macOS; those runs are Phase 2 gates. The approved 60 FPS at 1080p investigation is a feasibility question, not an achieved result or minimum-spec promise.

## Authority and evidence conventions

- Retrieved the authoritative [spec #1](https://github.com/dnldxn/tortuga/issues/1) and [execution plan #2](https://github.com/dnldxn/tortuga/issues/2) at execution start, 2026-09-30 approximately 06:28 UTC. Their `updatedAt` values were `2026-09-30T05:57:02Z` and `2026-09-30T06:08:33Z`, respectively. The planning date remains 2026-09-29; this record uses the executing host's UTC clock.
- Read both roadmap files at `main`, revision `d1a9880254fe9280d7de939e8b065cf24df82153`. The existing uncommitted headless-testing addition in `MASTER-PLAN.md` is user work; its starting Git blob hash is `945e960829f276162a50d03313ac96d63e6cdde9`. It is preserved without editing. This is the first slice within the approved overall plan; later tasks are already authorized subject to their evidence and decision gates.
- Reproduction commands, sanitized results, source fingerprints, and limitations are in the [runbook](evidence/phase-1/runbook.md). No timing/asset CSV or capture placeholder was created: there are no game measurements or selected assets to populate one.

Two independent evidence axes apply:

| Status | Meaning in this dossier |
|---|---|
| **measured** | Actually retrieved host state or directly checked bytes in this pass; scope and sample conditions stated. Does not imply game performance. |
| **documented-but-unmeasured** | A consulted document or attributed prior/user report supports the claim; corresponding behavior was not exercised here. |
| **estimated** | Explicit inference or provisional recommendation; no empirical validation or owner approval implied. |
| **blocked** | Required evidence/access is missing; identify the next action and gate. |

Source kinds are **manual**, **secondary context**, **testimony**, **observed footage**, **host inventory**, or **interpretation**. Observed-footage entries are the `O` rows below; the `C` rows remain documentary. High confidence in what a manual says is not high confidence that every released build behaves that way.

## Accessible machine and platform ledger

Inventory ID **LNX-01**, collected during 2026-09-30 06:28–06:31 UTC via the agent's local shell and read-only system-file tools; no sudo, configuration changes, or graphics-context probes. Values are snapshots, not controlled benchmark conditions.

| Area | Actual finding | Status / limit |
|---|---|---|
| Machine / access | Eluktronics Inc. MAX-17, DMI version `Standard`; local Linux shell available | **measured**; physical/user desktop testing still requires coordination |
| OS | Fedora Linux 44 (KDE Plasma Desktop Edition), x86_64; running kernel `7.2.4-200.fc44.x86_64` | **measured**; OS edition does not establish an active desktop session |
| CPU | Intel Core i7-10875H @ 2.30 GHz; 1 socket, 8 cores, 16 logical CPUs online | **measured**; not evidence of the target low-end laptop envelope |
| Integrated GPU | Intel CometLake-H GT2 [UHD Graphics], DRM `i915`; Mesa DRI/Vulkan packages `26.1.8-1.fc44.x86_64` | **measured** inventory; candidate integrated-GPU test path, not a selected/verified game renderer |
| Discrete GPU | PCI description TU106M [GeForce RTX 2070 Mobile / Max-Q Refresh]; NVIDIA reports GeForce RTX 2070, driver `610.57.04`, 8192 MiB VRAM | **measured**; separate faster surrogate, never substitute for Intel results |
| RAM | OS-visible total 33,457,631,232 bytes (~31.16 GiB); available 29,458,345,984 bytes at sample; swap total 8,589,930,496 bytes, unused | **measured** system inventory, not client/server memory consumption or installed-DIMM verification |
| Storage | Intel SSDPEKNW512G8 NVMe, 512,110,190,592 bytes, non-rotational; project filesystem Btrfs, reported size 335,511,814,144 bytes and available 131,532,595,200 bytes | **measured** capacity/free space only; no I/O or loading benchmark |
| Power | AC online; battery 98%, `Not charging`; CPU policy0 `intel_pstate` / `powersave` / energy preference `power` | **measured** partial policy; `powerprofilesctl` missing and ACPI platform-profile file absent. No confirmed overall performance mode or sustained thermal state |
| Display | Intel `card1-eDP-1` connected/enabled; supported-mode list contains `1920x1080` twice; all four listed NVIDIA connectors disconnected | **measured** connector state, not active graphical resolution, refresh rate, scaling, VSync, or presentation validation |
| Session / input | `DISPLAY` and `WAYLAND_DISPLAY` unset; `XDG_SESSION_TYPE=tty`. Kernel lists AT keyboard and UNIW mouse/touchpad; no gamepad name in the inspected list | **measured** enumeration only; no input delivery, remapping, controller, or human responsiveness test |
| Earlier headless stack | User/master addition and recalled prior check report Vulkan enumeration of Intel, NVIDIA, and llvmpipe, hardware EGL device contexts on both GPUs, and NVIDIA surfaceless success | **documented-but-unmeasured in this pass**, inherited verified-stack report. No retained raw prior log here and no rerun; not game-render proof |
| macOS | User-assisted access reported; model, chip, OS, RAM, display, storage, input, power policy unknown | Access **documented-but-unmeasured**; inventory, explicit baseline, and runtime **blocked** pending user outputs |
| Windows | No native runtime machine/tester currently available | **blocked**; owner must confirm access and tester, then inventory before native execution |

No supported OS range, minimum hardware, Mac baseline, or input-device target is approved from this inventory. Before any later Linux graphics measurement, explicitly select and verify the Intel hardware renderer, record the actual render size and power/cache/workload conditions, and reject accidental RTX/llvmpipe substitution. Offscreen rendering, display presentation, and logic-only headless execution are different evidence paths.

## Sources consulted and inherited

All new consultations below occurred on **2026-09-30 UTC**. Roadmap source IDs are retained.

- **R3 — primary PC manual:** newly consulted selected passages using `/tmp/opencode/tortuga-pirates-2004-manual.txt`. The [Steam manual URL](https://store.steampowered.com/manual/3920) resolved at `06:29:46Z` to a [Steam CDN PDF](https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/3920/manuals/manual.pdf?t=1777585034). Its 1,315,110 bytes match the local PDF, SHA-256 `d335ca09a46a071206d05ccb93d80af770cc7c5c2606077f1df422cde7c640f1`; direct CDN retrieval at `06:30:58Z` confirmed the same bytes. Fresh `pdftotext -layout` output exactly matches the inherited text. This is the manual for the 2004 PC game, with layout stamp `6/6/05` and PDF modification metadata in 2006, not a proven launch-day manual/build. Printed pages differ from PDF sheets. A text-mode web fetch exposed a different PDF header (73 sheets); locators here refer only to the byte-verified **72-sheet** revision. See runbook for reproduction and offsets.
- **R2 — secondary context:** newly reopened [Wikipedia, *Sid Meier's Pirates!* (2004 video game)](https://en.wikipedia.org/wiki/Sid_Meier%27s_Pirates!_(2004_video_game)); returned page identifies revision [1368363894](https://en.wikipedia.org/w/index.php?title=Sid_Meier%27s_Pirates!_(2004_video_game)&oldid=1368363894). Consulted introduction, Gameplay, Sailing, Naval battles, and Ship capture and prizes. Its citation-warning banner and mixed-platform coverage limit mechanical authority.
- **R1, R4–R7:** inherited roadmap references only, **not reopened** in this pass (1987 Wikipedia, Meier interview, PC/Xbox reviews, Steam product page). Their summaries are not new observations or newly verified testimony. No claim here depends on re-reading them. The 1987 manual/Broadsheet remains unconsulted.

### Compact claim table

`M` = manual, `S` = secondary context, `I` = interpretation. All R3 page locators are **printed pages**; parenthetical sheets are 1-based PDF positions in the pinned revision. Source titles/URLs, edition, revision, and access date are defined above for every row.

| ID | Claim / source locator | Kind; status; confidence | Conflict or limitation | Tortuga implication (provisional unless already in roadmap) |
|---|---|---|---|---|
| C01 | R2 introduction / release list: Windows release 2004; Xbox and other ports later; Xbox has multiplayer capabilities | S; **documented-but-unmeasured**; medium | Mixed-edition article; no footage authenticated | Confirm PC edition visibly before treating a recording as reference behavior |
| C02 | R3 pp. 17–21 (sheets 9–11): ship-centered navigation, wind indicators, helm controls, full/reefed sails; hull/rig affect best sailing direction; low crew reduces effectiveness; attack via nearby target or collision | M; **documented-but-unmeasured**; high for intended rules | No measured handling curves, upwind duration, or camera readability | Preserve legible wind/handling decisions; validate travel pace and controls in playtests |
| C03 | R3 pp. 32–33 (sheet 17): full sails faster/more vulnerable; reefing tighter/slower; port/starboard broadsides, closest available target, stronger bow/stern raking; crew-dependent automatic reload and partial volleys | M; **documented-but-unmeasured**; high | No measured aim assistance, arcs, turning radius, or reload timings | Core maneuver/fire trade-offs merit Phase 2 investigation without copying hidden constants |
| C04 | R3 pp. 33–35 (sheets 17–18): round shot longest range, mainly hull/cannon; chain medium range, mainly sails; grape short range, mainly crew; collateral damage possible. Hull/sail damage impairs handling; crew losses slow reload | M; **documented-but-unmeasured**; high | Availability depends on ship/upgrades; no balance measurements | Test minimal readable damage/ammo distinctions; full variety remains later scope |
| C05 | R3 pp. 35–37 (sheets 18–19): boarding leads to duel; capture retains ship/cargo/gold/specialists; sinking loses carried value; distance/nightfall can end combat; plunder returns to navigation | M; **documented-but-unmeasured**; high | Exact surrender thresholds and transitions unobserved | Preserve distinct outcomes as a design aim; persistent prizes Phase 7, playable duels Phase 14 |
| C06 | R3 p. 35 says destroyed sails **may** cause surrender on approach; R2 Naval battles says dismasted enemies **always** surrender, except escorts | M + S; **documented-but-unmeasured**; high that wording differs, low on runtime resolution | Partly narrowed by O07: two PC surrenders observed with sails only partly damaged, so dismasting is not required. A fully dismasted enemy and an escort were not observed, so "may" versus "always" is still open | Do not encode guaranteed surrender. Recommended research revision for owner acceptance: stop chasing the reference constant and let Phase 7 define Tortuga's own surrender rule |
| C07 | R3 pp. 12, 21, 82 (sheets 7, 11, 42): manual pause; information/menu/conversation time freezes; campaign day takes a few seconds traveling, several minutes in sea combat; duels, land combat, buying/selling/plundering stop campaign time | M; **documented-but-unmeasured**; high | Manual's approximate rates are not timings measured here. Action in a duel is not thereby motionless | Distinguish campaign time, real-time action, and user pause; shared time cannot inherit every single-player freeze |
| C08 | R3 pp. 81–82 (sheets 41–42): new voyage after dividing plunder skips months (about six); prison/marooning also advances months | M; **documented-but-unmeasured**; high | No observed transition or player waiting-time measurement | Career/recovery time jumps require shared-world design; defer career implementation to Phase 13 |
| C09 | R3 pp. 21–23, 37–39 (sheets 11–12, 19–20): port entry/fleet decisions connect to prizes; faction/city opinion changes access, trade/recruiting opportunities and hostility | M; **documented-but-unmeasured**; high | Targeted linkage reading only, not complete economy/crew/quest research | Keep naval MVP bounded while retaining campaign ownership of consequences |
| C10 | C02–C09 plus spec #1 imply readable naval choices and shared-time compatibility deserve early tests | I; **estimated**; provisional | Documentary synthesis, not a validated design pillar or approved Phase 2 brief | Use as questions for the next research slice, not settled mechanics |

### Provisional preserve / modernize / defer assessment

| System relationship | Documentary recommendation | Evidence / roadmap owner |
|---|---|---|
| Wind → maneuver → broadside/reload → damage | **Preserve** the simple, visible tactical trade-offs; **modernize** input remapping and state feedback provisionally | C02–C04; Phase 2; feel/readability still need observation and human testing |
| Win/lose/escape → capture/value → return to port | **Preserve** differentiated consequences; **defer** persistent prizes, cargo and services from naval MVP | C05, C09; Phases 6–8; Phase 2 only encounter outcomes/replay |
| Crew → speed/reload → voyage pressure | **Preserve** only necessary encounter-level effects initially; **defer** upkeep/recruiting economy | C02–C04; Phase 2 minimal distinctions, Phase 9 full crew management |
| Menus/encounters/time jumps → independent captains | **Modernize** time/authority assumptions; do not pause everyone because one captain opens a menu | C07–C08; Phase 1 constraints, Phase 3 sessions, Phase 5 campaign, Phase 13 career |
| Boarding victory → personal duel | **Defer** playable duels; no parity commitment in naval MVP | C05; Phase 7 bounded capture resolution, Phase 14 duels |

### Wider system claims and relationship assessment

Second manual pass, 2026-09-30, same byte-verified R3 revision; extracted text lines 572–796 and 1008–2197 read in full. All rows are `M`, **documented-but-unmeasured**, high confidence for intended rules unless an `O` row is cited. Commodity and price tables (pp. 111–112) and the ship gazetteer (pp. 97–107) were not reopened.

| ID | Claim / printed pages |
|---|---|
| C11 | pp. 26–27: crew grow restless with voyage length and difficulty level; ignoring the call to divide plunder lowers morale, then causes desertion or theft of a spare ship. Food is tracked in months; starvation lowers morale and causes desertion. A cook stretches rations |
| C12 | pp. 28–31: ships on the map show nationality by flag and role by hull color; attack by key or by running into the ship; a confirmation pop-up picks the target or cancels (seen in O04). Pursuers fire on the map until the player flees, enters a harbor, or fights. Escape by finding a faster point of sailing or ducking into port |
| C13 | pp. 40–44: the boarding duel runs alongside a crew battle; each moves the other. Crew size, morale, and duel progress decide losses; a captain whose crew is down to one man surrenders on the next hit |
| C14 | pp. 45–50: eight city types from size, wealth, and defenses. City menu: governor, tavern, merchant, shipwright, divide the plunder, status, sail away (seen in O14). Governors issue Letters of Marque, promotions, amnesty for a price, missions, and information. Taverns supply crew, gossip, upgrade locations, and map pieces. Settlements, Jesuit missions, pirate havens, and Indian villages are poorer variants that move between games |
| C15 | pp. 70–72: rank is per nation and needs a Letter of Marque. Each rank gives one concrete benefit in that nation's ports: easier recruiting, cheaper then free repairs, more goods, cheaper then free upgrades. Acting against a nation suspends the benefits but keeps the rank for Fame |
| C16 | pp. 73–78: quests are long, untimed, and carry no failure penalty; missions are one or two steps, sometimes timed, also without penalty. Villains may move on if the player is slow. Nine named pirates hold a Top Ten list the player climbs; beating one sends him to the bottom |
| C17 | pp. 51–69: treasure maps assemble from fragments and use landmarks that move between games; land parties consume food and morale. Land battles are turn-based and need 50 men. Sneaking and dancing are separate minigames |
| C18 | pp. 79–80: dividing plunder is advised when the crew demands it or to bank a large haul; it can be done in any city or haven |

| System | Relationship to naval play | Recommendation | Rationale | Roadmap owner |
|---|---|---|---|---|
| Sailing | Wind and point of sailing decide who can catch or escape whom (C02, C12, O11) | **Preserve** wind as the core variable; **modernize** with clearer wind and heading feedback | It is the one input every other naval choice depends on | Phase 2 |
| Combat and capture | Damage type chosen sets the outcome: sink, surrender, or board (C03–C05, O07–O09) | **Preserve** the three-way outcome; **modernize** so closing to board is not always best (O05) | The reference footage shows boarding dominating weak targets | Phase 2 outcomes; Phase 7 persistence |
| Boarding duel | Crew numbers and morale carry into the duel (C13, O08) | **Defer** the duel; resolve boarding from crew numbers until then | A second real-time game is out of MVP scope | Phase 7 simple resolution; Phase 14 duel |
| Ports | The only place damage, crew, and cargo are converted back into readiness (C14, O14) | **Preserve** the compact menu hub; **modernize** so one captain in port never stops the world (O04) | A menu hub is cheap to build and already proven readable | Phase 6 |
| Economy | Cargo capacity and prize sale make capture worth more than sinking (C05, O13) | **Preserve** the link; **defer** markets | No economy is needed to test maneuvering | Phase 8 |
| Crew | Crew size drives reload and boarding; food and morale limit voyage length (C03, C11, O06) | **Preserve** crew as the reload and boarding stat in the MVP; **defer** food, morale, and desertion | Only the encounter-level effect changes a naval decision | Phase 2 minimal; Phase 9 full |
| Factions | Target choice changes which ports help or shoot at you (C09, C15) | **Preserve** per-nation standing with concrete benefits; **defer** | Needs ports and persistence first | Phase 10 |
| Quests and discovery | Give reasons to sail somewhere specific (C16, C17) | **Preserve** untimed, penalty-free goals; **defer** | Depend on a persistent world | Phases 11, 15 |
| Progression and career | Rank benefits, Fame, and dividing plunder pace a career (C08, C15, C18) | **Modernize**: months-long skips and aging cannot be copied into shared time | Conflicts directly with independent captains | Phases 12, 13 |
| Character activities | Land battles, sneaking, dancing sit beside naval play (C17) | **Defer**; evaluate each on its merits | Master plan already treats them as optional candidates | Optional expansion |

This completes the system relationship table required by plan task 3. No initial region/period, art direction, vessel count, or engine is selected.

## Footage ledger and observations

Observer: the vision-capable agent session of 2026-09-30, approximately 06:55–07:10 UTC, reading still frames extracted with ffmpeg. The earlier session's image-read failure is superseded. **Frames were seen; no audio was heard; nothing was played back in motion.** Timestamps are recording time in `mm:ss`, read from stamps burned in from the source frame time. Reproduction commands and file hashes are in runbook section H.

| ID / source | Provenance and edition evidence | Editing and limits |
|---|---|---|
| F01 — [10min Gameplay](https://www.youtube.com/watch?v=_aFLduBaVeU) | 600.07 s. Uploader title "(PC) [2004] Gameplay", uploaded 2021-12-22; description states Windows PC on Win XP 32-bit, Core 2 Duo E4300, Radeon HD 2600 PRO, Elgato capture. Visible: sword-shaped pointer, an on-screen 3×3 action panel numbered 1–9 like a numeric keypad, no controller glyphs. **PC edition, high confidence** | **Edited.** Dissolves and a black frame inside the Nevis town menu at 01:31.7–01:34.2 remove the tavern and merchant visits (gold 1204→913, crew 69→103, date Feb 9→Feb 16 across the gap). Title card 00:00–00:03.5. No hard cut was detected inside any sea battle, but dissolves cannot be ruled out. Patch, difficulty, and mods unknown |
| F02 — [Thrym865 Ship of the Line fight](https://www.youtube.com/watch?v=Maj8TjrkVd4) | 215.3 s, uploaded 2011-07-26. Title states Swashbuckler difficulty; description lists the player's seven ship upgrades. Platform not stated by the uploader; HUD layout, fonts, pointer, and target prompt match F01. **PC edition, medium-high confidence from UI match** | Hard-cut detection found only two cuts (02:52.9 surrender scene, 03:06.0 map), so the battle from 00:02.4 to 02:52.9 appears continuous. Patch and mods unknown; a fully upgraded late-career ship is not a typical encounter |
| F03 — [G4 review archive](https://archive.org/details/g4tv.com-video15505) | Contact sheet inspected. The 00:50 frame reads "Only on PlayStation Portable"; gameplay frames at 01:00, 01:20, and 02:40 show PSP face-button prompts. **PSP edition** | **Rejected as PC reference.** Not used for any behavioral claim |

### Observation table

Status for every row is **measured** in the narrow sense of "read from frames of the named recording"; it says what that recording shows, not what every build does. Intervals sampled at 10 s (F01) or 5 s (F02) carry that uncertainty unless a denser figure is given.

| ID | Recording, time | What the frames show | Limits | Tortuga implication (provisional) |
|---|---|---|---|---|
| O01 | F01 00:04–01:25 | One full loop: sail → target prompt → battle → boarding duel → plunder screen → news dialog → back on the map with the prize following | Single easy target | The loop the MVP brief must reproduce in miniature, minus duel and persistent prize |
| O02 | F01 00:21.37→00:21.57 | Prompt is still on screen at 21.37 s; the battle view with full HUD is up at 21.57 s. No loading screen | One sample, 2007-era PC | Encounter entry is effectively instant; a useful bar for the transition budget |
| O03 | F01 00:04.8–00:11.3, 01:22–01:29; F02 03:06–03:32 | Map date advances about one day per 3–3.7 s of sailing | Short windows; F02 ends on "Paused" | Matches C07's "a few seconds" per day |
| O04 | F01 00:14.2–00:21.4 | While the target prompt is open the map is frozen: ships and frame are identical for about 7 s | — | A modal prompt that freezes the world cannot carry over to shared play (C07) |
| O05 | F01 five battles; F02 one | Gunnery/approach phase lasted about 20 s, 76 s, 20–30 s, 15–25 s, and 10–20 s in F01, and 170 s in F02. Four of the five F01 battles ended in boarding after little or no gunnery | F01 figures other than the first two are from 10 s sampling | Against weak targets, closing to board looks dominant. Phase 2 must test for exactly that dominant maneuver |
| O06 | F02 00:12.5–00:27.5, 01:37.5–01:47.5, 02:41.6–02:52.9; F01 00:26.2–00:32.2 | "N guns loaded" counter climbs back after a volley: 48 guns in roughly 6–10 s with 385 crew; 8 guns in about 6 s with 54 crew. A volley fired at 29 of 48 loaded | Counter read at 1.5–5 s steps | Confirms C03 partial volleys; reload is short relative to a turn |
| O07 | F01 03:04–03:07; F02 02:52.9–02:55.1 | Two surrenders on approach ("the enemy strikes her colors"). F01: enemy barque at 5 guns, 49 crew versus the player's 101; plunder screen reads hull damage 35%, sail damage 45%. F02: enemy at 24 guns, 5 crew versus 385; plunder screen reads both damage values in the 70s (second digit illegible) | No fully dismasted enemy, no escort | Surrender happens without dismasting; see C06 |
| O08 | F01 00:44, 04:13, 06:40, 08:45 | Four boardings led to duels, including one where the enemy had 0% hull and sail damage and outnumbered the player 97 to 49 | — | Boarding an undamaged ship goes to a duel, consistent with C05 |
| O09 | F02 00:02–02:53 | Enemy stats fall in steps on the HUD: 48 guns/150 crew → 44/142 → 36/117 → 24/101 → 24/5; enemy speed falls from 14–17 knots to 1–3. Player stays at 48 guns/385 crew throughout. Enemy masts are visibly bare by 02:28 | Fully upgraded player ship | Hull, sail, and crew damage are separately legible from numbers and from the model |
| O10 | F01 00:27.7; F02 02:25.9 | The loaded-guns box is replaced by "Out of Round Shot range" / "Out of Chain Shot range" | Grape shot not seen in use | Range feedback per ammunition type is explicit (C04) |
| O11 | F01, F02 battle HUD | Both ships' name, guns, crew, and speed at top; upgrade icons below; a compass rosette bottom-left with its own knots figure that differs from the ship's speed (13 versus 5 at F01 00:24.7), which reads as wind; wind streaks on the water; camera tightens as the ships close | Wind reading is inference | A small always-visible HUD carries the whole tactical state |
| O12 | F02 00:02→02:53; F01 01:55→03:04 | Lighting moves from day to dusk to night during a battle; F02 continues fighting in darkness for about 90 s | Whether nightfall ended any fight was not seen | C05's nightfall ending is not contradicted, only unobserved |
| O13 | F01 01:12, 03:16, 04:34; F02 03:01 | Plunder screen: two-column cargo transfer, Take All, keep-or-sink choice with "we need N of our M available crew to keep her sailing". After surrender, enemy sailors offer to join | — | Prize, cargo, and crew are linked at the moment of capture (C05, C09); all later-phase scope |
| O14 | F01 05:04–06:00 | Town menu: Governor, Tavern, Merchant, Shipwright, Divide the Plunder (greyed), Check Status, Sail away. Shipwright offers chain shot; merchant uses the same two-column transfer; governor grants a promotion for the French captures | Visit durations unusable because of the edit | Confirms the port hub structure in the roadmap table |
| O15 | F01 01:16–01:22, 03:07–03:30, 07:24 | Leaving a battle is a chain of click-through screens (surrender or duel end, plunder, news, specialist joins) taking about 10–25 s before map control returns | Click-paced, so partly the player's tempo | Quick replay in Tortuga needs a shorter exit than the reference |

### Checklist coverage against plan task 3

| Checklist area | Covered by | Still unobserved |
|---|---|---|
| Voyage loop | O01, O14 | — |
| Naval decisions | O05–O11 | Reefed sails in use, grape shot, a controlled vessel comparison, sinking, escape, player defeat, dismasted enemy, escorts |
| Pacing | O02, O03, O05, O15 | Upwind travel, recovery after defeat |
| Feedback | O09–O11 | All audio; input feel (never claimable from footage) |
| Connections | O13, O14 | Factions beyond one promotion, quests, career pressure |
| Multiplayer conflicts | O04, O12, "Paused" at F02 03:32 | Time passing in port (hidden by the F01 edit) |

The unobserved items are recommended as an owner-accepted research revision rather than more footage hunting: each is either documented in the manual (C03–C05, C07–C08) or is a Tortuga design decision owned by a later phase.

## Design pillars and Phase 2 naval brief (recommendation, not yet owner-approved)

Everything in this section is **estimated**: a proposal derived from the rows cited. None of it is approved direction until the owner says so.

| Pillar | Evidence | Practical implication | Phase 2 playtest question |
|---|---|---|---|
| Wind is the board | C02, C12, O11 | Every ship has visibly better and worse headings; the wind is always on screen | Can a player say, afterwards, where the wind was and how it helped or hurt them? |
| More than one way to win | C04, C05, O05, O07 | Sinking, crippling, and boarding must each be the best choice in some fight | Across five fights, does a player use more than one approach, or does one maneuver always win? |
| State at a glance | O09–O11 | Guns ready, hull, sails, and crew for both ships readable without opening anything | Shown a paused frame, can an onlooker say who is winning and why? |
| In and out in seconds | O02, O15, README goals | No loading screen into a fight; one action from result to replay | Do players start another fight unprompted? How long from result to control? |
| Fight or flight is the captain's call | C12, R4 (inherited) | Running away is a real, winnable option | Does anyone escape on purpose, and does it feel like a choice rather than a failure? |
| Small enough for one person | Spec #1, master plan | One sea area, three vessels, one art set | Not a playtest question; a scope check at Phase 2 planning |

**Setting.** Recommend the northern Leeward Islands in the buccaneering period, roughly 1660–1680. Wikipedia's *Golden Age of Piracy* (revision 1374703891, read 2026-09-30) gives the overall span as the 1650s–1730s and names a buccaneering period of c. 1650–1680, which keeps this inside the README's framing. The reference game's own 1660 map shows why the area suits a compact game: in F01, English Nevis, Dutch St. Eustatius, Montserrat, Guadeloupe, St. Kitts, St. Martin, and Antigua are all labelled within a few game days' sail of each other (O03), with French, English, and Dutch shipping mixed together. That is reference-game evidence, not verified history; real island ownership for the chosen years needs checking before Phase 5 builds the map. For Phase 2 the sea area is a single open-water arena styled as the channel between Nevis and Montserrat, with one coastline as a boundary and a steady prevailing wind. No map travel.

**Player outcome.** A player can start a fight, maneuver under wind, fire broadsides, win by sinking, crippling, or boarding, or lose or escape, and be back in a new fight within seconds.

**Loop.** Pick an encounter → maneuver → fight → outcome screen → replay or pick another.

**Scope.**

| Area | Phase 2 content |
|---|---|
| Vessels | Three, chosen to differ on the axes the manual names (C02): a small, fast, tight-turning sloop; a medium brig; a large, slow-turning frigate with the heaviest broadside |
| Encounters | One against one for each enemy type, plus one fight against two |
| Wind and handling | Full and reefed sails (C03), speed depending on heading to the wind |
| Damage | Hull, sails, crew, each with a visible effect on the ship (C04, O09) |
| Ammunition | Round shot and chain shot at minimum; grape shot if boarding by crew count needs it |
| Boarding | Resolved from crew numbers, no duel (C13 deferred to Phase 14) |
| Input | Keyboard first, all actions remappable; gamepad as a Phase 2 stretch. The reference's numeric-keypad layout (O11) is not assumed |
| Feedback | The O11 HUD set: both ships' guns, crew, speed; loaded-guns counter with out-of-range message (O10); wind indicator |
| Audio | Cannon, hit, splash, one ambient loop. Reference audio was never heard, so this is unsourced |

**Exclusions.** Career economy, persistent prizes, crew upkeep and food, playable duels, networking, campaign saves, ports.

**Presentation.** Recommend true top-down 2D sprites. A ship seen from directly above needs one image per damage state and rotates for free; the reference's angled 3D view (O11) needs modelled, textured hulls and sails for the same information. The 2D route is the smaller download and the smaller art job. Compare against low-poly 3D only if playtests show sail state or heel cannot be read from above.

**Assets for the probe.** Kenney's CC0 *Pirate Pack* (top-down ships with damage states, cannonballs, island and water tiles), to be recorded in `assets.csv` with source, license, and measured sizes when the probe uses it. No purchase is proposed.

**Probe workload derived from this brief.** 1920×1080, release build. *Normal scene:* scrolling water, 4 ships under way with wakes, HUD, one ambient loop. *Busy scene:* 16 ships each firing an 8-shot broadside every 3 s, with splash and smoke particles.

## Candidate comparison (desk research, 2026-09-30)

Versions and licenses from the GitHub releases API on 2026-09-30; capability claims from the linked documentation. Everything in this table is **documented-but-unmeasured**.

| | Godot 4.7.2 | Bevy 0.19.1 | raylib 6.0 |
|---|---|---|---|
| Released / license | 2026-08-18 / MIT | 2026-08-13 / MIT or Apache-2.0 | 2026-04-23 / zlib |
| Language, editor | GDScript or C#; full editor | Rust; code only | C; code only |
| Windows, macOS, Linux clients | All three exported from one Linux host with official templates ([export docs](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html)) | Cross-compiling from Linux to Windows documented ([cheatbook](https://bevy-cheatbook.github.io/setup/cross/linux-windows.html)); a Linux-to-macOS route was not confirmed in this pass | Builds on all three; cross-compiling and app bundling are do-it-yourself |
| macOS signing | Built-in ad-hoc signing with no Apple account; notarization needs a paid Apple Developer ID, via `rcodesign` from Linux or Xcode on a Mac. Un-notarized downloads are blocked by Gatekeeper until the user overrides | Same Apple rules; tooling is do-it-yourself | Same Apple rules; tooling is do-it-yourself |
| Graphics floor | Compatibility renderer: OpenGL 3.3 or Direct3D 11 ([requirements](https://docs.godotengine.org/en/4.7/about/system_requirements.html)) | wgpu: Vulkan, DX12, Metal, or GLES3 | OpenGL 1.1 through 4.3, selectable at build time |
| Headless server | `--headless` on any platform, no GPU or display; dedicated-server export strips textures to placeholders ([docs](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_dedicated_servers.html)) | Run without render plugins; same Rust code | Do not open a window; same C code |
| Networking | Built in (ENet and a high-level multiplayer API) | Third-party crates | None; bring a library |
| Footprint | Stock editor download is 78 MB zipped for Linux; template size can be cut by custom builds ([size docs](https://docs.godotengine.org/en/4.7/engine_details/development/compiling/optimizing_for_size.html)). Docs state 150 MB storage as the exported-project minimum | No stated figure; size tuning via LTO documented | Library archive is under 2 MB for Linux |
| Solo maintainability | Highest: scenes, UI, particles, audio, export, and profiler in one tool | Pre-1.0 with breaking releases; long compiles; no editor | Everything beyond drawing and input is hand-written |

**Recommendation: probe Godot 4.7.2 with the Compatibility renderer.** It is the only candidate where three-platform export, a headless server, and networking are all stock features, which is most of what Gates E and F ask about. Its open risk is the one the project cares most about: download size and startup time. raylib is the opposite trade, tiny and fast but with the most work left to the owner. Bevy sits between them on size and adds pre-1.0 churn, so it is not the runner-up.

**Runner-up trigger, written before measuring:** probe raylib only if Godot fails a probe question below or its measured package or startup is one the owner judges incompatible with "tiny" and "extremely fast".

### Probe questions and pass criteria

| # | Question | Pass | Stop |
|---|---|---|---|
| Q1 | Does the busy scene hold 16.67 ms frames at 1080p on the Intel UHD GPU? | p95 frame time ≤ 16.67 ms over three 60 s runs, Intel renderer confirmed in the log | After three runs per scene |
| Q2 | How big is a release client, zipped and unpacked, per platform? | Numbers exist for each exportable platform | After one export per platform |
| Q3 | How long from process start to first interactive frame, and from reload to control? | Five samples per class with median and range | After the samples |
| Q4 | Does a server run with no display or GPU and accept clients? | Server log shows 2 then 4 client connections with `DISPLAY` unset | After 4 clients or a blocker |
| Q5 | Does each client move only its own captain, with the server holding the state? | Server log shows per-client positions that match only that client's input | After one scripted run |
| Q6 | Does game time stop with zero clients and resume on reconnect, while the server keeps accepting connections? | Logged simulation time is flat across the empty interval while wall time advances | After two join/leave cycles |
| Q7 | Does the packaged client play offline with no server and no network? | Reaches control and keeps simulating with networking unavailable | After one run |

## Probe results (Godot 4.7.2, 2026-09-30)

All figures are **measured** on LNX-01 unless marked otherwise, from the release-exported Linux client drawing on the Intel UHD GPU through a virtual compositor. Raw rows: [`measurements.csv`](evidence/phase-1/measurements.csv). Method, conditions, failures, and limits: runbook section I. The probe is a technical sample built from [457 lines of script](evidence/phase-1/captures/probe-src/); it is not a game and says nothing about fun.

| # | Result | Evidence |
|---|---|---|
| Q1 frame time | **Pass.** Busy scene (17 ships, 16 firing): median 1.21 ms, p95 3.03–3.06 ms, p99 3.62–3.70 ms, worst frame 5.17 ms, no frame over 16.67 ms in three 60 s runs. Normal scene: p95 1.28–1.32 ms, worst 3.67 ms | 6 runs, 37k–72k frames each; vsync off, CPU governor `powersave` |
| Q2 package size | Linux 74.1 MB installed, 28.8 MB zip, 16.8 MB 7z. Windows 109.7 MB, 38.3 MB zip, 22.7 MB 7z. macOS universal 171.6 MB, 61.0 MB zip. The game's own data is 0.59 MB; the rest is the stock engine template | One export per platform. Windows and macOS packages were **exported, never run** |
| Q3 start-up | Launch to first drawn frame, five samples each from the NVMe: first-ever 2.55–2.69 s (median 2.65); cold binary 1.17–1.43 s (median 1.34); warm 1.14–1.39 s (median 1.21). Headless start and quit takes about 0.5 s, so roughly 0.8 s is display and GL set-up | "Cold" evicts only the game binary; system libraries stay cached |
| Q3 reload proxy | Tear down and rebuild the scene, then draw: 30 samples, 11.0–29.5 ms, 25 of them under 13 ms | A proxy: textures stay loaded, and there is no real encounter to enter |
| Memory | Client RSS peak 166–167 MB in every run, mean 162–163 MB, flat across normal and busy scenes | `VmRSS` at 1 Hz; includes shared libraries and driver mappings |
| Q4 headless server | **Pass.** Exported dedicated server ran with `DISPLAY` and `WAYLAND_DISPLAY` unset and accepted 2, then 4 clients. It links only libc, libm, libdl, libpthread, librt | `captures/logs/net-server.log` |
| Q5 authority and identity | **Pass.** Four clients sent different steering; on the server each ship's heading changed at exactly its own client's rate (−1.2, +1.2, +0.6, and 0 rad/s). Input is keyed by the sender's peer id, so a client has no way to name another ship | Same log, wall 16–25 s |
| Q6 pause when empty | **Pass, with a caveat.** Simulation time and the AI ship's position were frozen across four empty intervals (0–5, 40–50, 66–80, 86–95 s) while the server kept logging and accepted new clients, then resumed from the frozen value. Caveat: a client that vanishes is noticed late, see below | Same log |
| Q7 offline | **Pass.** In a network namespace with no usable interface, the packaged client drew its first frame (1.27 s on the engine's clock) and kept simulating under scripted steering | `captures/logs/offline-nonet.log` |
| Server cost | 79–80 MB RSS throughout. CPU 1.6–1.9% of one core when empty, 2.9% with 2 clients, 3.1% with 4 | Clients shared the host, so this is an upper-ish bound for a trivial simulation |
| Server package | 74.1 MB installed, 28.8 MB zip, 16.8 MB 7z: the same template as the client | Never added to client totals |
| Trimmed engine build | A 2D-only, size-optimised template compiled from source cut the Linux client to 28.5 MB installed, 11.1 MB zip, 6.8 MB 7z. Same scene, networking still works. Cost: busy-scene frames about 30% slower (p95 3.99 ms, p99 4.52 ms, worst 6.79 ms), still none over 16.67 ms; RSS peak 129 MB; start-up unchanged (medians 2.60 / 1.25 / 1.25 s) | One 60 s run and 15 start-up samples, Linux only. It needs the system C++ runtime, and it means owning a custom engine build per platform |

**Disconnect detection.** A client that quits normally is dropped at once. A client killed with SIGTERM was noticed after 7.5 s and 9.5 s, and one killed with SIGKILL after 5.4 s. During that window the server still counted it as present, so game time ran on with nobody there. Pause-when-empty is therefore only as good as the transport's timeout. Phase 3 owns the fix (shorter timeouts, a heartbeat, or rolling the clock back).

**One simulation, three modes.** `sim.gd` (97 lines, no rendering types) is stepped unchanged by offline play and by the server; clients only overwrite ship state from snapshots. That is evidence the offline and shared games need not diverge. It is not evidence about synchronized combat: only ship position and heading crossed the network, and shots were never sent.

**Not exercised.** Saving, restart recovery, and reconnecting as the same captain. The sample world lives in memory and dies with the process. Godot's file APIs are documented-but-unmeasured here. Adverse networks, security, and more than four clients were also not tested.

**Gate status.** Gate E: the candidate passed every runtime question that this host can ask. Gate F: no foundational blocker found in offline independence, headless operation, authority, or pause-empty. Gate G: there are repeated measurements for Linux only; Windows and macOS have sizes but no runtime evidence.

## Compatibility, costs, and budgets

### Foundation constraints

| Constraint | Basis | Owner of the detail |
|---|---|---|
| The dedicated server owns shared state; a client steers only the captain keyed to its own connection | Q5 | Phase 3 |
| Offline play runs the same simulation in-process with no server and no network | Q7, shared `sim.gd` | Phase 2 |
| Game time advances only while someone is connected; sockets, logging, and timeouts run on wall time | Q6 | Phase 3 sessions, Phase 5 campaign |
| No world-freezing modal prompts, and no months-long time skips, in shared play | O04, C07, C08 | Phase 5 encounters, Phase 13 career |
| Encounters between some captains must not stop the clock for the others | C07, O12 | Phase 5 |
| A vanished client must not keep the clock running | Disconnect finding above | Phase 3 |
| Saves belong to the server in shared play and to the player offline; converting between them is a separate decision | Not exercised | Phase 5 |

### Server and platform costs

**Estimated**, from the measured server use plus prices found by web search on 2026-09-30. The prices come from secondary pages, not the vendors' own price lists, and must be rechecked before any spending. Nothing has been bought or provisioned.

| Item | Figure | Note |
|---|---|---|
| Server need | Under 100 MB RAM and a few percent of one laptop core for 4 clients in the sample | A real combat simulation will cost more; allow 10× and it still fits the smallest rented tier |
| Small rented Linux server | About €4 per month (Hetzner CX22, 2 vCPU, 4 GB) to $6 per month (DigitalOcean 1 GB) | Secondary sources; Hetzner raised prices twice in 2026 |
| Existing machine | No rental cost | Owner's own always-on Linux box or the development laptop for playtests; needs a reachable port |
| Server OS | Linux x86_64 recommended | The only server platform actually run |
| Apple Developer Program | $99 per year | Only needed to notarize Mac builds. Without it, Gatekeeper blocks a downloaded build until the user overrides it |
| Windows signing | Roughly $10 per month (Azure Artifact Signing) or $150–300 per year (certificate) | Optional; unsigned builds trigger SmartScreen warnings |
| Assets and tools | $0 so far | Godot is MIT, the sprites are CC0 |
| Operator work | Owner | Updates, backups once saves exist, and sharing the address; no matchmaking or accounts assumed |

### Budgets (approved by the owner on 2026-09-30)

Baseline hardware for all client budgets: an Intel UHD (Comet Lake GT2 class) integrated GPU at 1920×1080, release build, measured with the method in runbook section I. Each budget is set with headroom over today's sample because the sample is far lighter than a finished fight.

| Budget | Approved limit | Measured today | Acceptance statistic |
|---|---|---|---|
| Frame time | p99 ≤ 16.67 ms and no more than 0.1% of frames over 16.67 ms | p99 3.7 ms, none over | Three 60 s runs of the busiest scene, vsync off |
| Client memory | ≤ 300 MB RSS | 167 MB peak | Peak `VmRSS` over a full session |
| First-ever start | ≤ 4.0 s | 2.65 s median | Median of 5, launch to first drawn frame |
| Later starts | ≤ 2.0 s | 1.34 s cold, 1.21 s warm (median) | Median of 5 |
| Encounter entry and replay | ≤ 250 ms from trigger to control | 11–30 ms proxy; the reference game showed about 200 ms (O02) | Median of 5, worst sample reported |
| Compressed download | ≤ 50 MB for Windows and Linux, ≤ 80 MB for macOS | 28.8 / 38.3 / 61.0 MB zipped | Bytes of the file a player downloads |
| Installed size | ≤ 150 MB for Windows and Linux, ≤ 220 MB for macOS | 74 / 110 / 172 MB | Bytes after unpacking |
| Server | ≤ 200 MB RSS and ≤ 25% of one core with 4 captains | 80 MB, 3.1% | Measured on the hosting machine |

**What the size numbers mean.** Today the engine is more than 99% of every package and the game is 0.6 MB. The download and installed limits above leave about 20 MB of compressed game content on top of the stock engine. They are the honest numbers for stock Godot; they are small for a modern game and large beside the project's word "tiny".

There is a measured way to go lower without leaving Godot. With the trimmed engine build, the same limits could be tightened to roughly a 30 MB download and 60 MB installed on Linux. For Windows and macOS that is an **estimate**: no trimmed template was built for them, and doing so needs cross-compilers or a build on each platform. The recommendation is to start Phase 2 on stock templates, where every engine feature is available while the design is still moving, and switch to a trimmed build once the feature set is known. If a budget is missed later, the order of response is: cut or recompress assets, then trim the engine build, then revise the budget with the owner.

### Decision and risk register

| Item | Evidence and status | Impact | Recommended action | Owner / latest gate |
|---|---|---|---|---|
| Engine | Godot 4.7.2 passed Q1–Q7 on Linux (**measured**) | Foundation for everything | Selected by the owner 2026-09-30 | Closed |
| Package size versus "tiny" | Stock: 17–61 MB compressed, almost all engine. Trimmed Linux build: 7–11 MB compressed (**measured**) | The project's headline goal | Accept stock sizes for Phase 2 and plan a trimmed build before release. The runner-up trigger is not met: Godot failed no question, and the trimmed build answers the size concern. Owner approved stock sizes for Phase 2 on 2026-09-30; plan the trimmed build before release | Phase 17 at the latest |
| Windows runtime | Package exported, never run (**blocked**) | Cannot claim Windows support | Owner names a Windows machine and tester | Owner; before Phase 2 closes |
| macOS runtime | Universal package exported and ad-hoc signed, never run (**blocked**); no Mac specifications supplied | Cannot claim Mac support or set a Mac baseline | Owner runs the zip on the Mac and returns the log and machine details | Owner; before Phase 2 closes |
| Real display pacing | Virtual output only (**blocked**) | Vsync stutter and latency are unknown | Repeat Q1 in a real desktop session on the laptop panel | Researcher + owner; Phase 2 |
| Power profile | Measured at `powersave` only | Numbers may be pessimistic, and thermals over long play are unknown | Repeat at the desktop's normal profile and for 10+ minutes | Phase 2 |
| Baseline hardware | One 2020 laptop iGPU tested | It may not be the slowest machine players own | Owner confirmed a 2020-class Intel UHD laptop at 1080p as the floor, 2026-09-30 | Closed; revisit if a weaker machine must be supported |
| Vanished clients keep time running | 5–10 s detection (**measured**) | Breaks pause-when-empty by a few seconds | Tune timeouts or add a heartbeat | Phase 3 |
| Saving and restart | Not exercised | Shared campaign depends on it | Prototype with the first persistent feature | Phase 5 |
| Combat over the network | Not exercised | Core of Phases 3–4 | Keep the simulation free of rendering so it can be synchronized later | Phase 3 |
| Mac notarization and Windows signing | Costs **estimated** | Friction for players downloading builds | Defer spending until builds go to people outside the owner's circle | Owner; Phase 17 at the latest |
| Audio | Placeholder noise; no sink on the test host; reference audio never heard | Audio cost and direction unknown | Pick CC0 sounds in Phase 2 and measure with a real device | Phase 2 |
| Historical setting | Reference-game evidence only | Map accuracy | Verify island ownership for the chosen years | Phase 5 |

## Owner decisions recorded

Given by the owner in the working session on 2026-09-30 (UTC), in the order listed.

| Decision | Accepted |
|---|---|
| Research revision for Gate C | The unobserved checklist items (sinking, escape, player defeat, upwind travel, dismasted surrender and C06, reefed sails and grape shot in use, all audio) are accepted as gaps. Tortuga defines its own surrender rule in Phase 7 |
| Brief | Northern Leeward Islands c. 1660–1680, the three-vessel scope, and top-down 2D sprites are accepted as the working direction |
| Probe candidate | Godot 4.7.2 is approved as the candidate to probe, with raylib as runner-up under the written trigger. This is not yet the engine selection |
| Reporting | A progress comment on issue #2 is approved |
| Engine selection | **Godot 4.7.2, Compatibility renderer, selected** after the probe results and a comparison with free closed-source engines. The raylib runner-up probe will not run |
| Budgets | The budgets table is approved as written |
| Baseline hardware | A 2020-class Intel UHD integrated-graphics laptop at 1920×1080 is the performance floor |
| Phase 1 | Deliverables accepted; Phase 2 planning may begin. Native runs on Windows and macOS, a real-display frame-time check, and human playtests remain mandatory before Phase 2 closes |

## Pending gates and next evidence

| Gate / gap | Status and next action | Owner / latest gate |
|---|---|---|
| A: evidence foundation | **Established for this slice**: authority, labels, source hashes, commands, inventory and limitations recorded. Independent desk research can continue | Phase 1 researcher |
| B: representative hardware | Linux inventory **measured**; Intel render path confirmed and used for the probe; baseline approved by the owner. Still open: a real-display run at a normal power profile, Mac inventory, and Windows access | Researcher + owner; before dependent measurement; native Windows/macOS/Linux execution mandatory before Phase 2 closes |
| B/C: gameplay observation | **Unblocked.** F01 and F02 visually inspected and authenticated as PC; F03 rejected as PSP. Observations O01–O15 recorded. Audio unheard; F01 is edited | Done; coverage gaps accepted by the owner |
| C: documentary/behavior reconciliation | **Passed.** Pacing, entry/exit, feedback, and surrender-without-dismasting observed; wider system relationship table added; remaining gaps accepted as a research revision (see owner decisions) | Closed 2026-09-30 |
| D–G: bounded brief → candidate → probe → measurement | **Done on Linux.** Brief accepted as working direction; Godot 4.7.2 probed; Q1–Q7 answered; sizes, start-up, memory, and server cost measured. Windows and macOS have exported packages and no runtime evidence | Researcher; Windows/macOS runs need the owner |
| H / Phase 1 closure | **Passed.** Engine, budgets, and baseline approved and deliverables accepted by the owner | Closed 2026-09-30 |

Mac follow-up is user-assisted: request model/chip, OS/architecture, CPU/GPU, RAM/storage, display/refresh/scaling, input, AC/battery and power settings, with serials/UUIDs/addresses omitted. Windows follow-up requires an owner-confirmed tester and native machine/access route before inventing run instructions. Candidate-specific workload and commands must be supplied after selection; an export or compatibility layer will not close native runtime gates.
