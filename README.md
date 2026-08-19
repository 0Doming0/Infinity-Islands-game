# SkyDungeon / Infinity Islands

A Roblox action-RPG product built around a deliberately simple progression loop: enter an island, defeat enemies, gain XP, level up, unlock the next area and repeat with increasing difficulty.

## Product focus

The project was developed as an MVP rather than as a feature-complete RPG. The main goal was to test whether a clear action/progression loop could retain players before investing in a much larger content scope.

My work went beyond gameplay programming and included product decisions around onboarding, mobile usability, progression, monetization, analytics and paid acquisition.

## Core experience

- island-based progression
- enemy combat and targeting
- XP and leveling
- guided progression between islands
- mobile-focused combat UX
- orbs and companion systems
- loot and reward systems
- persistent player progression
- onboarding and player guidance
- monetization experiments
- telemetry and product analytics

## Product iteration

After launch and paid Roblox Ads tests, I used player behavior and session metrics to identify problems in the first-time experience. This led to iterations around mobile combat, onboarding clarity, mob spawning, performance and guidance.

The project became a practical exercise in the full cycle:

`MVP → launch → acquisition → metrics → diagnosis → iteration`

## Stack

- Roblox Studio
- Luau
- Rojo
- client/server architecture
- Roblox DataStore / platform services

## Repository workflow

This project uses Rojo. To build the place file:

```bash
rojo build -o "SkyDungeon.rbxlx"
```

Then open `SkyDungeon.rbxlx` in Roblox Studio and run:

```bash
rojo serve
```

## Portfolio context

This repository represents an independently planned and implemented game product. The value of the case is not only the codebase, but the decisions made after exposing the product to real players and using acquisition and behavioral signals to improve it.
