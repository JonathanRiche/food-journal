# Skill: food-journal CLI

This skill describes how an agent should use the `food-journal` CLI to record and query meals.

## Quick Start

Assumes `food-journal` is installed and in PATH.

```bash
food-journal <command>
```

## Logging meals

Add a meal entry with macros:

```bash
food-journal add "Greek Yogurt" 120 20 8 0 0 breakfast "Plain, 170g"
```

Optional images list (store as a single string; comma-separated works well):

```bash
food-journal add "Salad" 320 8 24 18 6 lunch "With vinaigrette" --images "salad.jpg,plate.png"
```

## Checking totals

Show everything for today:

```bash
food-journal today
```

Show totals so far today (current time cutoff):

```bash
food-journal today --so-far
```

Show totals for a specific date up to a time:

```bash
food-journal show 2026-02-03 --until 14:30
```

## Searching and cleanup

- Search by name:
  ```bash
  food-journal search chicken
  ```
- List recent entries:
  ```bash
  food-journal recent 10
  ```
- Delete an entry by id:
  ```bash
  food-journal delete 42
  ```

## Data storage

Entries are stored at:

```
~/.local/share/food-journal/food_journal.db
```
