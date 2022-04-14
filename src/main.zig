const std = @import("std");

/// Encodes a data block with the UU scheme. Will insert the file header, name, mode and a full data block.
/// - `writer` is a `std.io.Writer` that is used to store the output data.
/// - `file_name` is the name of the encoded file. It is not allowed to contain either CR, LF or path separators.
/// - `mode` is the access mode of the encoded file. If not given, it will default to `644`.
/// - `data` is the contents of the file.
pub fn encodeFile(writer: anytype, file_name: []const u8, mode: ?std.fs.File.Mode, data: []const u8) (error{InputTooLarge} || @TypeOf(writer).Error)!void {
    std.debug.assert(std.mem.indexOfAny(u8, file_name, "\\/\r\n") == null); // CR, LF and file system separators are not allowed

    const real_mode = mode orelse 0o644;

    try writer.print("begin {o} {s}\n", .{ real_mode, file_name });

    var i: usize = 0;
    while (i < data.len) : (i += 45) {
        const section_length = std.math.min(data.len - i, 45);
        try encodeLine(writer, data[i..][0..section_length]);
        try writer.writeAll("\n");
    }

    try writer.writeAll("`\n");
    try writer.writeAll("end\n");
}

/// Encodes a single line of data with the UU scheme without the line terminator.
/// - `writer` is a std.io.Writer instance
/// - `data` is the data to be encoded. Maximum allowed length is 45 bytes.
/// Returns a `error.InputTooLarge` if more than 45 bytes are passed, otherwise will
/// return only errors for the writer.
pub fn encodeLine(writer: anytype, data: []const u8) (error{InputTooLarge} || @TypeOf(writer).Error)!void {
    if (data.len == 0) {
        try writer.writeAll("`");
        return;
    }

    if (data.len > 45) {
        return error.InputTooLarge;
    }

    const byte_len = @truncate(u8, data.len);

    try writer.writeByte(0x20 + byte_len);

    var i: usize = 0;
    while (i < data.len) : (i += 3) {
        const section_length = std.math.min(data.len - i, 3);

        var block = [3]u8{ 0, 0, 0 };
        std.mem.copy(u8, &block, data[i .. i + section_length]);

        try writer.print("{s}", .{&encodeBlock(block)});
    }
}

/// Decodes a UU encoded line.
/// - `reader` is the `std.io.Reader` that will provide the bytes
/// - `buffer` is a buffer of 45 bytes to store the result data in.
/// Function returns the decoded bytes.
/// **Note:**
/// The reader will be left at the position directly after the encoded data, but will not consume the line ending.
/// This means that there might be garbage/invalid data on the stream.
pub fn decodeLine(reader: anytype, buffer: *[45]u8) (error{ EndOfStream, IllegalCharacter } || @TypeOf(reader).Error)![]u8 {
    var length_byte = try reader.readByte();
    if (length_byte < 0x20 and length_byte >= 77 and length_byte != '`')
        return error.IllegalCharacter;
    const length = decodeNumber(length_byte) catch unreachable;
    if (length > 45) {
        return error.IllegalCharacter;
    }
    if (length == 0) {
        return buffer[0..0];
    }
    var i: usize = 0;
    while (i < length) : (i += 3) {
        var encoded_block: [4]u8 = undefined;
        try reader.readNoEof(&encoded_block);

        const block = try decodeBlock(encoded_block);

        std.mem.copy(u8, buffer[i .. i + 3], &block);
    }

    return buffer[0..length];
}

/// Encodes three bytes with the uu encoding scheme.
pub fn encodeBlock(block: [3]u8) [4]u8 {
    const group = std.mem.readIntBig(u24, &block);

    const c0 = @truncate(u6, group >> 0);
    const c1 = @truncate(u6, group >> 6);
    const c2 = @truncate(u6, group >> 12);
    const c3 = @truncate(u6, group >> 18);

    return .{
        mapSpaceToGrave(0x20 + @as(u8, c3)),
        mapSpaceToGrave(0x20 + @as(u8, c2)),
        mapSpaceToGrave(0x20 + @as(u8, c1)),
        mapSpaceToGrave(0x20 + @as(u8, c0)),
    };
}

/// Decodes four uu encoded bytes and returns the original bytes.
/// Accepts both space and accent grave as the 0 character.
/// Will return `error.IllegalCharacter` when a character out of range is encountered.
pub fn decodeBlock(encoded: [4]u8) error{IllegalCharacter}![3]u8 {
    const c0 = try decodeNumber(encoded[3]);
    const c1 = try decodeNumber(encoded[2]);
    const c2 = try decodeNumber(encoded[1]);
    const c3 = try decodeNumber(encoded[0]);

    const group = @as(u24, c0) << 0 |
        @as(u24, c1) << 6 |
        @as(u24, c2) << 12 |
        @as(u24, c3) << 18;

    var block: [3]u8 = undefined;
    std.mem.writeIntBig(u24, &block, group);
    return block;
}

fn decodeNumber(val: u8) !u6 {
    return switch (val) {
        '`', ' ' => 0,
        0x21...0x5F => @truncate(u6, val - 0x20),
        else => error.IllegalCharacter,
    };
}

fn mapSpaceToGrave(in: u8) u8 {
    return if (in == 0x20)
        '`'
    else
        in;
}

fn testLineEncoding(expected: []const u8, data: []const u8) !void {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try encodeLine(buffer.writer(), data);

    try std.testing.expectEqualStrings(expected, buffer.items);
}

test "line encoding" {
    try testLineEncoding("#0V%T", "Cat");
    try testLineEncoding("::'1T<#HO+W=W=RYW:6MI<&5D:6$N;W)G#0H`", "http://www.wikipedia.org\r\n");
}

fn testFileEncoding(expected: []const []const u8, file_name: []const u8, mode: ?std.fs.File.Mode, data: []const u8) !void {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try encodeFile(buffer.writer(), file_name, mode, data);

    var expected_string = std.ArrayList(u8).init(std.testing.allocator);
    defer expected_string.deinit();

    for (expected) |line| {
        try expected_string.writer().print("{s}\n", .{line});
    }

    try std.testing.expectEqualStrings(expected_string.items, buffer.items);
}

test "file encoding" {
    try testFileEncoding(&.{
        "begin 644 cat.txt",
        "#0V%T",
        "`",
        "end",
    }, "cat.txt", null, "Cat");
    try testFileEncoding(&.{
        "begin 644 wikipedia-url.txt",
        "::'1T<#HO+W=W=RYW:6MI<&5D:6$N;W)G#0H`",
        "`",
        "end",
    }, "wikipedia-url.txt", 0o644, "http://www.wikipedia.org\r\n");
    try testFileEncoding(&.{
        "begin 123 lorem.txt",
        "M3&]R96T@:7!S=6T@9&]L;W(@<VET(&%M970L(&-O;G-E8W1E='5E<B!A9&EP",
        "M:7-C:6YG(&5L:70N($%E;F5A;B!C;VUM;V1O(&QI9W5L82!E9V5T(&1O;&]R",
        "M+B!!96YE86X@;6%S<V$N($-U;2!S;V-I:7,@;F%T;W%U92!P96YA=&EB=7,@",
        "M970@;6%G;FES(&1I<R!P87)T=7)I96YT(&UO;G1E<RP@;F%S8V5T=7(@<FED",
        "M:6-U;'5S(&UU<RX@1&]N96,@<75A;2!F96QI<RP@=6QT<FEC:65S(&YE8RP@",
        "M<&5L;&5N=&5S<75E(&5U+\"!P<F5T:75M('%U:7,L('-E;2X@3G5L;&$@8V]N",
        "M<V5Q=6%T(&UA<W-A('%U:7,@96YI;2X@1&]N96,@<&5D92!J=7-T;RP@9G)I",
        "M;F=I;&QA('9E;\"P@86QI<75E=\"!N96,L('9U;'!U=&%T92!E9V5T+\"!A<F-U",
        "M+B!);B!E;FEM(&IU<W1O+\"!R:&]N8W5S('5T+\"!I;7!E<F1I970@82P@=F5N",
        "M96YA=&ES('9I=&%E+\"!J=7-T;RX@3G5L;&%M(&1I8W1U;2!F96QI<R!E=2!P",
        "M961E(&UO;&QI<R!P<F5T:75M+B!);G1E9V5R('1I;F-I9'5N=\"X@0W)A<R!D",
        "M87!I8G5S+B!6:79A;75S(&5L96UE;G1U;2!S96UP97(@;FES:2X@065N96%N",
        "M('9U;'!U=&%T92!E;&5I9F5N9\"!T96QL=7,N($%E;F5A;B!L96\\@;&EG=6QA",
        "M+\"!P;W)T=&ET;W(@974L(&-O;G-E<75A=\"!V:71A92P@96QE:69E;F0@86,L",
        "M(&5N:6TN($%L:7%U86T@;&]R96T@86YT92P@9&%P:6)U<R!I;BP@=FEV97)R",
        "M82!Q=6ES+\"!F975G:6%T(&$L('1E;&QU<RX@4&AA<V5L;'5S('9I=F5R<F$@",
        "M;G5L;&$@=70@;65T=7,@=F%R:75S(&QA;W)E970N(%%U:7-Q=64@<G5T<G5M",
        "M+B!!96YE86X@:6UP97)D:65T+B!%=&EA;2!U;'1R:6-I97,@;FES:2!V96P@",
        "M875G=64N($-U<F%B:71U<B!U;&QA;6-O<G!E<B!U;'1R:6-I97,@;FES:2X@",
        "M3F%M(&5G970@9'5I+B!%=&EA;2!R:&]N8W5S+B!-865C96YA<R!T96UP=7,L",
        "M('1E;&QU<R!E9V5T(&-O;F1I;65N='5M(')H;VYC=7,L('-E;2!Q=6%M('-E",
        "M;7!E<B!L:6)E<F\\L('-I=\"!A;65T(&%D:7!I<V-I;F<@<V5M(&YE<75E('-E",
        "M9\"!I<'-U;2X@3F%M('%U86T@;G5N8RP@8FQA;F1I=\"!V96PL(&QU8W1U<R!P",
        "M=6QV:6YA<BP@:&5N9')E<FET(&ED+\"!L;W)E;2X@36%E8V5N87,@;F5C(&]D",
        "M:6\\@970@86YT92!T:6YC:61U;G0@=&5M<'5S+B!$;VYE8R!V:71A92!S87!I",
        "M96X@=70@;&EB97)O('9E;F5N871I<R!F875C:6)U<RX@3G5L;&%M('%U:7,@",
        "M86YT92X@171I86T@<VET(&%M970@;W)C:2!E9V5T(&5R;W,@9F%U8VEB=7,@",
        "M=&EN8VED=6YT+B!$=6ES(&QE;RX@4V5D(&9R:6YG:6QL82!M875R:7,@<VET",
        "M(&%M970@;FEB:\"X@1&]N96,@<V]D86QE<R!S86=I='1I<R!M86=N82X@4V5D",
        "M(&-O;G-E<75A=\"P@;&5O(&5G970@8FEB96YD=6T@<V]D86QE<RP@875G=64@",
        "2=F5L:70@8W5R<W5S(&YU;F,L",
        "`",
        "end",
    }, "lorem.txt", 0o123, "Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Aenean commodo ligula eget dolor. Aenean massa. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Donec quam felis, ultricies nec, pellentesque eu, pretium quis, sem. Nulla consequat massa quis enim. Donec pede justo, fringilla vel, aliquet nec, vulputate eget, arcu. In enim justo, rhoncus ut, imperdiet a, venenatis vitae, justo. Nullam dictum felis eu pede mollis pretium. Integer tincidunt. Cras dapibus. Vivamus elementum semper nisi. Aenean vulputate eleifend tellus. Aenean leo ligula, porttitor eu, consequat vitae, eleifend ac, enim. Aliquam lorem ante, dapibus in, viverra quis, feugiat a, tellus. Phasellus viverra nulla ut metus varius laoreet. Quisque rutrum. Aenean imperdiet. Etiam ultricies nisi vel augue. Curabitur ullamcorper ultricies nisi. Nam eget dui. Etiam rhoncus. Maecenas tempus, tellus eget condimentum rhoncus, sem quam semper libero, sit amet adipiscing sem neque sed ipsum. Nam quam nunc, blandit vel, luctus pulvinar, hendrerit id, lorem. Maecenas nec odio et ante tincidunt tempus. Donec vitae sapien ut libero venenatis faucibus. Nullam quis ante. Etiam sit amet orci eget eros faucibus tincidunt. Duis leo. Sed fringilla mauris sit amet nibh. Donec sodales sagittis magna. Sed consequat, leo eget bibendum sodales, augue velit cursus nunc,");
}

// The fuzzer test tries to shove semiish large data into the encoder with random lengths and contents.
// This test is not here to test correctness but to check for any unhandled edge cases by randomly yeeting
// data at the encoder. The encoder should never break/panic/error for valid inputs.
test "fuzz encoder" {

    // this test runs for at least a certain time and number of rounds to make sure we test the encoder on random inputs
    const duration = 1500 * std.time.ns_per_ms; // at least this long
    const limit = 64; // at least this number of rounds

    var input = try std.testing.allocator.alloc(u8, 1 << 20); // alloc 1 MB of data
    defer std.testing.allocator.free(input);

    var random = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp()));
    const rng = random.random();

    const end = std.time.nanoTimestamp() + duration;

    var count: usize = 0;

    while (count < limit or std.time.nanoTimestamp() < end) : (count += 1) {
        const length = rng.intRangeAtMost(usize, 0, input.len);

        const buffer = input[0..length];
        rng.bytes(buffer);

        var counter = std.io.countingWriter(std.io.null_writer);

        try encodeFile(counter.writer(), "empty", null, buffer);

        try std.testing.expect(counter.bytes_written >= buffer.len / 45); // at least write one line per chunk!
    }

    // std.debug.print("fuzzing encoder cycles: {}\n", .{count});
}

// This fuzzer will dest the decodeLine function by encoding a good amount of random lines of random length,
// then decoding the line again and check for equality.
// If the returned value isn't exactly as encoded, we implemented something wrong.
test "fuzz line encoder/decoder" {

    // this test runs for at least a certain time and number of rounds to make sure we test the encoder on random inputs
    const duration = 1500 * std.time.ns_per_ms; // at least this long
    const limit = 1024; // at least this number of rounds

    var random = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp()));
    const rng = random.random();

    const end = std.time.nanoTimestamp() + duration;

    var count: usize = 0;

    while (count < limit or std.time.nanoTimestamp() < end) : (count += 1) {
        var line_data: [45]u8 = undefined;

        const length = rng.intRangeAtMost(usize, 0, line_data.len);
        const src_buffer = line_data[0..length];
        rng.bytes(src_buffer);

        var encoded_data: [128]u8 = undefined;
        var writer = std.io.fixedBufferStream(&encoded_data);
        try encodeLine(writer.writer(), src_buffer);

        var reader = std.io.fixedBufferStream(writer.getWritten());

        var mem: [45]u8 = undefined;
        const decoded_data = try decodeLine(reader.reader(), &mem);

        // validate we decoded the right data.
        std.testing.expectEqualSlices(u8, src_buffer, decoded_data) catch |err| {
            std.debug.print("input:   {any}\n", .{src_buffer});
            std.debug.print("encoded: [{s}]\n", .{writer.getWritten()});
            std.debug.print("output:  {any}\n", .{decoded_data});
            return err;
        };

        // validate we read exactly the encoded data.
        std.testing.expectEqual(writer.getWritten().len, reader.getPos() catch unreachable) catch |err| {
            std.debug.print("input:   {any}\n", .{src_buffer});
            std.debug.print("encoded: [{s}]\n", .{writer.getWritten()});
            std.debug.print("output:  {any}\n", .{decoded_data});
            return err;
        };
    }

    // std.debug.print("fuzzing line cycles: {}\n", .{count});
}
