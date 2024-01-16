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

        var generator_str: []const u8 = undefined;
        if (self.generator) {
            generator_str = "\n  generator = 1";
        } else {
            generator_str = "";
        }

        return try std.fmt.allocPrint(
            allocator,
            \\rule {s}
            \\  command = {s}
            \\  description = {s}{s}
        ,
            .{
                self.name,
                command_list.items,
                self.description,
                generator_str,
            },
        );
    }
};

pub const Build = struct {
    outputs: std.ArrayList([]const u8),
    implicit_outputs: std.ArrayList([]const u8),
    rule: Rule,
    dependencies: std.ArrayList([]const u8),
    implicit_dependencies: std.ArrayList([]const u8),
    ordered_deps: bool,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        rule: Rule,
        ordered_deps: bool,
    ) Self {
        const outputs = std.ArrayList([]const u8).init(allocator);
        const implicit_outputs = std.ArrayList([]const u8).init(allocator);
        const dependencies = std.ArrayList([]const u8).init(allocator);
        const implicit_dependencies = std.ArrayList([]const u8).init(allocator);

        return Self{
            .outputs = outputs,
            .implicit_outputs = implicit_outputs,
            .rule = rule,
            .dependencies = dependencies,
            .implicit_dependencies = implicit_dependencies,
            .ordered_deps = ordered_deps,
        };
    }

    pub fn deinit(self: *Self) void {
        self.outputs.deinit();
        self.implicit_outputs.deinit();
        self.dependencies.deinit();
        self.implicit_dependencies.deinit();
    }

    pub fn append(
        self: *Self,
        comptime scope: @Type(.EnumLiteral),
        val: []const u8,
    ) !void {
        switch (scope) {
            .output => try self.outputs.append(val),
            .implicit_output => try self.implicit_outputs.append(val),
            .dependency => try self.dependencies.append(val),
            .implicit_dependency => try self.implicit_dependencies.append(val),

            else => return error.UnknownScope,
        }
    }

    pub fn toString(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        var output_list = std.ArrayList(u8).init(allocator);
        var implicit_output_list = std.ArrayList(u8).init(allocator);
        var dependency_list = std.ArrayList(u8).init(allocator);
        var implicit_dependency_list = std.ArrayList(u8).init(allocator);
        defer output_list.deinit();
        defer implicit_output_list.deinit();
        defer dependency_list.deinit();
        defer implicit_dependency_list.deinit();

        for (self.outputs.items, 0..) |output, idx| {
            if (idx == 0 or idx == self.outputs.items.len) {
                try output_list.appendSlice(output);
            } else {
                try output_list.appendSlice(" ");
                try output_list.appendSlice(output);
            }
        }

        for (self.implicit_outputs.items, 0..) |implicit_output, idx| {
            if (idx == 0 or idx == self.implicit_outputs.items.len) {
                try implicit_output_list.appendSlice(implicit_output);
            } else {
                try implicit_output_list.appendSlice(" ");
                try implicit_output_list.appendSlice(implicit_output);
            }
        }

        for (self.dependencies.items, 0..) |dependency, idx| {
            if (idx == 0 or idx == self.dependencies.items.len) {
                try dependency_list.appendSlice(dependency);
            } else {
                try dependency_list.appendSlice(" ");
                try dependency_list.appendSlice(dependency);
            }
        }

        for (self.implicit_dependencies.items, 0..) |implicit_dependency, idx| {
            if (idx == 0 or idx == self.implicit_dependencies.items.len) {
                try implicit_dependency_list.appendSlice(implicit_dependency);
            } else {
                try implicit_dependency_list.appendSlice(" ");
                try implicit_dependency_list.appendSlice(implicit_dependency);
            }
        }

        var dep_separator: []const u8 = undefined;
        if (self.implicit_dependencies.items.len == 0) {
            dep_separator = "";
        } else if (self.ordered_deps) {
            dep_separator = " || ";
        } else {
            dep_separator = " | ";
        }

        var output_separator: []const u8 = undefined;
        if (self.implicit_outputs.items.len >= 1) {
            output_separator = " | ";
        } else {
            output_separator = "";
        }

        return try std.fmt.allocPrint(
            allocator,
            "build {s}{s}{s}: {s} {s}{s}{s}",
            .{
                output_list.items,
                output_separator,
                implicit_output_list.items,
                self.rule.name,
                dependency_list.items,
                dep_separator,
                implicit_dependency_list.items,
            },
        );
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
            try std.testing.expectEqualStrings("touch $in", item);
        } else if (idx == 1) {
            try std.testing.expectEqualStrings("echo yay", item);
        } else {
            return error.TestUnexpectedResult;
        }
    }
}

test "Format string from NinjaRule" {
    const test_allocator = std.testing.allocator;

    {
        var test_rule = Rule.init(
            test_allocator,
            "test_rule",
            "This is a test rule",
            false,
        );
        defer test_rule.deinit();
        {
            try test_rule.append("yes");
        }

        const test_string_1 = try test_rule.toString(test_allocator);
        defer test_allocator.free(test_string_1);

        const expected_string_1 =
            \\rule test_rule
            \\  command = yes
            \\  description = This is a test rule
        ;

        try std.testing.expectEqualStrings(test_string_1, expected_string_1);
    }

    {
        var test_rule = Rule.init(
            test_allocator,
            "test_rule",
            "This is a test rule",
            false,
        );
        defer test_rule.deinit();
        {
            try test_rule.append("touch $in");
            try test_rule.append("echo did something to $i");
            try test_rule.append("echo yay");
        }

        const test_string = try test_rule.toString(test_allocator);
        defer test_allocator.free(test_string);

        const expected_string =
            \\rule test_rule
            \\  command = touch $in && $
            \\            echo did something to $i && $
            \\            echo yay
            \\  description = This is a test rule
        ;

        try std.testing.expectEqualStrings(test_string, expected_string);
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
        try test_build.append(.output, "output");
        try test_build.append(.implicit_output, "implicit_output");
        try test_build.append(.dependency, "dependency_1");
        try test_build.append(.dependency, "dependency_2");
        try test_build.append(.implicit_dependency, "implicit_dependency");

        try std.testing.expectError(
            error.UnknownScope,
            test_build.append(.something_unscoped, ":^("),
        );
    }
    defer test_build.deinit();

    for (test_build.outputs.items) |item| {
        try std.testing.expectEqualStrings("output", item);
    }

    for (test_build.implicit_outputs.items) |item| {
        try std.testing.expectEqualStrings("implicit_output", item);
    }

    for (test_build.dependencies.items, 0..) |item, idx| {
        if (idx == 0) {
            try std.testing.expectEqualStrings("dependency_1", item);
        } else if (idx == 1) {
            try std.testing.expectEqualStrings("dependency_2", item);
        } else {
            return error.TestUnexpectedResult;
        }
    }

    for (test_build.implicit_dependencies.items) |item| {
        try std.testing.expectEqualStrings("implicit_dependency", item);
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
        try test_build.append(.output, "output_1");
        try test_build.append(.implicit_output, "output_2");
        try test_build.append(.dependency, "dependency");
        try test_build.append(.implicit_dependency, "implicit_dependency");
    }
    defer test_build.deinit();

    const test_string = try test_build.toString(test_allocator);
    defer test_allocator.free(test_string);

    const expected_string =
        "build output_1 | output_2: test_rule dependency | implicit_dependency";

    try std.testing.expectEqualStrings(test_string, expected_string);
}
