const std = @import("std");
const zqlite = @import("zqlite");
const models = @import("models.zig");
const c = @cImport({
    @cInclude("time.h");
});
const FoodEntry = models.FoodEntry;
const MealType = models.MealType;
const DailySummary = models.DailySummary;
const FoodCacheEntry = models.FoodCacheEntry;

pub const Database = struct {
    db: zqlite.Conn,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Database {
        const path_z = try allocator.allocSentinel(u8, path.len, 0);
        defer allocator.free(path_z);
        std.mem.copyForwards(u8, path_z[0..path.len], path);

        const flags = zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode;

        // Open database
        var db = try zqlite.open(path_z, flags);
        errdefer db.close();

        // Create tables
        const create_table_sql =
            "CREATE TABLE IF NOT EXISTS food_entries (" ++
            "id INTEGER PRIMARY KEY AUTOINCREMENT," ++
            "name TEXT NOT NULL," ++
            "calories REAL NOT NULL," ++
            "protein REAL NOT NULL," ++
            "carbs REAL NOT NULL," ++
            "fat REAL NOT NULL," ++
            "fiber REAL DEFAULT 0," ++
            "timestamp INTEGER NOT NULL," ++
            "meal_type TEXT NOT NULL," ++
            "notes TEXT," ++
            "images TEXT)";

        try db.exec(create_table_sql, .{});

        try ensureImagesColumn(db);
        try ensureFoodCacheTable(db);

        // Create index for faster date queries
        try db.exec("CREATE INDEX IF NOT EXISTS idx_timestamp ON food_entries(timestamp)", .{});

        return Database{
            .db = db,
            .allocator = allocator,
        };
    }

    pub fn close(self: *Database) void {
        self.db.close();
    }

    pub fn addEntry(self: *Database, entry: FoodEntry) !i64 {
        try self.db.exec("INSERT INTO food_entries (name, calories, protein, carbs, fat, fiber, timestamp, meal_type, notes, images) " ++
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", .{
            entry.name,
            entry.calories,
            entry.protein,
            entry.carbs,
            entry.fat,
            entry.fiber,
            entry.timestamp,
            entry.meal_type.toString(),
            entry.notes,
            entry.images,
        });

        return self.db.lastInsertedRowId();
    }

    pub fn updateEntry(self: *Database, entry: FoodEntry) !void {
        const id = entry.id orelse return error.InvalidEntryId;

        try self.db.exec("UPDATE food_entries SET name = ?, calories = ?, protein = ?, carbs = ?, fat = ?, fiber = ?, timestamp = ?, meal_type = ?, notes = ?, images = ? WHERE id = ?", .{
            entry.name,
            entry.calories,
            entry.protein,
            entry.carbs,
            entry.fat,
            entry.fiber,
            entry.timestamp,
            entry.meal_type.toString(),
            entry.notes,
            entry.images,
            id,
        });
    }

    pub fn getEntriesForDate(self: *Database, date_str: []const u8) !std.ArrayList(FoodEntry) {
        const start_ts = try dateStringToTimestamp(date_str);
        const end_ts = start_ts + 86400;
        return self.getEntriesForRange(start_ts, end_ts);
    }

    pub fn getEntriesForRange(self: *Database, start_ts: i64, end_ts: i64) !std.ArrayList(FoodEntry) {
        var entries: std.ArrayList(FoodEntry) = .empty;
        errdefer entries.deinit(self.allocator);

        var rows = try self.db.rows("SELECT id, name, calories, protein, carbs, fat, fiber, timestamp, meal_type, notes, images " ++
            "FROM food_entries " ++
            "WHERE timestamp >= ? AND timestamp < ? " ++
            "ORDER BY timestamp ASC", .{ start_ts, end_ts });
        defer rows.deinit();

        while (rows.next()) |row| {
            const meal_type_str = row.text(8);
            const meal_type = MealType.fromString(meal_type_str) orelse .other;

            const entry = FoodEntry{
                .id = row.int(0),
                .name = try self.allocator.dupe(u8, row.text(1)),
                .calories = row.float(2),
                .protein = row.float(3),
                .carbs = row.float(4),
                .fat = row.float(5),
                .fiber = row.float(6),
                .timestamp = row.int(7),
                .meal_type = meal_type,
                .notes = if (row.nullableText(9)) |notes| try self.allocator.dupe(u8, notes) else null,
                .images = if (row.nullableText(10)) |images| try self.allocator.dupe(u8, images) else null,
            };
            try entries.append(self.allocator, entry);
        }

        if (rows.err) |err| return err;

        return entries;
    }

    pub fn getDailySummary(self: *Database, date_str: []const u8) !DailySummary {
        const start_ts = try dateStringToTimestamp(date_str);
        const end_ts = start_ts + 86400;
        return self.getSummaryForRange(date_str, start_ts, end_ts);
    }

    pub fn getSummaryForRange(self: *Database, date_str: []const u8, start_ts: i64, end_ts: i64) !DailySummary {
        var data: struct {
            total_calories: f64,
            total_protein: f64,
            total_carbs: f64,
            total_fat: f64,
            total_fiber: f64,
            entry_count: i64,
        } = .{
            .total_calories = 0,
            .total_protein = 0,
            .total_carbs = 0,
            .total_fat = 0,
            .total_fiber = 0,
            .entry_count = 0,
        };

        if (try self.db.row(
            "SELECT COALESCE(SUM(calories), 0) as total_calories, " ++
                "COALESCE(SUM(protein), 0) as total_protein, " ++
                "COALESCE(SUM(carbs), 0) as total_carbs, " ++
                "COALESCE(SUM(fat), 0) as total_fat, " ++
                "COALESCE(SUM(fiber), 0) as total_fiber, " ++
                "COUNT(*) as entry_count " ++
                "FROM food_entries " ++
                "WHERE timestamp >= ? AND timestamp < ?",
            .{ start_ts, end_ts },
        )) |row| {
            defer row.deinit();
            data = .{
                .total_calories = row.float(0),
                .total_protein = row.float(1),
                .total_carbs = row.float(2),
                .total_fat = row.float(3),
                .total_fiber = row.float(4),
                .entry_count = row.int(5),
            };
        }

        return DailySummary{
            .date = date_str,
            .total_calories = data.total_calories,
            .total_protein = data.total_protein,
            .total_carbs = data.total_carbs,
            .total_fat = data.total_fat,
            .total_fiber = data.total_fiber,
            .entry_count = data.entry_count,
        };
    }

    pub fn deleteEntry(self: *Database, id: i64) !void {
        try self.db.exec("DELETE FROM food_entries WHERE id = ?", .{id});
    }

    pub fn getRecentEntries(self: *Database, limit: i64) !std.ArrayList(FoodEntry) {
        var entries: std.ArrayList(FoodEntry) = .empty;
        errdefer entries.deinit(self.allocator);

        var rows = try self.db.rows("SELECT id, name, calories, protein, carbs, fat, fiber, timestamp, meal_type, notes, images " ++
            "FROM food_entries " ++
            "ORDER BY timestamp DESC " ++
            "LIMIT ?", .{limit});
        defer rows.deinit();

        while (rows.next()) |row| {
            const meal_type_str = row.text(8);
            const meal_type = MealType.fromString(meal_type_str) orelse .other;

            const entry = FoodEntry{
                .id = row.int(0),
                .name = try self.allocator.dupe(u8, row.text(1)),
                .calories = row.float(2),
                .protein = row.float(3),
                .carbs = row.float(4),
                .fat = row.float(5),
                .fiber = row.float(6),
                .timestamp = row.int(7),
                .meal_type = meal_type,
                .notes = if (row.nullableText(9)) |notes| try self.allocator.dupe(u8, notes) else null,
                .images = if (row.nullableText(10)) |images| try self.allocator.dupe(u8, images) else null,
            };
            try entries.append(self.allocator, entry);
        }

        if (rows.err) |err| return err;

        return entries;
    }

    pub fn searchEntries(self: *Database, query: []const u8) !std.ArrayList(FoodEntry) {
        var entries: std.ArrayList(FoodEntry) = .empty;
        errdefer entries.deinit(self.allocator);

        // Add wildcards for LIKE query
        var pattern_buf: [256]u8 = undefined;
        const pattern = std.fmt.bufPrint(&pattern_buf, "%{s}%", .{query}) catch return entries;

        var rows = try self.db.rows("SELECT id, name, calories, protein, carbs, fat, fiber, timestamp, meal_type, notes, images " ++
            "FROM food_entries " ++
            "WHERE name LIKE ? " ++
            "ORDER BY timestamp DESC", .{pattern});
        defer rows.deinit();

        while (rows.next()) |row| {
            const meal_type_str = row.text(8);
            const meal_type = MealType.fromString(meal_type_str) orelse .other;

            const entry = FoodEntry{
                .id = row.int(0),
                .name = try self.allocator.dupe(u8, row.text(1)),
                .calories = row.float(2),
                .protein = row.float(3),
                .carbs = row.float(4),
                .fat = row.float(5),
                .fiber = row.float(6),
                .timestamp = row.int(7),
                .meal_type = meal_type,
                .notes = if (row.nullableText(9)) |notes| try self.allocator.dupe(u8, notes) else null,
                .images = if (row.nullableText(10)) |images| try self.allocator.dupe(u8, images) else null,
            };
            try entries.append(self.allocator, entry);
        }

        if (rows.err) |err| return err;

        return entries;
    }

    pub fn searchFoodCache(self: *Database, query: []const u8) !std.ArrayList(FoodCacheEntry) {
        var entries: std.ArrayList(FoodCacheEntry) = .empty;
        errdefer entries.deinit(self.allocator);

        var pattern_buf: [256]u8 = undefined;
        const pattern = std.fmt.bufPrint(&pattern_buf, "%{s}%", .{query}) catch return entries;

        var rows = try self.db.rows("SELECT product_id, name, calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g, fiber_per_100g, timestamp " ++
            "FROM food_cache " ++
            "WHERE name LIKE ? " ++
            "ORDER BY name ASC", .{pattern});
        defer rows.deinit();

        while (rows.next()) |row| {
            const entry = FoodCacheEntry{
                .product_id = try self.allocator.dupe(u8, row.text(0)),
                .name = try self.allocator.dupe(u8, row.text(1)),
                .calories_per_100g = row.float(2),
                .protein_per_100g = row.float(3),
                .carbs_per_100g = row.float(4),
                .fat_per_100g = row.float(5),
                .fiber_per_100g = row.float(6),
                .timestamp = row.int(7),
            };
            try entries.append(self.allocator, entry);
        }

        if (rows.err) |err| return err;

        return entries;
    }

    pub fn getFoodCacheById(self: *Database, product_id: []const u8) !?FoodCacheEntry {
        if (try self.db.row("SELECT product_id, name, calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g, fiber_per_100g, timestamp " ++
            "FROM food_cache WHERE product_id = ?", .{product_id})) |row| {
            defer row.deinit();
            return FoodCacheEntry{
                .product_id = try self.allocator.dupe(u8, row.text(0)),
                .name = try self.allocator.dupe(u8, row.text(1)),
                .calories_per_100g = row.float(2),
                .protein_per_100g = row.float(3),
                .carbs_per_100g = row.float(4),
                .fat_per_100g = row.float(5),
                .fiber_per_100g = row.float(6),
                .timestamp = row.int(7),
            };
        }
        return null;
    }

    pub fn upsertFoodCache(self: *Database, entry: FoodCacheEntry) !void {
        try self.db.exec(
            "INSERT INTO food_cache (product_id, name, calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g, fiber_per_100g, timestamp) " ++
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?) " ++
                "ON CONFLICT(product_id) DO UPDATE SET name = excluded.name, calories_per_100g = excluded.calories_per_100g, " ++
                "protein_per_100g = excluded.protein_per_100g, carbs_per_100g = excluded.carbs_per_100g, fat_per_100g = excluded.fat_per_100g, " ++
                "fiber_per_100g = excluded.fiber_per_100g, timestamp = excluded.timestamp",
            .{
                entry.product_id,
                entry.name,
                entry.calories_per_100g,
                entry.protein_per_100g,
                entry.carbs_per_100g,
                entry.fat_per_100g,
                entry.fiber_per_100g,
                entry.timestamp,
            },
        );
    }
};

fn ensureFoodCacheTable(db: zqlite.Conn) !void {
    const create_cache_sql =
        "CREATE TABLE IF NOT EXISTS food_cache (" ++
        "product_id TEXT PRIMARY KEY," ++
        "name TEXT NOT NULL," ++
        "calories_per_100g REAL," ++
        "protein_per_100g REAL," ++
        "carbs_per_100g REAL," ++
        "fat_per_100g REAL," ++
        "fiber_per_100g REAL," ++
        "timestamp INTEGER NOT NULL)";
    try db.exec(create_cache_sql, .{});
}

fn ensureImagesColumn(db: zqlite.Conn) !void {
    var has_images = false;
    var rows = try db.rows("PRAGMA table_info(food_entries)", .{});
    defer rows.deinit();

    while (rows.next()) |row| {
        if (std.mem.eql(u8, row.text(1), "images")) {
            has_images = true;
            break;
        }
    }

    if (rows.err) |err| return err;

    if (!has_images) {
        try db.exec("ALTER TABLE food_entries ADD COLUMN images TEXT", .{});
    }
}

// Helper function to convert YYYY-MM-DD to unix timestamp
pub fn dateStringToTimestamp(date_str: []const u8) !i64 {
    // Expected format: YYYY-MM-DD
    if (date_str.len < 10) return error.InvalidDateFormat;

    const date_part = date_str[0..10];
    const year = try std.fmt.parseInt(i32, date_part[0..4], 10);
    const month = try std.fmt.parseInt(i32, date_part[5..7], 10);
    const day = try std.fmt.parseInt(i32, date_part[8..10], 10);

    var tm: c.tm = std.mem.zeroes(c.tm);
    tm.tm_year = year - 1900;
    tm.tm_mon = month - 1;
    tm.tm_mday = day;
    tm.tm_hour = 0;
    tm.tm_min = 0;
    tm.tm_sec = 0;
    tm.tm_isdst = -1;

    const local = c.mktime(&tm);
    if (local == -1) return error.InvalidDateFormat;

    return @intCast(local);
}

test "dateStringToTimestamp offsets" {
    const t1 = try dateStringToTimestamp("2026-02-03");
    const t2 = try dateStringToTimestamp("2026-02-04");
    const diff = t2 - t1;
    try std.testing.expect(diff >= 23 * 3600 and diff <= 25 * 3600);
    try std.testing.expectError(error.InvalidDateFormat, dateStringToTimestamp("2026-2-3"));
}

test "food cache upsert and lookup" {
    var database = try Database.init(std.testing.allocator, ":memory:");
    defer database.close();

    const entry: FoodCacheEntry = .{
        .product_id = "12345",
        .name = "Test Food",
        .calories_per_100g = 100,
        .protein_per_100g = 10,
        .carbs_per_100g = 20,
        .fat_per_100g = 5,
        .fiber_per_100g = 3,
        .timestamp = 1700000000,
    };

    try database.upsertFoodCache(entry);

    const fetched = try database.getFoodCacheById("12345");
    try std.testing.expect(fetched != null);
    const value = fetched.?;
    defer {
        database.allocator.free(value.product_id);
        database.allocator.free(value.name);
    }

    try std.testing.expectEqualStrings("12345", value.product_id);
    try std.testing.expectEqualStrings("Test Food", value.name);
    try std.testing.expectEqual(@as(f64, 100), value.calories_per_100g);
    try std.testing.expectEqual(@as(f64, 10), value.protein_per_100g);

    var matches = try database.searchFoodCache("Test");
    defer {
        for (matches.items) |item| {
            database.allocator.free(item.product_id);
            database.allocator.free(item.name);
        }
        matches.deinit(database.allocator);
    }

    try std.testing.expectEqual(@as(usize, 1), matches.items.len);
    try std.testing.expectEqualStrings("12345", matches.items[0].product_id);
}
