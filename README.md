# Food Journal CLI

Track meals, macros, and quick summaries from the terminal.

## Requirements

- SQLite3 available on your system (linked via `-lsqlite3`)
- Zig 0.15.2+ (only if building from source)

## Install (Release)

Linux x86_64 and macOS (x86_64 + arm64) builds are published on GitHub Releases.

```bash
curl -fsSL https://raw.githubusercontent.com/JonathanRiche/food-journal/master/install-v2.sh | bash
```

The installer places `food-journal` in `~/.local/bin` by default. You can override:

```bash
INSTALL_DIR="$HOME/bin" curl -fsSL https://raw.githubusercontent.com/JonathanRiche/food-journal/master/install-v2.sh | bash
```

If the install directory is not on PATH, the script will append it to your shell profile.

## Agent skill

The skill definition lives at `skills/food-journal/SKILL.md`.

After installing the CLI, you can add the agent skill with:

```bash
npx skills add https://github.com/anthropics/skills --skill food-journal
```

## Build (from source)

```bash
zig build
```

## Run

```bash
food-journal <command>
```

From source:

```bash
zig build run -- <command>
```

Examples:

```bash
food-journal add "Chicken Breast" 165 31 0 3.6 0 lunch "Grilled, 100g"
food-journal today
food-journal today --so-far
food-journal show 2026-02-03 --until 14:30
food-journal recent 20
food-journal search chicken
food-journal delete 42
```

## Commands

- `add "Food Name" <calories> <protein> <carbs> <fat> [fiber] [meal_type] [notes] [--images <list>]`
  - `meal_type` values: `breakfast`, `lunch`, `dinner`, `snack`, `other`
  - `--images` accepts a free-form string (comma-separated list recommended)
- `today [--so-far | --until HH:MM]`
  - `--so-far` uses the current time as the cutoff
  - `--until HH:MM` uses a time-of-day cutoff (24h format)
- `show YYYY-MM-DD [--until HH:MM]`
- `recent [limit]`
- `search <query>`
- `delete <id>`
- `help`

## Data location

The database file is stored at:

```
~/.local/share/food-journal/food_journal.db
```

The directory is created automatically on startup.

## Notes on dates

- `today` and `show` are based on simple epoch math (no timezone handling).
- `--until` includes entries up to the specified minute.

## Development

- Run `zig build` to compile
- Update schema in `src/db.zig`
- CLI parsing lives in `src/main.zig`
