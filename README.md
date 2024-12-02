# Regex library for zig
This library wraps the C regex library and provides a convenient API.

Compatible with zig version `0.0.13`

## Installation
1. Run `zig fetch --save https://github.com/skota-io/zig-regex`
2. In your `build.zig` <br>
todo

## Usage
### 1. Initialize
```zig
const libregex = @import("zig-regex-lib");
const Regex = libregex.Regex;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const pattern = "(v)([0-9]+.[0-9]+.[0-9]+)";
const regex = Regex.init(gpa.allocator(), pattern, libregex.REG_EXTENDED));
defer regex.deinit();
```

### 2. Check if some input matches pattern
```zig
const expect = @import("std").testing.expect;

try expect(try r.matches("v1.22.101"));
try expect(!try r.matches("1.2.3"));
```

### 3. Get all matches in an input
```zig
const expect = @import("std").testing.expect;

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
```

### 4. Find sub-expressions
```zig

const input: []const u8 = "Latest stable version is v1.2.2. Latest version is v1.3.0";

var exec_result: libregex.ExecResult = undefined;
var exec_iterator = try r.getExecIterator(input);

exec_result = (try exec_iterator.next()).?;
try expect(std.mem.eql(u8, exec_result.match_list.items[0], "v1.2.2"));
try expect(std.mem.eql(u8, exec_result.match_list.items[1], "v"));
try expect(std.mem.eql(u8, exec_result.match_list.items[2], "1.2.2"));
exec_result.deinit();

exec_result = (try exec_iterator.next()).?;
try expect(std.mem.eql(u8, exec_result.match_list.items[0], "v1.3.0"));
try expect(std.mem.eql(u8, exec_result.match_list.items[1], "v"));
try expect(std.mem.eql(u8, exec_result.match_list.items[2], "1.3.0"));
exec_result.deinit();

try expect(try exec_iterator.next() == null);
```
