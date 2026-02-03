const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get the zqlite dependency
    const zqlite_dep = b.dependency("zqlite", .{
        .target = target,
        .optimize = optimize,
    });

    // Create the main module
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add the zqlite module
    exe_mod.addImport("zqlite", zqlite_dep.module("zqlite"));

    // Create the main executable
    const exe = b.addExecutable(.{
        .name = "food-journal",
        .root_module = exe_mod,
    });

    addSqlite(exe.root_module, zqlite_dep);

    // Install the executable
    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    run_step.dependOn(&run_cmd.step);

    // Test step
    const test_step = b.step("test", "Run tests");

    const model_test_mod = b.createModule(.{
        .root_source_file = b.path("src/models.zig"),
        .target = target,
        .optimize = optimize,
    });

    const model_tests = b.addTest(.{
        .root_module = model_test_mod,
    });
    const run_model_tests = b.addRunArtifact(model_tests);
    test_step.dependOn(&run_model_tests.step);

    const main_test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_test_mod.addImport("zqlite", zqlite_dep.module("zqlite"));

    const main_tests = b.addTest(.{
        .root_module = main_test_mod,
    });
    addSqlite(main_tests.root_module, zqlite_dep);
    const run_main_tests = b.addRunArtifact(main_tests);
    test_step.dependOn(&run_main_tests.step);
}

fn addSqlite(module: *std.Build.Module, zqlite_dep: *std.Build.Dependency) void {
    module.addIncludePath(zqlite_dep.path("lib"));
    module.addCSourceFile(.{
        .file = zqlite_dep.path("lib/sqlite3.c"),
        .flags = &[_][]const u8{
            "-DSQLITE_DQS=0",
            "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1",
            "-DSQLITE_USE_ALLOCA=1",
            "-DSQLITE_THREADSAFE=1",
            "-DSQLITE_TEMP_STORE=3",
            "-DSQLITE_ENABLE_API_ARMOR=1",
            "-DSQLITE_ENABLE_UNLOCK_NOTIFY",
            "-DSQLITE_DEFAULT_FILE_PERMISSIONS=0600",
            "-DSQLITE_OMIT_DECLTYPE=1",
            "-DSQLITE_OMIT_DEPRECATED=1",
            "-DSQLITE_OMIT_LOAD_EXTENSION=1",
            "-DSQLITE_OMIT_PROGRESS_CALLBACK=1",
            "-DSQLITE_OMIT_SHARED_CACHE",
            "-DSQLITE_OMIT_TRACE=1",
            "-DSQLITE_OMIT_UTF16=1",
            "-DHAVE_USLEEP=0",
        },
    });
    module.link_libc = true;
}
