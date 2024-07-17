const std = @import("std");
const assert = std.debug.assert;

pub fn progressiveSliceMatch(
    comptime T: type,
    candidates: []const []const T,
) error{ NotSorted, DuplicateEntry }!ProgressiveSliceMatch(T) {
    const Pmc = ProgressiveSliceMatch(T);
    return try Pmc.init(candidates);
}

pub fn ProgressiveSliceMatch(comptime T: type) type {
    return struct {
        candidates: []const []const T,
        current_index: usize = 0,
        query_len: usize = 0,

        const Self = @This();

        pub fn init(candidates: []const []const T) error{ NotSorted, DuplicateEntry }!Self {
            var pmc = Self{ .candidates = &.{} };
            try pmc.resetWith(candidates);
            return pmc;
        }

        /// Clears the search query.
        pub fn clear(pmc: *Self) void {
            std.debug.assert(pmc.candidates.len != 0);
            pmc.* = .{ .candidates = pmc.candidates };
        }

        pub fn resetWith(pmc: *Self, candidates: []const []const T) error{ NotSorted, DuplicateEntry }!void {
            assert(candidates.len != 0);
            for (candidates[0 .. candidates.len - 1], candidates[1..]) |a, b| {
                try switch (std.mem.order(T, a, b)) {
                    .lt => {},
                    .eq => error.DuplicateEntry,
                    .gt => error.NotSorted,
                };
            }
            pmc.* = .{
                .candidates = candidates,
            };
        }

        pub inline fn getMatch(pse: Self) ?[]const T {
            const candidate = pse.getClosestCandidate() orelse return null;
            if (candidate.len > pse.query_len) return null;
            assert(candidate.len == pse.query_len);
            return candidate;
        }

        pub inline fn getMatchedSubstring(pmc: Self) ?[]const T {
            if (pmc.current_index == pmc.candidates.len) return null;
            const candidate = pmc.candidates[pmc.current_index];
            return candidate[0..pmc.query_len];
        }

        pub inline fn getClosestCandidate(pmc: Self) ?[]const T {
            if (pmc.current_index == pmc.candidates.len) return null;
            const closest = pmc.candidates[pmc.current_index];
            if (pmc.query_len == 0 and closest.len != 0) return null;
            return closest;
        }

        /// Asserts that `segment.len != 0`.
        pub fn append(pmc: *Self, segment: []const T) bool {
            assert(segment.len != 0);
            if (pmc.current_index == pmc.candidates.len) return false;

            const prefix = pmc.candidates[pmc.current_index][0..pmc.query_len];
            while (pmc.current_index != pmc.candidates.len) : (pmc.current_index += 1) {
                const candidate_tag: []const T = pmc.candidates[pmc.current_index];
                if (!std.mem.startsWith(T, candidate_tag, prefix)) {
                    pmc.current_index = pmc.candidates.len;
                    return false;
                }
                const remaining = candidate_tag[prefix.len..];
                if (remaining.len < segment.len) continue;
                if (!std.mem.startsWith(T, remaining, segment)) continue;
                pmc.query_len += segment.len;
                return true;
            }

            pmc.current_index = pmc.candidates.len;
            return false;
        }

        /// Asserts that `segment.len != 0`.
        /// Returns the result for if the caller was to `append` the
        /// given `segment`, without actually appending it.
        pub inline fn appendCheck(self: Self, segment: []const T) bool {
            var copy = self;
            return copy.append(segment);
        }
    };
}

fn testProgressiveSliceMatch(comptime T: type, candidates: []const []const T) !void {
    const sorted: []const []const T = blk: {
        const is_sorted = std.sort.isSorted([]const T, candidates, {}, struct {
            fn lessThan(_: void, lhs: []const T, rhs: []const T) bool {
                return std.mem.lessThan(T, lhs, rhs);
            }
        }.lessThan);
        if (is_sorted) break :blk candidates;

        const sorted = try std.testing.allocator.dupe([]const T, candidates);
        errdefer std.testing.allocator.free(sorted);
        const Ctx = struct {
            candidates: [][]const T,
            pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
                return std.mem.lessThan(T, ctx.candidates[a], ctx.candidates[b]);
            }
            pub fn swap(ctx: @This(), a: usize, b: usize) void {
                std.mem.swap([]const T, &ctx.candidates[a], &ctx.candidates[b]);
            }
        };
        std.sort.insertionContext(0, sorted.len, Ctx{ .candidates = sorted });
        break :blk sorted;
    };
    defer if (sorted.ptr != candidates.ptr) {
        std.testing.allocator.free(sorted);
    };

    var pmc = try progressiveSliceMatch(T, sorted);
    for (sorted) |candidate| {
        pmc.clear();
        try std.testing.expectEqualSlices(T, &.{}, try testing.expectNonNull(pmc.getMatchedSubstring()));
        try std.testing.expectEqual(null, pmc.getClosestCandidate());
        try std.testing.expectEqual(null, pmc.getMatch());

        try std.testing.expect(pmc.append(candidate));
        try std.testing.expectEqualSlices(T, candidate, try testing.expectNonNull(pmc.getMatchedSubstring()));
        try std.testing.expectEqual(candidate, pmc.getClosestCandidate());
        try std.testing.expectEqual(candidate, pmc.getMatch());

        pmc.clear();
        try std.testing.expect(pmc.append(pmc.candidates[pmc.candidates.len - 1]));
        try std.testing.expect(!pmc.append("-no-match"));
        try std.testing.expectEqual(null, pmc.getMatchedSubstring());
        try std.testing.expectEqual(null, pmc.getClosestCandidate());
        try std.testing.expectEqual(null, pmc.getMatch());

        for (1..candidate.len + 1) |max_seg_size| {
            pmc.clear();
            var segment_iter = std.mem.window(T, candidate, max_seg_size, max_seg_size);
            while (segment_iter.next()) |segment| {
                try std.testing.expectStringStartsWith(candidate, try testing.expectNonNull(pmc.getMatchedSubstring()));
                try std.testing.expect(pmc.append(segment));
                try std.testing.expect(pmc.getClosestCandidate() != null);
            }
            try std.testing.expectEqualSlices(T, candidate, try testing.expectNonNull(pmc.getMatchedSubstring()));
            try std.testing.expectEqual(candidate, pmc.getClosestCandidate());
            try std.testing.expectEqual(candidate, pmc.getMatch());
        }
    }
}

test progressiveSliceMatch {
    var pmc = try progressiveSliceMatch(u8, &.{
        "bar",
        "baz",
        "buzz",
        "fizz",
        "foo",
    });

    try std.testing.expectEqual(null, pmc.getMatch());
    try std.testing.expectEqual(null, pmc.getClosestCandidate());
    try std.testing.expectEqualStrings("", try testing.expectNonNull(pmc.getMatchedSubstring()));

    try std.testing.expect(pmc.append("ba"));
    try std.testing.expectEqualStrings("ba", try testing.expectNonNull(pmc.getMatchedSubstring()));
    _ = try testing.expectNonNull(pmc.getClosestCandidate());

    try std.testing.expect(pmc.append("z"));
    try std.testing.expectEqualStrings("baz", try testing.expectNonNull(pmc.getMatchedSubstring()));
    _ = try testing.expectNonNull(pmc.getClosestCandidate());

    try std.testing.expectEqual("baz", pmc.getMatch());

    try std.testing.expect(!pmc.append("z"));
    try std.testing.expectEqual(null, pmc.getMatch());
    try std.testing.expectEqual(null, pmc.getMatchedSubstring());
    try std.testing.expectEqual(null, pmc.getClosestCandidate());

    pmc.clear();
    try std.testing.expect(pmc.append("f"));
    try std.testing.expectEqualStrings("f", try testing.expectNonNull(pmc.getMatchedSubstring()));
    try std.testing.expect(!pmc.append("a"));

    pmc.clear();
    try std.testing.expect(!pmc.append("a"));
    try std.testing.expectEqual(null, pmc.getMatchedSubstring());
    try std.testing.expect(!pmc.append("a"));

    pmc.clear();
    try std.testing.expect(pmc.append("fizz"));
    try std.testing.expectEqualStrings("fizz", try testing.expectNonNull(pmc.getMatch()));

    try testProgressiveSliceMatch(u8, &.{ "adlk", "bnae", "aaeg", "cvxz", "fadsfea", "vafa", "zvcxer", "ep", "afeap", "lapqqokf" });
    try testProgressiveSliceMatch(u8, &.{ "a", "ab", "abcd", "bcdefg", "bcde", "xy", "xz", "xyz", "xyzzz" });
}

pub fn ProgressiveStringToEnum(comptime E: type) type {
    const info = @typeInfo(E).Enum;
    return struct {
        current_index: usize = 0,
        query_len: usize = 0,
        const Self = @This();

        pub inline fn getMatch(pse: Self) ?E {
            const candidate = pse.getClosestCandidate() orelse return null;
            const str = @tagName(candidate);
            if (str.len > pse.query_len) return null;
            assert(str.len == pse.query_len);
            return candidate;
        }

        pub inline fn getMatchedSubslice(pse: Self) ?[]const u8 {
            if (pse.current_index == sorted.tags.len) return null;
            const candidate = @tagName(sorted.tags[pse.current_index]);
            return candidate[0..pse.query_len];
        }

        pub inline fn getClosestCandidate(pse: Self) ?E {
            if (pse.current_index == sorted.tags.len) return null;
            const closest = sorted.tags[pse.current_index];
            if (pse.query_len == 0 and @tagName(closest).len != 0) return null;
            return closest;
        }

        /// asserts that `segment.len != 0`
        pub fn append(pse: *Self, segment: []const u8) bool {
            assert(segment.len != 0);
            if (pse.current_index == sorted.tags.len) return false;

            const prefix = @tagName(sorted.tags[pse.current_index])[0..pse.query_len];
            while (pse.current_index != sorted.tags.len) : (pse.current_index += 1) {
                const candidate_tag: E = sorted.tags[pse.current_index];
                if (!std.mem.startsWith(u8, @tagName(candidate_tag), prefix)) {
                    pse.current_index = sorted.tags.len;
                    return false;
                }
                const remaining = @tagName(candidate_tag)[prefix.len..];
                if (remaining.len < segment.len) continue;
                if (!std.mem.startsWith(u8, remaining, segment)) continue;
                pse.query_len += segment.len;
                return true;
            }

            pse.current_index = sorted.tags.len;
            return false;
        }

        /// Asserts that `segment.len != 0`.
        /// Returns the result for if the caller was to `append` the
        /// given `segment`, without actually appending it.
        pub inline fn appendCheck(self: Self, segment: []const u8) bool {
            var copy = self;
            return copy.append(segment);
        }

        const sorted = blk: {
            var tags: [info.fields.len]E = undefined;
            @setEvalBranchQuota(tags.len);
            for (&tags, info.fields) |*tag, field| {
                tag.* = @field(E, field.name);
            }

            // sort
            @setEvalBranchQuota(@min(std.math.maxInt(u32), tags.len * tags.len));
            for (tags[0 .. tags.len - 1], 0..) |*tag_a, i| {
                for (tags[i + 1 ..]) |*tag_b| {
                    if (!std.mem.lessThan(u8, @tagName(tag_a.*), @tagName(tag_b.*))) {
                        std.mem.swap(E, tag_a, tag_b);
                    }
                }
            }

            break :blk .{
                .tags = tags,
            };
        };
    };
}

fn testProgressiveStringToEnum(comptime E: type) !void {
    const Pse = ProgressiveStringToEnum(E);
    var pse = Pse{};
    for (comptime std.enums.values(E)) |value| {
        const field_name = @tagName(value);

        pse = .{};
        try std.testing.expectEqualStrings("", try testing.expectNonNull(pse.getMatchedSubslice()));
        try std.testing.expectEqual(null, pse.getClosestCandidate());
        try std.testing.expectEqual(null, pse.getMatch());

        try std.testing.expect(pse.append(field_name));
        try std.testing.expectEqualStrings(field_name, try testing.expectNonNull(pse.getMatchedSubslice()));
        try std.testing.expectEqual(value, pse.getClosestCandidate());
        try std.testing.expectEqual(value, pse.getMatch());

        try std.testing.expect(!pse.append(comptime non_matching: {
            const lexicographic_biggest = Pse.sorted.tags[Pse.sorted.tags.len - 1];
            break :non_matching @tagName(lexicographic_biggest) ++ "-no-match";
        }));
        try std.testing.expectEqual(null, pse.getMatchedSubslice());
        try std.testing.expectEqual(null, pse.getClosestCandidate());
        try std.testing.expectEqual(null, pse.getMatch());

        for (1..field_name.len + 1) |max_seg_size| {
            pse = .{};
            var segment_iter = std.mem.window(u8, field_name, max_seg_size, max_seg_size);
            while (segment_iter.next()) |segment| {
                try std.testing.expectStringStartsWith(field_name, try testing.expectNonNull(pse.getMatchedSubslice()));
                try std.testing.expect(pse.append(segment));
                try std.testing.expect(pse.getClosestCandidate() != null);
            }
            try std.testing.expectEqualStrings(field_name, try testing.expectNonNull(pse.getMatchedSubslice()));
            try std.testing.expectEqual(value, pse.getClosestCandidate());
            try std.testing.expectEqual(value, pse.getMatch());
        }
    }
}

test ProgressiveStringToEnum {
    const E = enum {
        foo,
        bar,
        baz,
        fizz,
        buzz,
    };
    var pste = ProgressiveStringToEnum(E){};
    try std.testing.expectEqual(null, pste.getMatch());
    try std.testing.expectEqual(null, pste.getClosestCandidate());
    try std.testing.expectEqualStrings("", try testing.expectNonNull(pste.getMatchedSubslice()));

    try std.testing.expect(pste.append("ba"));
    try std.testing.expectEqualStrings("ba", try testing.expectNonNull(pste.getMatchedSubslice()));
    _ = try testing.expectNonNull(pste.getClosestCandidate());

    try std.testing.expect(pste.append("z"));
    try std.testing.expectEqualStrings("baz", try testing.expectNonNull(pste.getMatchedSubslice()));
    _ = try testing.expectNonNull(pste.getClosestCandidate());

    try std.testing.expectEqual(.baz, pste.getMatch());

    try std.testing.expect(!pste.append("z"));
    try std.testing.expectEqual(null, pste.getMatch());
    try std.testing.expectEqual(null, pste.getMatchedSubslice());
    try std.testing.expectEqual(null, pste.getClosestCandidate());

    try testProgressiveStringToEnum(enum { adlk, bnae, aaeg, cvxz, fadsfea, vafa, zvcxer, ep, afeap, lapqqokf });
    try testProgressiveStringToEnum(enum { a, ab, abcd, bcdefg, bcde, xy, xz, xyz, xyzzz });
}

const testing = struct {
    fn expectNonNull(optional: anytype) !@typeInfo(@TypeOf(optional)).Optional.child {
        if (optional) |value| return value;
        return error.TestExpectedNonNullValue;
    }
};
