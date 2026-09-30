A modern remake of the classic game "Sid Meier's Pirates!". This project aims to capture the essence of the original game while introducing new features and improvements.

## Project goals

- Highly performant play: responsive controls, smooth frame pacing, and efficient CPU, GPU, and memory use on the agreed target hardware.
- Extremely fast loading: minimize cold-start time to playable action and waits when entering or replaying encounters.
- Tiny game files: keep the total download and installed footprint small, with compact assets and minimal runtime dependencies.

These goals guide engine, asset, and feature choices from the start. Phase 1 will establish measurable performance, loading-time, and size budgets with defined test conditions; playable milestones will verify them on supported platforms. See [the master plan](MASTER-PLAN.md) for the phased roadmap.

## Running the game

The game lives in [`game/`](game/) (Godot 4.7.2, Compatibility renderer). Toolchain setup, launch and test commands: [Sailing playground runbook](docs/phase-2/sailing-playground.md).

## Features
- Cross-platform support for Windows, macOS, and Linux.
- Open-world exploration of the Caribbean during the Golden Age of Piracy.
- Engaging naval combat with a variety of ships and weapons.
- Dynamic trading system with fluctuating prices and goods.
- Character progression and skill development for your pirate captain.
- Quests and missions that offer unique challenges and rewards.
- Multiplayer mode for cooperative and competitive gameplay.
