# Food Journal - Future Tasks & Ideas

This file contains feature ideas and improvements for the food-journal CLI.

---

## 🎯 High Priority

### 1. Natural Language Parser
**Description:** Parse natural language descriptions into food entries with estimated macros.

**Example:**
```bash
food-journal add "3 eggs, 2 slices bacon, coffee with cream"
```

**Implementation Notes:**
- Split by commas or "and"
- Use Open Food Facts API to look up each item
- Estimate quantities ("3 eggs" → 150g, "2 slices bacon" → 60g)
- Sum macros across all items
- Could use AI/LLM for ambiguous cases

---

### 2. Recent/Favorites Shortcuts
**Description:** Quick re-entry of common meals and favoriting system.

**Commands:**
```bash
food-journal again 1                    # Re-add entry #1 with new timestamp
food-journal favorite "breakfast"       # Tag entry as favorite
food-journal fav breakfast              # Add favorite by tag
food-journal list-favorites             # Show all favorites
```

**Implementation Notes:**
- Add `favorites` table to database
- Store entry template with all macros
- Allow partial matching on favorite names

---

### 3. Smart Time Parsing
**Description:** Parse relative time descriptions into Unix timestamps.

**Example:**
```bash
food-journal add "protein shake" --time "2 hours ago"
food-journal add "dinner" --time "yesterday 7pm"
food-journal add "snack" --time "today 3:30"
```

**Implementation Notes:**
- Parse common patterns: "X hours/minutes ago", "yesterday HH:MM", "today HH:MM"
- Use current time as reference
- Calculate Unix timestamp

---

## 🛠️ Medium Priority

### 4. Water & Supplement Tracking
**Description:** Track water intake and supplements separately from food.

**Commands:**
```bash
food-journal water 500ml                # Add water intake
food-journal water --total            # Show today's total water
food-journal supp "Magnesium 400mg"    # Log supplement
food-journal supp "Vitamin D 2000IU"  # Another supplement
```

**Implementation Notes:**
- Separate `water_intake` and `supplements` tables
- Water target tracking (default 2500ml/day)
- Supplements don't count toward macros

---

### 5. Goals & Progress Tracking
**Description:** Set daily macro goals and track progress against them.

**Commands:**
```bash
food-journal goals --set calories 2000 --set protein 150 --set carbs 20 --set fat 140
food-journal goals --set protein 150
food-journal today --vs-goals           # Show progress: 112/150g protein (75%)
food-journal show 2026-02-03 --vs-goals
```

**Implementation Notes:**
- Add `user_goals` table (calories, protein, carbs, fat, fiber, water)
- Calculate percentages in real-time
- Visual progress bars in terminal output

---

### 6. CSV Export
**Description:** Export meal history to CSV for analysis in spreadsheet apps.

**Commands:**
```bash
food-journal export 2026-02-01 2026-02-28 > meals.csv
food-journal export --last 30 > last_30_days.csv
food-journal export --all > all_meals.csv
```

**Implementation Notes:**
- CSV columns: date, time, name, meal_type, calories, protein, carbs, fat, fiber, notes
- Date range handling
- Optional: JSON export for programmatic use

---

### 7. Photo Storage with Entries
**Description:** View stored images alongside meal entries.

**Commands:**
```bash
food-journal show 2026-02-03 --with-images
food-journal recent 5 --with-images
```

**Implementation Notes:**
- Images already stored via `--images` flag
- Store file paths in database
- Display image list in output
- Optional: TUI image preview (if terminal supports it)

---

## 🔥 The Big One

### 8. Terminal UI (TUI)
**Description:** Interactive terminal interface for browsing and managing entries.

**Features:**
- Interactive search with arrow key navigation
- Visual daily summary with charts/progress bars
- Click/enter to "eat this again"
- Browse history by date with calendar view
- Real-time macro tracking dashboard

**Implementation Notes:**
- Use ratatui (Rust) or equivalent Zig library
- Event loop for keyboard input
- Separate TUI binary: `food-journal-tui`
- Or embed as `food-journal tui` subcommand

---

## 📝 Technical Debt & Improvements

### 9. Better Error Messages
- User-friendly errors for network failures
- Suggestions when API rate limited
- Validate portion sizes (reject "5000g" as likely error)

### 10. Offline Mode
- Cache all Open Food Facts data locally after first lookup
- Work completely offline for previously searched items
- Sync indicator when online/offline

### 11. Recipe Builder
```bash
food-journal recipe create "Chicken Stir Fry"
food-journal recipe add-ingredient "chicken breast" 200g
food-journal recipe add-ingredient "broccoli" 150g
food-journal recipe add-ingredient "olive oil" 10g
food-journal recipe save              # Calculates total macros
food-journal add "Chicken Stir Fry" --from-recipe  # Adds all ingredients
```

### 12. Weight Tracking
```bash
food-journal weight 258.5             # Log daily weight
food-journal weight --graph 30        # Show 30-day trend
```

---

## Completed ✅

- [x] Open Food Facts API integration
- [x] Local food cache database
- [x] Search command
- [x] Add with `--from-db` flag
- [x] Portion size scaling (50g → 0.5×)
- [x] Rate limiting for API

---

*Last updated: 2026-02-03*
