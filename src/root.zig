const std = @import("std");
const libregex = @cImport({
    @cInclude("c_src/regex_adapter.h");
});

const expect = std.testing.expect;

pub const MatchIterator = struct {
    regex: Regex,
    allocator: std.mem.Allocator,
    offset: usize,
    input: [:0]const u8,

    pub fn init(allocator: std.mem.Allocator, r: Regex, input: []const u8) !MatchIterator {
        const c_str: [:0]u8 = try std.mem.Allocator.dupeZ(allocator, u8, input);

        return .{
            .allocator = allocator,
            .input = c_str,
            .regex = r,
            .offset = 0,
        };
    }

    pub fn deinit(self: MatchIterator) void {
        self.allocator.free(self.input);
    }

    pub fn next(self: *MatchIterator) ?[]const u8 {
        if (self.offset >= self.input.len - 1) {
            return null;
        }

        const input: [:0]const u8 = self.input[self.offset..self.input.len :0];
        var pmatch: [1]libregex.regmatch_t = undefined;
        const result = libregex.regexec(self.regex.inner, input, 1, &pmatch, 0);
        if (result != 0) {
            return null;
        }
        defer {
            self.offset += @as(usize, @intCast(pmatch[0].rm_so)) + 1;
        }

        const start = @as(usize, @intCast(pmatch[0].rm_so)) + self.offset;
        const end = @as(usize, @intCast(pmatch[0].rm_eo)) + self.offset;

        return self.input[start..end];
    }
};

pub const ExecIterator = struct {
    regex: Regex,
    allocator: std.mem.Allocator,
    offset: usize,
    input: std.ArrayList(u8),
    exec_results: std.ArrayList(std.ArrayList([]const u8)),

    pub fn init(allocator: std.mem.Allocator, r: Regex, input: []const u8) !ExecIterator {
        var c_str = std.ArrayList(u8).init(allocator);
        for (input) |char| try c_str.append(char);
        try c_str.append(0);

        return .{
            .allocator = allocator,
            .input = c_str,
            .regex = r,
            .offset = 0,
            .exec_results = std.ArrayList(std.ArrayList([]const u8)).init(allocator),
        };
    }

    pub fn deinit(self: ExecIterator) void {
        for (self.exec_results.items) |res| {
            res.deinit();
        }
        self.input.deinit();
        self.exec_results.deinit();
    }

    pub fn next(self: *ExecIterator) !?[][]const u8 {
        if (self.offset >= self.input.items.len - 1) {
            return null;
        }

        const input: [:0]const u8 = self.input.items[self.offset .. self.input.items.len - 1 :0];
        const exec_result = libregex.exec(self.regex.inner, input, self.regex.num_subexpressions, 0);
        defer libregex.free_match_ptr(exec_result.matches);

        if (exec_result.exec_code != 0) {
            if (exec_result.exec_code == libregex.REG_NOMATCH) return null;

            return error.OutOfMemory;
        }

        var match_list = std.ArrayList([]const u8).init(self.allocator);
        try self.exec_results.append(match_list);

        if (exec_result.matches[0].rm_so == exec_result.matches[0].rm_eo) {
            return null;
        }

        var offset_increment: usize = 0;

        for (exec_result.matches, 0..exec_result.n_matches) |_, i| {
            const pmatch = exec_result.matches[i];
            const start = @as(usize, @intCast(pmatch.rm_so));
            const end = @as(usize, @intCast(pmatch.rm_eo));

            const start_of_original_input = start + self.offset;
            const end_of_original_input = end + self.offset;

            const match: []const u8 = self.input.items[start_of_original_input..end_of_original_input];

            if (i == 0) {
                offset_increment = start + 1;
            }

            try match_list.append(match);
        }

        self.offset += offset_increment;

        return match_list.items;
    }
};

const Regex = struct {
    inner: *libregex.regex_t,
    num_subexpressions: c_ulonglong,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, pattern: []const u8, flags: c_int) !Regex {
        const c_str = try std.mem.Allocator.dupeZ(allocator, u8, pattern);
        defer allocator.free(c_str);

        const res = libregex.compile_regex(c_str, flags);
        if (res.compiled_regex == null) {
            return error.compile;
        }

        return .{
            .inner = res.compiled_regex.?,
            .num_subexpressions = res.re_nsub,
            .allocator = allocator,
        };
    }

    fn deinit(self: Regex) void {
        libregex.free_regex_t(self.inner);
    }

    fn matches(self: Regex, input: []const u8) !bool {
        const c_str: [:0]u8 = try std.mem.Allocator.dupeZ(self.allocator, u8, input);
        defer self.allocator.free(c_str);

        const result = libregex.regexec(self.inner, c_str, 0, null, 0);

        if (result == 0) return true;
        if (result == libregex.REG_NOMATCH) return false;

        return error.OutOfMemory;
    }

    fn getMatchIterator(self: Regex, input: []const u8) !MatchIterator {
        return MatchIterator.init(self.allocator, self, input);
    }

    fn getExecIterator(self: Regex, input: []const u8) !ExecIterator {
        return ExecIterator.init(self.allocator, self, input);
    }
};

test "matches" {
    const r = try Regex.init(std.testing.allocator, "^v[0-9]+.[0-9]+.[0-9]+", libregex.REG_EXTENDED);
    defer r.deinit();

    try expect(try r.matches("v1.2.3"));
    try expect(try r.matches("v1.22.101"));
    try expect(!try r.matches("1.2.3"));
}

test "full match iterator" {
    const r = try Regex.init(std.testing.allocator, "(v)([0-9]+.[0-9]+.[0-9]+)", libregex.REG_EXTENDED);
    defer r.deinit();

    const input: []const u8 =
        \\ The latest stable version is v2.1.0. If you are using an older verison of x then please use v1.12.2
        \\ You can also try the nightly version v2.2.0-beta-2
    ;

    var iterator = try r.getMatchIterator(input);
    defer iterator.deinit();

    try expect(std.mem.eql(u8, "v2.1.0", iterator.next().?));
    try expect(std.mem.eql(u8, "v1.12.2", iterator.next().?));
    try expect(std.mem.eql(u8, "v2.2.0", iterator.next().?));

    try expect(iterator.next() == null);
}

test "exec iterator" {
    const r = try Regex.init(std.testing.allocator, "(v)([0-9]+.[0-9]+.[0-9]+)", libregex.REG_EXTENDED);
    defer r.deinit();

    const input: []const u8 = "Latest stable version is v1.2.2. Latest version is v1.3.0";
    var expected: []const []const u8 = undefined;
    var exec_result: [][]const u8 = undefined;

    var exec_iterator = try r.getExecIterator(input);
    defer exec_iterator.deinit();

    expected = &[_][]const u8{ "v1.2.2", "v", "1.2.2" };
    exec_result = (try exec_iterator.next()).?;

    for (expected, 0..) |e, i| {
        try expect(std.mem.eql(u8, e, exec_result[i]));
    }

    expected = &[_][]const u8{ "v1.3.0", "v", "1.3.0" };
    exec_result = (try exec_iterator.next()).?;
    for (expected, 0..) |e, i| {
        try expect(std.mem.eql(u8, e, exec_result[i]));
    }

    try expect(try exec_iterator.next() == null);
}
