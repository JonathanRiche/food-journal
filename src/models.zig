const std = @import("std");

pub const FoodEntry = struct {
    id: ?i64,
    name: []const u8,
    calories: f64,
    protein: f64, // in grams
    carbs: f64, // in grams
    fat: f64, // in grams
    fiber: f64, // in grams (optional)
    timestamp: i64, // unix timestamp
    meal_type: MealType,
    notes: ?[]const u8,
    images: ?[]const u8,

    pub fn calculateMacros(self: FoodEntry) Macros {
        return .{
            .calories = self.calories,
            .protein = self.protein,
            .carbs = self.carbs,
            .fat = self.fat,
            .fiber = self.fiber,
        };
    }
};

pub const Macros = struct {
    calories: f64,
    protein: f64,
    carbs: f64,
    fat: f64,
    fiber: f64,

    pub fn format(self: Macros, writer: anytype) !void {
        try writer.print(
            "Calories: {d:.0} | Protein: {d:.1}g | Carbs: {d:.1}g | Fat: {d:.1}g | Fiber: {d:.1}g",
            .{ self.calories, self.protein, self.carbs, self.fat, self.fiber },
        );
    }
};

pub const MealType = enum {
    breakfast,
    lunch,
    dinner,
    snack,
    other,

    pub fn fromString(str: []const u8) ?MealType {
        var buf: [20]u8 = undefined;
        const lowered = std.ascii.lowerString(&buf, str);

        if (std.mem.eql(u8, lowered, "breakfast")) return .breakfast;
        if (std.mem.eql(u8, lowered, "lunch")) return .lunch;
        if (std.mem.eql(u8, lowered, "dinner")) return .dinner;
        if (std.mem.eql(u8, lowered, "snack")) return .snack;
        if (std.mem.eql(u8, lowered, "other")) return .other;
        return null;
    }

    pub fn toString(self: MealType) []const u8 {
        return switch (self) {
            .breakfast => "Breakfast",
            .lunch => "Lunch",
            .dinner => "Dinner",
            .snack => "Snack",
            .other => "Other",
        };
    }
};

pub const FoodCacheEntry = struct {
    product_id: []const u8,
    name: []const u8,
    calories_per_100g: f64,
    protein_per_100g: f64,
    carbs_per_100g: f64,
    fat_per_100g: f64,
    fiber_per_100g: f64,
    timestamp: i64,
};

pub const DailySummary = struct {
    date: []const u8,
    total_calories: f64,
    total_protein: f64,
    total_carbs: f64,
    total_fat: f64,
    total_fiber: f64,
    entry_count: i64,

    pub fn format(self: DailySummary, writer: anytype) !void {
        try writer.print(
            \\n=== {s} ===
            \\nEntries: {d}
            \\nTotal Calories: {d:.0}
            \\nTotal Protein: {d:.1}g
            \\nTotal Carbs: {d:.1}g
            \\nTotal Fat: {d:.1}g
            \\nTotal Fiber: {d:.1}g
            \\n
        ,
            .{
                self.date,
                self.entry_count,
                self.total_calories,
                self.total_protein,
                self.total_carbs,
                self.total_fat,
                self.total_fiber,
            },
        );
    }
};
