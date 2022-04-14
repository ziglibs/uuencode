const std = @import("std");

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

        const group = std.mem.readIntBig(u24, &block);

        const c0 = @truncate(u6, group >> 0);
        const c1 = @truncate(u6, group >> 6);
        const c2 = @truncate(u6, group >> 12);
        const c3 = @truncate(u6, group >> 18);

        try writer.print("{c}{c}{c}{c}", .{
            mapSpaceToGrave(0x20 + @as(u8, c3)),
            mapSpaceToGrave(0x20 + @as(u8, c2)),
            mapSpaceToGrave(0x20 + @as(u8, c1)),
            mapSpaceToGrave(0x20 + @as(u8, c0)),
        });
    }
}

fn mapSpaceToGrave(in: u8) u8 {
    return if (in == 0x20)
        '`'
    else
        in;
}

pub fn encodeFile(writer: anytype, file_name: []const u8, mode: ?std.fs.File.Mode, data: []const u8) !void {
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
