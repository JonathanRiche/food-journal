const std = @import("std");
const db = @import("db.zig");
const models = @import("models.zig");
const FoodEntry = models.FoodEntry;
const MealType = models.MealType;
const Database = db.Database;

const DB_NAME = "food_journal.db";

const DateRange = struct {
    start_ts: i64,
    end_ts: i64,
    label: ?[]const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const db_path = try getDatabasePath(allocator);
    defer allocator.free(db_path);

    // Initialize database
    var database = try Database.init(allocator, db_path);
    defer database.close();

    const command = args[1];

    if (std.mem.eql(u8, command, "add")) {
        try addEntry(&database, args);
    } else if (std.mem.eql(u8, command, "today")) {
        const until_time = parseFlagValue(args, "--until") catch |err| switch (err) {
            error.MissingFlagValue => {
                std.debug.print("Usage: food-journal today [--so-far | --until HH:MM]\n", .{});
                return;
            },
            else => return err,
        };
        const so_far = hasFlag(args, "--so-far");
        try showToday(&database, until_time, so_far);
    } else if (std.mem.eql(u8, command, "show")) {
        if (args.len < 3) {
            std.debug.print("Usage: food-journal show YYYY-MM-DD [--until HH:MM]\n", .{});
            return;
        }
        const until_time = parseFlagValue(args, "--until") catch |err| switch (err) {
            error.MissingFlagValue => {
                std.debug.print("Usage: food-journal show YYYY-MM-DD [--until HH:MM]\n", .{});
                return;
            },
            else => return err,
        };
        try showDate(&database, args[2], until_time, null);
    } else if (std.mem.eql(u8, command, "recent")) {
        const limit = if (args.len >= 3) try std.fmt.parseInt(i64, args[2], 10) else 10;
        try showRecent(&database, limit);
    } else if (std.mem.eql(u8, command, "search")) {
        if (args.len < 3) {
            std.debug.print("Usage: food-journal search <query>\n", .{});
            return;
        }
        try searchEntries(&database, args[2]);
    } else if (std.mem.eql(u8, command, "delete")) {
        if (args.len < 3) {
            std.debug.print("Usage: food-journal delete <id>\n", .{});
            return;
        }
        const id = try std.fmt.parseInt(i64, args[2], 10);
        try deleteEntry(&database, id);
    } else if (std.mem.eql(u8, command, "help")) {
        printUsage();
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        printUsage();
    }
}

fn addEntry(database: *Database, args: []const []const u8) !void {
    // Quick add: food-journal add "Food Name" <calories> <protein> <carbs> <fat> [fiber] [meal_type] [notes] [--images <list>]
    const images = parseFlagValue(args, "--images") catch |err| switch (err) {
        error.MissingFlagValue => {
            std.debug.print("Usage: food-journal add \"Food Name\" <calories> <protein> <carbs> <fat> [fiber] [meal_type] [notes] [--images <list>]\n", .{});
            return;
        },
        else => return err,
    };

    var positional: std.ArrayList([]const u8) = .empty;
    defer positional.deinit(database.allocator);

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--images")) {
            if (i + 1 >= args.len) {
                std.debug.print("Usage: food-journal add \"Food Name\" <calories> <protein> <carbs> <fat> [fiber] [meal_type] [notes] [--images <list>]\n", .{});
                return;
            }
            i += 1;
            continue;
        }
        try positional.append(database.allocator, args[i]);
    }

    if (positional.items.len < 5) {
        std.debug.print(
            \\nUsage: food-journal add "Food Name" <calories> <protein> <carbs> <fat> [fiber] [meal_type] [notes] [--images <list>]
            \\nExample: food-journal add "Chicken Breast" 165 31 0 3.6 0 lunch "Grilled, 100g" --images "front.jpg,back.jpg"
            \\nMeal types: breakfast, lunch, dinner, snack, other (default: other)
            \\n
        , .{});
        return;
    }

    const name = positional.items[0];
    const calories = try std.fmt.parseFloat(f64, positional.items[1]);
    const protein = try std.fmt.parseFloat(f64, positional.items[2]);
    const carbs = try std.fmt.parseFloat(f64, positional.items[3]);
    const fat = try std.fmt.parseFloat(f64, positional.items[4]);
    const fiber = if (positional.items.len >= 6) try std.fmt.parseFloat(f64, positional.items[5]) else 0;
    const meal_type_str = if (positional.items.len >= 7) positional.items[6] else "other";
    const notes = if (positional.items.len >= 8) positional.items[7] else null;

    const meal_type = MealType.fromString(meal_type_str) orelse .other;
    const timestamp = std.time.timestamp();

    const entry = FoodEntry{
        .id = null,
        .name = name,
        .calories = calories,
        .protein = protein,
        .carbs = carbs,
        .fat = fat,
        .fiber = fiber,
        .timestamp = timestamp,
        .meal_type = meal_type,
        .notes = notes,
        .images = images,
    };

    const id = try database.addEntry(entry);

    std.debug.print(
        \\n✅ Added entry #{d}
        \\nFood: {s}
        \\nCalories: {d:.0}
        \\nProtein: {d:.1}g
        \\nCarbs: {d:.1}g
        \\nFat: {d:.1}g
        \\nFiber: {d:.1}g
        \\nMeal: {s}
        \\nTime: {d}
        \\n
    , .{
        id, name, calories, protein, carbs, fat, fiber, meal_type.toString(), timestamp,
    });
}

fn showToday(database: *Database, until_time: ?[]const u8, so_far: bool) !void {
    // Get today's date
    const timestamp = std.time.timestamp();
    var date_buf: [11]u8 = undefined;
    const date_str = try timestampToDateString(timestamp, date_buf[0..]);
    try showDate(database, date_str, until_time, if (so_far) "now" else null);
}

fn showDate(database: *Database, date_str: []const u8, until_time: ?[]const u8, label: ?[]const u8) !void {
    const range = buildDateRange(date_str, until_time, label) catch |err| switch (err) {
        error.InvalidTimeFormat => {
            std.debug.print("Invalid time. Use HH:MM (e.g. 13:30).\n", .{});
            return;
        },
        else => return err,
    };
    if (range.label) |suffix| {
        std.debug.print("\n📅 Date: {s} (through {s})\n", .{ date_str, suffix });
    } else {
        std.debug.print("\n📅 Date: {s}\n", .{date_str});
    }

    // Show summary
    const summary = try database.getSummaryForRange(date_str, range.start_ts, range.end_ts);
    std.debug.print("{f}", .{summary});

    // Show entries
    var entries = try database.getEntriesForRange(range.start_ts, range.end_ts);
    defer {
        for (entries.items) |entry| {
            database.allocator.free(entry.name);
            if (entry.notes) |notes| database.allocator.free(notes);
            if (entry.images) |images| database.allocator.free(images);
        }
        entries.deinit(database.allocator);
    }

    if (entries.items.len == 0) {
        std.debug.print("\nNo entries for this date.\n", .{});
        return;
    }

    std.debug.print("\n🍽️  Entries:\n", .{});
    for (entries.items) |entry| {
        std.debug.print("  [{d}] {s} ({s})\n", .{
            entry.id.?, entry.name, entry.meal_type.toString(),
        });
        std.debug.print("      Calories: {d:.0} | Protein: {d:.1}g | Carbs: {d:.1}g | Fat: {d:.1}g", .{ entry.calories, entry.protein, entry.carbs, entry.fat });
        if (entry.notes) |notes| {
            std.debug.print(" | Notes: {s}\n", .{notes});
        } else {
            std.debug.print("\n", .{});
        }
    }
}

fn showRecent(database: *Database, limit: i64) !void {
    var entries = try database.getRecentEntries(limit);
    defer {
        for (entries.items) |entry| {
            database.allocator.free(entry.name);
            if (entry.notes) |notes| database.allocator.free(notes);
            if (entry.images) |images| database.allocator.free(images);
        }
        entries.deinit(database.allocator);
    }

    if (entries.items.len == 0) {
        std.debug.print("No entries found.\n", .{});
        return;
    }

    std.debug.print("\n🕐 Recent {d} entries:\n", .{entries.items.len});
    for (entries.items) |entry| {
        var date_buf: [11]u8 = undefined;
        const date_str = try timestampToDateString(entry.timestamp, date_buf[0..]);
        std.debug.print("  [{d}] {s} - {s} ({s})\n", .{
            entry.id.?, date_str, entry.name, entry.meal_type.toString(),
        });
        std.debug.print("      Calories: {d:.0} | Protein: {d:.1}g | Carbs: {d:.1}g | Fat: {d:.1}g\n", .{ entry.calories, entry.protein, entry.carbs, entry.fat });
    }
}

fn searchEntries(database: *Database, query: []const u8) !void {
    var entries = try database.searchEntries(query);
    defer {
        for (entries.items) |entry| {
            database.allocator.free(entry.name);
            if (entry.notes) |notes| database.allocator.free(notes);
            if (entry.images) |images| database.allocator.free(images);
        }
        entries.deinit(database.allocator);
    }

    if (entries.items.len == 0) {
        std.debug.print("No entries found matching '{s}'.\n", .{query});
        return;
    }

    std.debug.print("\n🔍 Found {d} entries matching '{s}':\n", .{ entries.items.len, query });
    for (entries.items) |entry| {
        var date_buf: [11]u8 = undefined;
        const date_str = try timestampToDateString(entry.timestamp, date_buf[0..]);
        std.debug.print("  [{d}] {s} - {s} ({s})\n", .{
            entry.id.?, date_str, entry.name, entry.meal_type.toString(),
        });
        std.debug.print("      Calories: {d:.0} | Protein: {d:.1}g | Carbs: {d:.1}g | Fat: {d:.1}g\n", .{ entry.calories, entry.protein, entry.carbs, entry.fat });
    }
}

fn deleteEntry(database: *Database, id: i64) !void {
    try database.deleteEntry(id);
    std.debug.print("✅ Deleted entry #{d}\n", .{id});
}

fn printUsage() void {
    std.debug.print(
        \\n🍎 Food Journal - Track your meals and macros
        \\n
        \\nUsage:
        \\  food-journal add "Food Name" <calories> <protein> <carbs> <fat> [fiber] [meal_type] [notes] [--images <list>]
        \\  food-journal today [--so-far | --until HH:MM]    Show today's entries
        \\  food-journal show YYYY-MM-DD [--until HH:MM]     Show entries for specific date
        \\  food-journal recent [limit]           Show recent entries (default: 10)
        \\  food-journal search <query>          Search food entries by name
        \\  food-journal delete <id>              Delete an entry by ID
        \\  food-journal help                     Show this help message
        \\n
    , .{});
}

// Helper to convert timestamp to YYYY-MM-DD format
fn timestampToDateString(timestamp: i64, buf: []u8) ![]const u8 {
    if (buf.len < 11) return error.BufferTooSmall;
    // Calculate year, month, day from timestamp
    // This is a simplified calculation
    const days_since_epoch = @divFloor(timestamp, 86400);

    // Approximate year (ignoring leap seconds and precise leap year calc for simplicity)
    var year: i32 = 1970;
    var remaining_days = days_since_epoch;

    while (remaining_days > 0) {
        const days_in_year: i64 = if (isLeapYear(year)) 366 else 365;
        if (remaining_days >= days_in_year) {
            remaining_days -= days_in_year;
            year += 1;
        } else {
            break;
        }
    }

    // Calculate month and day
    const month_days = [_]u5{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var month: u5 = 1;

    while (month <= 12) {
        var days_in_month = month_days[month - 1];
        if (month == 2 and isLeapYear(year)) {
            days_in_month = 29;
        }

        if (remaining_days < days_in_month) {
            break;
        }

        remaining_days -= days_in_month;
        month += 1;
    }

    const day = remaining_days + 1;

    const year_u: u16 = @intCast(year);
    const month_u: u8 = @intCast(month);
    const day_u: u8 = @intCast(day);
    return try std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{ year_u, month_u, day_u });
}

fn isLeapYear(year: i32) bool {
    return (@mod(year, 4) == 0 and @mod(year, 100) != 0) or (@mod(year, 400) == 0);
}

test "parseFlagValue and hasFlag" {
    const args = [_][]const u8{ "food-journal", "today", "--until", "12:30" };
    try std.testing.expect(hasFlag(&args, "--until"));
    try std.testing.expect(!hasFlag(&args, "--so-far"));
    try std.testing.expectEqualStrings("12:30", (try parseFlagValue(&args, "--until")) orelse "");
    try std.testing.expectEqual(@as(?[]const u8, null), try parseFlagValue(&args, "--missing"));
    try std.testing.expectError(error.MissingFlagValue, parseFlagValue(&[_][]const u8{ "food-journal", "today", "--until" }, "--until"));
}

test "parseTimeToSeconds" {
    try std.testing.expectEqual(@as(i64, 0), try parseTimeToSeconds("00:00"));
    try std.testing.expectEqual(@as(i64, 86340), try parseTimeToSeconds("23:59"));
    try std.testing.expectError(error.InvalidTimeFormat, parseTimeToSeconds("24:00"));
    try std.testing.expectError(error.InvalidTimeFormat, parseTimeToSeconds("9:00"));
}

test "timestampToDateString roundtrip" {
    const date = "2026-02-03";
    const ts = try db.dateStringToTimestamp(date);
    var buf: [11]u8 = undefined;
    const out = try timestampToDateString(ts, buf[0..]);
    try std.testing.expectEqualStrings(date, out);
}

test "buildDateRange with until time" {
    const date = "2026-02-03";
    const range = try buildDateRange(date, "12:34", null);
    const start_ts = try db.dateStringToTimestamp(date);
    const expected_end = start_ts + (12 * 3600 + 34 * 60 + 60);
    try std.testing.expectEqual(start_ts, range.start_ts);
    try std.testing.expectEqual(expected_end, range.end_ts);
}

test "cli commands basic" {
    var database = try Database.init(std.testing.allocator, ":memory:");
    defer database.close();

    const add_args = [_][]const u8{
        "food-journal",
        "add",
        "Test Food",
        "100",
        "10",
        "20",
        "5",
        "1",
        "lunch",
        "note",
        "--images",
        "img1.jpg,img2.jpg",
    };
    try addEntry(&database, &add_args);

    try showToday(&database, null, false);

    var date_buf: [11]u8 = undefined;
    const date_str = try timestampToDateString(std.time.timestamp(), date_buf[0..]);
    try showDate(&database, date_str, null, null);

    try showRecent(&database, 10);
    try searchEntries(&database, "Test");

    var entries = try database.getRecentEntries(10);
    defer {
        for (entries.items) |entry| {
            database.allocator.free(entry.name);
            if (entry.notes) |notes| database.allocator.free(notes);
            if (entry.images) |images| database.allocator.free(images);
        }
        entries.deinit(database.allocator);
    }

    try std.testing.expectEqual(@as(usize, 1), entries.items.len);
    const entry_id = entries.items[0].id.?;
    try deleteEntry(&database, entry_id);

    var after_delete = try database.getRecentEntries(10);
    defer {
        for (after_delete.items) |entry| {
            database.allocator.free(entry.name);
            if (entry.notes) |notes| database.allocator.free(notes);
            if (entry.images) |images| database.allocator.free(images);
        }
        after_delete.deinit(database.allocator);
    }
    try std.testing.expectEqual(@as(usize, 0), after_delete.items.len);
}

fn hasFlag(args: []const []const u8, flag: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, flag)) return true;
    }
    return false;
}

fn parseFlagValue(args: []const []const u8, flag: []const u8) !?[]const u8 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], flag)) {
            if (i + 1 >= args.len) return error.MissingFlagValue;
            return args[i + 1];
        }
    }
    return null;
}

fn buildDateRange(date_str: []const u8, until_time: ?[]const u8, label: ?[]const u8) !DateRange {
    const start_ts = try db.dateStringToTimestamp(date_str);
    var end_ts = start_ts + 86400;
    var range_label = label;

    if (until_time) |time_str| {
        const seconds = try parseTimeToSeconds(time_str);
        const end_offset = @min(seconds + 60, 86400);
        end_ts = start_ts + end_offset;
        range_label = time_str;
    } else if (label) |tag| {
        if (std.mem.eql(u8, tag, "now")) {
            const now = std.time.timestamp();
            if (now <= start_ts) {
                end_ts = start_ts;
            } else if (now >= start_ts + 86400) {
                end_ts = start_ts + 86400;
            } else {
                end_ts = now + 1;
            }
        }
    }

    return .{
        .start_ts = start_ts,
        .end_ts = end_ts,
        .label = range_label,
    };
}

fn parseTimeToSeconds(time_str: []const u8) !i64 {
    if (time_str.len != 5 or time_str[2] != ':') return error.InvalidTimeFormat;

    const hour = try std.fmt.parseInt(i64, time_str[0..2], 10);
    const minute = try std.fmt.parseInt(i64, time_str[3..5], 10);

    if (hour < 0 or hour > 23 or minute < 0 or minute > 59) return error.InvalidTimeFormat;

    return hour * 3600 + minute * 60;
}

fn getDatabasePath(allocator: std.mem.Allocator) ![]u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return error.MissingHome,
        else => return err,
    };
    defer allocator.free(home);

    const data_dir = try std.fs.path.join(allocator, &[_][]const u8{
        home,
        ".local",
        "share",
        "food-journal",
    });
    defer allocator.free(data_dir);

    try std.fs.cwd().makePath(data_dir);

    return std.fs.path.join(allocator, &[_][]const u8{
        data_dir,
        DB_NAME,
    });
}
