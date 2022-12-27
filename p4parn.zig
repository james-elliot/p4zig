const std = @import("std");
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const context = std.Thread.SpawnConfig{ .stack_size = 1024 * 1024 };
// 27 bits use 2GB
const NB_BITS: u8 = 29;
const SIZEX: usize = 6;
const SIZEY: usize = 7;
// 6x7 NB_BITS=29 255s
// 7x6 NB_BITS=29 582s

fn eval(tab: *[SIZEX][SIZEY]Colors, x: usize, y: usize, color: Colors) bool {
    // For vertical search, search only below
    if (y >= FOUR - 1) {
        var nb: u32 = 1;
        var j = y - 1;
        while (true) {
            if (tab[x][j] == color) nb += 1 else break;
            if (j == 0) break;
            j -= 1;
        }
        if (nb >= FOUR) return true;
    }
    {
        // Horizontal search
        var nb: u32 = 1;
        if (x > 0) {
            var i = x - 1;
            while (true) {
                if (tab[i][y] == color) nb += 1 else break;
                if (i == 0) break;
                i -= 1;
            }
        }
        if (x < SIZEX - 1) {
            var i = x + 1;
            while (true) {
                if (tab[i][y] == color) nb += 1 else break;
                if (i == SIZEX - 1) break;
                i += 1;
            }
        }
        if (nb >= FOUR) return true;
    }
    {
        // diag1
        var nb: u32 = 1;
        if ((x < SIZEX - 1) and (y < SIZEY - 1)) {
            var i = x + 1;
            var j = y + 1;
            while (true) {
                if (tab[i][j] == color) nb += 1 else break;
                if ((i == SIZEX - 1) or (j == SIZEY - 1)) break;
                i += 1;
                j += 1;
            }
        }
        if ((x > 0) and (y > 0)) {
            var i = x - 1;
            var j = y - 1;
            while (true) {
                if (tab[i][j] == color) nb += 1 else break;
                if ((i == 0) or (j == 0)) break;
                i -= 1;
                j -= 1;
            }
        }
        if (nb >= FOUR) return true;
    }
    {
        // diag2
        var nb: u32 = 1;
        if ((x < SIZEX - 1) and (y > 0)) {
            var i = x + 1;
            var j = y - 1;
            while (true) {
                if (tab[i][j] == color) nb += 1 else break;
                if ((i == SIZEX - 1) or (j == 0)) break;
                i += 1;
                j -= 1;
            }
        }
        if ((x > 0) and (y < SIZEY - 1)) {
            var i = x - 1;
            var j = y + 1;
            while (true) {
                if (tab[i][j] == color) nb += 1 else break;
                if ((i == 0) or (j == SIZEY - 1)) break;
                i -= 1;
                j += 1;
            }
        }
        if (nb >= FOUR) return true;
    }
    return false;
}

const Vals = i8;
const Vals_min: Vals = -120;
const Vals_max: Vals = 120;
const Val_working: Vals = 127;
const Val_finished: Vals = 126;
const Depth = u8;
const Colors = i8;
const Sigs = u64;

const FOUR: usize = 4;
const MAXDEPTH: Depth = SIZEX * SIZEY - 1;
const WHITE: Colors = 1;
const BLACK = -WHITE;
const EMPTY: Colors = 0;
const HASH_SIZE: usize = 1 << NB_BITS;
const HASH_MASK: Sigs = HASH_SIZE - 1;

const HashElem = packed struct { sig: Sigs, v_inf: Vals, v_sup: Vals, d: Depth, m: u8 };
const ZHASH = HashElem{ .sig = 0, .v_inf = Vals_min, .v_sup = Vals_max, .d = 0, .m = 0 };

var runnings: u8 = 0;
const RUNMAX = 4;
const PARDEPTH = 5;

var first_hash: Sigs = undefined;
var hashesw: [SIZEX][SIZEY]Sigs = undefined;
var hashesb: [SIZEX][SIZEY]Sigs = undefined;
var hashes: []HashElem = undefined;

fn retrieve(hv: Sigs, v_inf: *Vals, v_sup: *Vals) bool {
    const ind: usize = hv & HASH_MASK;
    while (@cmpxchgWeak(u8, &hashes[ind].m, 0, 1, .SeqCst, .SeqCst) != null) {}
    if (hashes[ind].sig == hv) {
        v_inf.* = hashes[ind].v_inf;
        v_sup.* = hashes[ind].v_sup;
        @atomicStore(u8, &hashes[ind].m, 0, .SeqCst);
        //        return false;
        return true;
    } else {
        @atomicStore(u8, &hashes[ind].m, 0, .SeqCst);
        return false;
    }
}

fn store(hv: Sigs, alpha: Vals, beta: Vals, g: Vals, depth: Depth) void {
    const ind = hv & HASH_MASK;
    const d = MAXDEPTH + 2 - depth;
    while (@cmpxchgWeak(u8, &hashes[ind].m, 0, 1, .SeqCst, .SeqCst) != null) {}
    if (hashes[ind].d <= d) {
        if (hashes[ind].sig != hv) {
            hashes[ind].d = d;
            hashes[ind].v_inf = Vals_min;
            hashes[ind].v_sup = Vals_max;
            hashes[ind].sig = hv;
        }
        if ((g > alpha) and (g < beta)) {
            hashes[ind].v_inf = g;
            hashes[ind].v_sup = g;
        } else if (g <= alpha) {
            hashes[ind].v_sup = @min(g, hashes[ind].v_sup);
        } else if (g >= beta) {
            hashes[ind].v_inf = @max(g, hashes[ind].v_inf);
        }
    }
    @atomicStore(u8, &hashes[ind].m, 0, .SeqCst);
}

var prt: u8 = 0;
fn ab(first: *[SIZEX]usize, tab: *[SIZEX][SIZEY]Colors, alpha: Vals, beta: Vals, color: Colors, depth: Depth, hv: Sigs, hv2: Sigs, v: *Vals, hts: *bool, idx: u64, idy: u64) void {
    const indexes = comptime init: {
        var t: [SIZEX]usize = undefined;
        for (t) |*b, ix| b.* = (SIZEX - 1) / 2 + (ix + 1) / 2 * (2 * (ix % 2)) - (ix + 1) / 2;
        break :init t;
    };
    //    while (@cmpxchgWeak(u8, &prt, 0, 1, .SeqCst, .SeqCst) != null) {}
    //    stderr.print("enter={} {}\n", .{ idx, idy }) catch unreachable;
    //    @atomicStore(u8, &prt, 0, .SeqCst);
    var a = alpha;
    var b = beta;
    var v_inf: Vals = undefined;
    var v_sup: Vals = undefined;
    if (retrieve(@min(hv, hv2), &v_inf, &v_sup)) {
        if (v_inf == v_sup) {
            @atomicStore(Vals, v, v_inf, .SeqCst);
            return;
        }
        if (v_inf >= b) {
            @atomicStore(Vals, v, v_inf, .SeqCst);
            return;
        }
        if (v_sup <= a) {
            @atomicStore(Vals, v, v_sup, .SeqCst);
            return;
        }
        a = @max(a, v_inf);
        b = @min(b, v_sup);
    }
    for (indexes) |x| {
        const y = first[x];
        if ((y != SIZEY) and (eval(tab, x, y, color))) {
            @atomicStore(Vals, v, 1, .SeqCst);
            return;
        }
    }
    if (depth == MAXDEPTH) {
        @atomicStore(Vals, v, 0, .SeqCst);
        return;
    }
    var g: Vals = Vals_min;
    var nhv: Sigs = undefined;
    var nhv2: Sigs = undefined;
    var my_hts = false;
    var vv = [_]Vals{Val_working} ** SIZEX;
    var tha = [_]?std.Thread{null} ** SIZEX;
    var toto = [_]?*[SIZEX]usize{null} ** SIZEX;
    var titi = [_]?*[SIZEX][SIZEY]Colors{null} ** SIZEX;

    for (indexes) |x| {
        if (a >= b) {
            break;
        }

        if (@atomicLoad(bool, hts, .SeqCst)) {
            //            stderr.print("enter={} {}\n", .{ idx, idy }) catch unreachable;
            @atomicStore(bool, &my_hts, true, .SeqCst);
            for (indexes) |i| {
                if (tha[i]) |t| {
                    t.join();
                    _ = @atomicRmw(u8, &runnings, .Sub, 1, .SeqCst);
                    if (toto[x]) |m| {
                        defer allocator.destroy(m);
                    }
                    if (titi[x]) |m| {
                        defer allocator.destroy(m);
                    }
                }
            }
            @atomicStore(Vals, v, Val_finished, .SeqCst);
            return;
        }

        const y = first[x];
        if (y < SIZEY) {
            first[x] += 1;
            if (color == WHITE) {
                tab[x][y] = WHITE;
                nhv = hv ^ hashesw[x][y];
                nhv2 = hv2 ^ hashesw[SIZEX - 1 - x][y];
            } else {
                tab[x][y] = BLACK;
                nhv = hv ^ hashesb[x][y];
                nhv2 = hv2 ^ hashesb[SIZEX - 1 - x][y];
            }

            if ((@atomicLoad(u8, &runnings, .SeqCst) < RUNMAX) and (depth < PARDEPTH)) {
                while (@cmpxchgWeak(u8, &prt, 0, 1, .SeqCst, .SeqCst) != null) {}
                stderr.print("start={} {} {}\n", .{ depth, 10 * idx + x + 1, 10 * idy + y + 1 }) catch unreachable;
                @atomicStore(u8, &prt, 0, .SeqCst);
                _ = @atomicRmw(u8, &runnings, .Add, 1, .SeqCst);
                var nfirst = allocator.create([SIZEX]usize) catch unreachable;
                toto[x] = nfirst;
                for (first) |t, i| {
                    nfirst[i] = t;
                }
                var ntab = allocator.create([SIZEX][SIZEY]Colors) catch unreachable;
                titi[x] = ntab;
                for (tab.*) |t, i| {
                    for (t) |tt, j| {
                        ntab[i][j] = tt;
                    }
                }
                tha[x] = std.Thread.spawn(context, ab, .{ nfirst, ntab, -b, -a, -color, depth + 1, nhv, nhv2, &vv[x], &my_hts, 10 * idx + x + 1, 10 * idy + y + 1 }) catch unreachable;
            } else {
                ab(first, tab, -b, -a, -color, depth + 1, nhv, nhv2, &vv[x], &my_hts, 10 * idx + x + 1, 10 * idy + y + 1);
                g = @max(-vv[x], g);
                a = @max(a, g);
            }
            first[x] -= 1;
            tab[x][y] = EMPTY;
        }
    }
    var active = true;
    while (active) {
        active = false;
        for (indexes) |x| {
            if (tha[x]) |t| {
                // If a>=b stop everything right now
                if (a >= b) {
                    @atomicStore(bool, &my_hts, true, .SeqCst);
                    for (indexes) |i| {
                        if (tha[i]) |tt| {
                            tt.join();
                            tha[i] = null;
                            _ = @atomicRmw(u8, &runnings, .Sub, 1, .SeqCst);
                            if (toto[i]) |m| {
                                defer allocator.destroy(m);
                            }
                            if (titi[i]) |m| {
                                defer allocator.destroy(m);
                            }
                        }
                    }
                    active = false;
                    break;
                }

                var v0 = @atomicLoad(Vals, &vv[x], .SeqCst);
                if (v0 != Val_working) {
                    if (v0 != Val_finished) {
                        g = @max(-v0, g);
                        a = @max(a, g);
                    }
                    t.join();
                    _ = @atomicRmw(u8, &runnings, .Sub, 1, .SeqCst);
                    tha[x] = null;
                    if (toto[x]) |m| {
                        defer allocator.destroy(m);
                    }
                    if (titi[x]) |m| {
                        defer allocator.destroy(m);
                    }
                } else {
                    //std.Thread.yield() catch unreachable;
                    std.time.sleep(1_000_000);
                    active = true;
                }
            }
        }
    }
    store(@min(hv, hv2), alpha, beta, g, depth);
    //    while (@cmpxchgWeak(u8, &prt, 0, 1, .SeqCst, .SeqCst) != null) {}
    //    stderr.print("exit={} {} ret={}\n", .{ idx, idy, g }) catch unreachable;
    //    @atomicStore(u8, &prt, 0, .SeqCst);
    @atomicStore(Vals, v, g, .SeqCst);
    return;
}

pub fn main() !void {
    var first = [_]usize{0} ** SIZEX;
    //var first = allocator.alloc(usize, SIZEX) catch unreachable;
    var tab = [_][SIZEY]Colors{[_]Colors{EMPTY} ** SIZEY} ** SIZEX;
    const allocator2 = std.heap.page_allocator;
    const RndGen = std.rand.DefaultPrng;
    hashes = try allocator2.alloc(HashElem, HASH_SIZE);
    defer allocator2.free(hashes);
    for (hashes) |*a| a.* = ZHASH;
    var rnd = RndGen.init(0);
    for (hashesw) |*b| {
        for (b) |*a| a.* = rnd.random().int(Sigs);
    }
    for (hashesb) |*b| {
        for (b) |*a| a.* = rnd.random().int(Sigs);
    }
    first_hash = rnd.random().int(Sigs);
    var t = std.time.milliTimestamp();
    var ret: Vals = Val_working;
    var hts = false;
    ab(&first, &tab, Vals_min, Vals_max, WHITE, 0, first_hash, first_hash, &ret, &hts, 0, 0);
    t = std.time.milliTimestamp() - t;
    try stderr.print("time={d}\n", .{t});
    try stderr.print("ret={} runnings={}\n", .{ ret, runnings });
}

//const Inner = struct { a: u32, b: bool };
//var toto = [_][20]Inner{[_]Inner{.{ .a = 1, .b = true }} ** 20} ** 10;

