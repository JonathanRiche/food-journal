const std = @import("std");

pub const FoodProduct = struct {
    product_id: []const u8,
    name: []const u8,
    calories_per_100g: f64,
    protein_per_100g: f64,
    carbs_per_100g: f64,
    fat_per_100g: f64,
    fiber_per_100g: f64,
};

var last_request_ms: ?i128 = null;

fn rateLimit() void {
    const now = std.time.milliTimestamp();
    if (last_request_ms) |last| {
        const elapsed = now - last;
        if (elapsed < 1000) {
            const remaining: u64 = @intCast(1000 - elapsed);
            std.Thread.sleep(remaining * std.time.ns_per_ms);
        }
    }
    last_request_ms = std.time.milliTimestamp();
}

pub fn searchProducts(allocator: std.mem.Allocator, query: []const u8) !std.ArrayList(FoodProduct) {
    rateLimit();

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var encoded_writer = std.Io.Writer.Allocating.init(allocator);
    defer encoded_writer.deinit();
    const component = std.Uri.Component{ .raw = query };
    try component.formatQuery(&encoded_writer.writer);
    const encoded_query = try encoded_writer.toOwnedSlice();
    defer allocator.free(encoded_query);

    const url = try std.fmt.allocPrint(allocator,
        "https://world.openfoodfacts.org/cgi/search.pl?search_terms={s}&json=1&page_size=10",
        .{encoded_query},
    );
    defer allocator.free(url);

    var body_writer = std.Io.Writer.Allocating.init(allocator);
    defer body_writer.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .response_writer = &body_writer.writer,
        .headers = .{ .accept_encoding = .{ .override = "identity" } },
    });

    if (result.status != .ok) {
        return error.ApiRequestFailed;
    }

    const body = try body_writer.toOwnedSlice();
    if (body.len > 5 * 1024 * 1024) return error.ResponseTooLarge;
    defer allocator.free(body);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();

    var products: std.ArrayList(FoodProduct) = .empty;
    errdefer {
        for (products.items) |item| {
            allocator.free(item.product_id);
            allocator.free(item.name);
        }
        products.deinit(allocator);
    }

    const root = parsed.value;
    const products_val = root.object.get("products") orelse return products;
    if (products_val != .array) return products;

    for (products_val.array.items) |item| {
        if (item != .object) continue;
        const obj = item.object;
        const id_val = obj.get("code") orelse continue;
        const name_val = obj.get("product_name") orelse continue;
        if (id_val != .string or name_val != .string) continue;

        const nutriments_val = obj.get("nutriments");

        const calories = getJsonNumber(nutriments_val, "energy-kcal_100g") orelse getJsonNumber(nutriments_val, "energy-kcal") orelse 0;
        const protein = getJsonNumber(nutriments_val, "proteins_100g") orelse 0;
        const carbs = getJsonNumber(nutriments_val, "carbohydrates_100g") orelse 0;
        const fat = getJsonNumber(nutriments_val, "fat_100g") orelse 0;
        const fiber = getJsonNumber(nutriments_val, "fiber_100g") orelse 0;

        const product = FoodProduct{
            .product_id = try allocator.dupe(u8, id_val.string),
            .name = try allocator.dupe(u8, name_val.string),
            .calories_per_100g = calories,
            .protein_per_100g = protein,
            .carbs_per_100g = carbs,
            .fat_per_100g = fat,
            .fiber_per_100g = fiber,
        };

        try products.append(allocator, product);
    }

    return products;
}

fn getJsonNumber(value_opt: ?std.json.Value, key: []const u8) ?f64 {
    const value = value_opt orelse return null;
    if (value != .object) return null;
    const obj = value.object;
    const entry = obj.get(key) orelse return null;
    return switch (entry) {
        .float => |v| v,
        .integer => |v| @floatFromInt(v),
        .string => |s| std.fmt.parseFloat(f64, s) catch null,
        else => null,
    };
}
