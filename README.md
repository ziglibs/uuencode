# uuencode

A [uuencode](https://en.wikipedia.org/wiki/Uuencoding) implementation for Zig.

This is both a package as well as a command line utility.

## API

```zig
// encoders:
pub fn encodeFile(writer: anytype, file_name: []const u8, mode: ?std.fs.File.Mode, data: []const u8) !void;
pub fn encodeLine(writer: anytype, data: []const u8) !void;

// decoders:
pub fn decodeLine(reader: anytype, buffer: *[45]u8) ![]u8;


// primitive functions:
pub fn encodeBlock(block: [3]u8) [4]u8;
pub fn decodeBlock(encoded: [4]u8) error{IllegalCharacter}![3]u8;
```
