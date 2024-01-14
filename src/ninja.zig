const std = @import("std");

pub const Rule = struct {
    name: []const u8,
    commands: std.ArrayList([]const u8),
    description: []const u8,
    generator: bool = false,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        description: []const u8,
        generator: bool,
    ) Self {
        const commands = std.ArrayList([]const u8).init(allocator);
        return Self{
            .name = name,
            .commands = commands,
            .description = description,
            .generator = generator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.commands.deinit();
    }

    pub fn append(self: *Self, val: []const u8) !void {
        try self.commands.append(val);
    }

    pub fn toString(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        var command_list = std.ArrayList(u8).init(allocator);
        defer command_list.deinit();

        for (self.commands.items, 0..) |command, idx| {
            if (idx == 0 or idx == self.commands.items.len) {
                try command_list.appendSlice(command);
            } else {
                try command_list.appendSlice(" && $\n            ");
                try command_list.appendSlice(command);
            }
        }

        return try std.fmt.allocPrint(
            allocator,
            \\rule {s}
            \\  command = {s}
            \\  description = {s}
            \\  generator = {d}
        ,
            .{
                self.name,
                command_list.items,
                self.description,
                @intFromBool(self.generator),
            },
        );
    }
};

pub const Build = struct {
    targets: std.ArrayList([]const u8),
    rule: Rule,
    files: std.ArrayList([]const u8),
    deps: std.ArrayList([]const u8),
    ordered_deps: bool,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        rule: Rule,
        ordered_deps: bool,
    ) Self {
        const targets = std.ArrayList([]const u8).init(allocator);
        const files = std.ArrayList([]const u8).init(allocator);
        const deps = std.ArrayList([]const u8).init(allocator);

        return Self{
            .targets = targets,
            .rule = rule,
            .files = files,
            .deps = deps,
            .ordered_deps = ordered_deps,
        };
    }

    pub fn deinit(self: *Self) void {
        self.targets.deinit();
        self.files.deinit();
        self.deps.deinit();
    }

    pub fn appendTarget(self: *Self, val: []const u8) !void {
        try self.targets.append(val);
    }
    pub fn appendFile(self: *Self, val: []const u8) !void {
        try self.files.append(val);
    }
    pub fn appendDep(self: *Self, val: []const u8) !void {
        try self.deps.append(val);
    }

    pub fn toString(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        var target_list = std.ArrayList(u8).init(allocator);
        var file_list = std.ArrayList(u8).init(allocator);
        var dep_list = std.ArrayList(u8).init(allocator);
        defer target_list.deinit();
        defer file_list.deinit();
        defer dep_list.deinit();

        for (self.targets.items, 0..) |target, idx| {
            if (idx == 0 or idx == self.targets.items.len) {
                try target_list.appendSlice(target);
            } else {
                try target_list.appendSlice(" ");
                try target_list.appendSlice(target);
            }
        }

        for (self.files.items, 0..) |file, idx| {
            if (idx == 0 or idx == self.files.items.len) {
                try file_list.appendSlice(file);
            } else {
                try file_list.appendSlice(" ");
                try file_list.appendSlice(file);
            }
        }

        for (self.deps.items, 0..) |dep, idx| {
            if (idx == 0 or idx == self.deps.items.len) {
                try dep_list.appendSlice(dep);
            } else {
                try dep_list.appendSlice(" ");
                try dep_list.appendSlice(dep);
            }
        }

        var separator: []const u8 = undefined;
        if (self.ordered_deps) {
            separator = "||";
        } else {
            separator = "|";
        }

        if (self.deps.items.len >= 1) {
            return try std.fmt.allocPrint(
                allocator,
                "build {s}: {s} {s} {s} {s}",
                .{
                    target_list.items,
                    self.rule.name,
                    file_list.items,
                    separator,
                    dep_list.items,
                },
            );
        } else {
            return try std.fmt.allocPrint(
                allocator,
                "build {s}: {s} {s}\n",
                .{
                    target_list.items,
                    self.rule.name,
                    file_list.items,
                },
            );
        }
    }
};

test "Initialize NinjaRule" {
    const test_allocator = std.testing.allocator;

    var test_rule = Rule.init(test_allocator, "test", "test rule", false);
    defer test_rule.deinit();
    {
        try test_rule.append("touch $in");
        try test_rule.append("echo yay");
    }

    for (test_rule.commands.items, 0..) |item, idx| {
        if (idx == 0) {
            try std.testing.expect(std.mem.eql(u8, "touch $in", item));
        } else if (idx == 1) {
            try std.testing.expect(std.mem.eql(u8, "echo yay", item));
        } else {
            return error.TestUnexpectedResult;
        }
    }
}

test "Format string from NinjaRule" {
    const test_allocator = std.testing.allocator;

    {
        var test_rule_1 = Rule.init(
            test_allocator,
            "test_rule_1",
            "This is a test rule",
            false,
        );
        defer test_rule_1.deinit();
        {
            try test_rule_1.append("yes");
        }

        const test_string_1 = try test_rule_1.toString(test_allocator);
        defer test_allocator.free(test_string_1);

        const expected_string_1 =
            \\rule test_rule_1
            \\  command = yes
            \\  description = This is a test rule
            \\  generator = 0
        ;

        try std.testing.expect(std.mem.eql(u8, test_string_1, expected_string_1));
    }

    {
        var test_rule_2 = Rule.init(
            test_allocator,
            "test_rule_2",
            "This is a test rule",
            false,
        );
        defer test_rule_2.deinit();
        {
            try test_rule_2.append("touch $in");
            try test_rule_2.append("echo did something to $i");
            try test_rule_2.append("echo yay");
        }

        const test_string_2 = try test_rule_2.toString(test_allocator);
        defer test_allocator.free(test_string_2);

        const expected_string_2 =
            \\rule test_rule_2
            \\  command = touch $in $
            \\            echo did something to $i $
            \\            echo yay
            \\  description = This is a test rule
            \\  generator = 0
        ;

        try std.testing.expect(std.mem.eql(u8, test_string_2, expected_string_2));
    }
}

test "Initialize NinjaBuild" {
    const test_allocator = std.testing.allocator;

    var test_rule = Rule.init(test_allocator, "test", "test rule", false);
    defer test_rule.deinit();
    {
        try test_rule.append("yes");
    }

    var test_build = Build.init(test_allocator, test_rule, false);
    {
        try test_build.appendTarget("target");
        try test_build.appendFile("infile_1");
        try test_build.appendFile("infile_2");
        try test_build.appendDep("dep");
    }
    defer test_build.deinit();

    for (test_build.targets.items) |item| {
        try std.testing.expect(std.mem.eql(u8, "target", item));
    }

    for (test_build.files.items, 0..) |item, idx| {
        if (idx == 0) {
            try std.testing.expect(std.mem.eql(u8, "infile_1", item));
        } else if (idx == 1) {
            try std.testing.expect(std.mem.eql(u8, "infile_2", item));
        } else {
            return error.TestUnexpectedResult;
        }
    }

    for (test_build.deps.items) |item| {
        try std.testing.expect(std.mem.eql(u8, "dep", item));
    }
}

test "Format string from NinjaBuild" {
    const test_allocator = std.testing.allocator;

    var test_rule = Rule.init(test_allocator, "test_rule", "test rule", false);
    defer test_rule.deinit();
    {
        try test_rule.append("yes");
    }

    var test_build = Build.init(test_allocator, test_rule, false);
    {
        try test_build.appendTarget("target_1");
        try test_build.appendTarget("target_2");
        try test_build.appendFile("infile_1");
        try test_build.appendFile("infile_2");
        try test_build.appendDep("dep");
    }
    defer test_build.deinit();

    const test_string_1 = try test_build.toString(test_allocator);
    defer test_allocator.free(test_string_1);

    const expected_string_1 =
        "build target_1 target_2: test_rule infile_1 infile_2 | dep";

    try std.testing.expect(std.mem.eql(u8, test_string_1, expected_string_1));
}
