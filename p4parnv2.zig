const std = @import("std");
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const gpa_alloc = gpa.allocator();
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const context = std.Thread.SpawnConfig{ .stack_size = 65536 };
// 27 bits use 2GB
const NB_BITS: u8 = 28;
const SIZEX: usize = 6;
const SIZEY: usize = 6;
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

var runnings_m: u8 = 0;
var runnings: u8 = 0;
const RUNMAX = 8;
const PARDEPTH = 2;

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

fn inc_run() bool {
    while (@cmpxchgWeak(u8, &runnings_m, 0, 1, .SeqCst, .SeqCst) != null) {}
    if (@atomicLoad(u8, &runnings, .SeqCst) < RUNMAX) {
        _ = @atomicRmw(u8, &runnings, .Add, 1, .SeqCst);
        stderr.print("starting={}\n", .{runnings}) catch unreachable;
        @atomicStore(u8, &runnings_m, 0, .SeqCst);
        return true;
    }
    return false;
}
fn dec_run() void {
    while (@cmpxchgWeak(u8, &runnings_m, 0, 1, .SeqCst, .SeqCst) != null) {}
    stderr.print("stopping={}\n", .{runnings}) catch unreachable;
    _ = @atomicRmw(u8, &runnings, .Sub, 1, .SeqCst);
    @atomicStore(u8, &runnings_m, 0, .SeqCst);
}

var prt: u8 = 0;

const indexes = init: {
    var t: [SIZEX]usize = undefined;
    for (t) |*b, ix| b.* = (SIZEX - 1) / 2 + (ix + 1) / 2 * (2 * (ix % 2)) - (ix + 1) / 2;
    break :init t;
};

fn abd(
    first: *[SIZEX]usize,
    tab: *[SIZEX][SIZEY]Colors,
    alpha: Vals,
    beta: Vals,
    color: Colors,
    depth: Depth,
    hv: Sigs,
    hv2: Sigs,
    hts: *bool,
    v: *Vals,
) void {
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
    var thrs = [_]?std.Thread{null} ** SIZEX;
    var firsts = [_]?*[SIZEX]usize{null} ** SIZEX;
    var tabs = [_]?*[SIZEX][SIZEY]Colors{null} ** SIZEX;
    var nb_runs: usize = 0;
    var runs = [_]usize{0} ** SIZEX;
    var ix: usize = 0;
    while (true) {
        if (((ix == SIZEX) and (nb_runs == 0)) or (a >= b) or (@atomicLoad(bool, hts, .SeqCst))) {
            @atomicStore(bool, &my_hts, true, .SeqCst);
            for (indexes) |x| {
                if (thrs[x]) |t| {
                    dec_run();
                    t.join();
                }
                if (firsts[x]) |m| {
                    gpa_alloc.destroy(m);
                }
                if (tabs[x]) |m| {
                    gpa_alloc.destroy(m);
                }
            }
            if (hts.*) {
                @atomicStore(Vals, v, Val_finished, .SeqCst);
            } else {
                store(@min(hv, hv2), alpha, beta, g, depth);
                @atomicStore(Vals, v, g, .SeqCst);
            }
            return;
        }
        if ((ix < SIZEX) and (first[indexes[ix]] < SIZEY) and inc_run()) {
            var x = indexes[ix];
            var y = first[x];
            ix += 1;
            runs[nb_runs] = x;
            nb_runs += 1;
            var nfirst = gpa_alloc.create([SIZEX]usize) catch unreachable;
            firsts[x] = nfirst;
            for (first) |t, i| {
                nfirst[i] = t;
            }
            var ntab = gpa_alloc.create([SIZEX][SIZEY]Colors) catch unreachable;
            tabs[x] = ntab;
            for (tab.*) |t, i| {
                for (t) |tt, j| {
                    ntab[i][j] = tt;
                }
            }
            nfirst[x] += 1;
            if (color == WHITE) {
                ntab[x][y] = WHITE;
                nhv = hv ^ hashesw[x][y];
                nhv2 = hv2 ^ hashesw[SIZEX - 1 - x][y];
            } else {
                ntab[x][y] = BLACK;
                nhv = hv ^ hashesb[x][y];
                nhv2 = hv2 ^ hashesb[SIZEX - 1 - x][y];
            }
            thrs[x] = std.Thread.spawn(context, abs, .{ nfirst, ntab, -b, -a, -color, depth + 1, nhv, nhv2, &my_hts, &vv[x] }) catch unreachable;
        }
        var i: usize = 0;
        while (i < nb_runs) : (i += 1) {
            var x = runs[i];
            if (vv[x] != Val_working) {
                nb_runs -= 1;
                runs[i] = runs[nb_runs];
                dec_run();
                if (thrs[x]) |t| {
                    t.join();
                    thrs[x] = null;
                }
                if (vv[x] != Val_finished) {
                    g = @max(-vv[x], g);
                    a = @max(a, g);
                }
            }
        }
        std.time.sleep(100_000);
    }
}

fn abs(first: *[SIZEX]usize, tab: *[SIZEX][SIZEY]Colors, alpha: Vals, beta: Vals, color: Colors, depth: Depth, hv: Sigs, hv2: Sigs, hts: *bool, ret: *Vals) void {
    if (@atomicLoad(bool, hts, .SeqCst)) {
        ret.* = Val_finished;
        return;
    }
    var a = alpha;
    var b = beta;
    var v_inf: Vals = undefined;
    var v_sup: Vals = undefined;
    if (retrieve(@min(hv, hv2), &v_inf, &v_sup)) {
        if (v_inf == v_sup) {
            ret.* = v_inf;
            return;
        }
        if (v_inf >= b) {
            ret.* = v_inf;
            return;
        }
        if (v_sup <= a) {
            ret.* = v_sup;
            return;
        }
        a = @max(a, v_inf);
        b = @min(b, v_sup);
    }
    for (indexes) |x| {
        const y = first[x];
        if ((y != SIZEY) and (eval(tab, x, y, color))) {
            ret.* = 1;
            return;
        }
    }
    if (depth == MAXDEPTH) {
        ret.* = 0;
        return;
    }
    var g: Vals = Vals_min;
    var v: Vals = undefined;
    var nhv: Sigs = undefined;
    var nhv2: Sigs = undefined;
    for (indexes) |x| {
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
            abs(first, tab, -b, -a, -color, depth + 1, nhv, nhv2, hts, &v);
            first[x] -= 1;
            tab[x][y] = EMPTY;
            if (v == Val_finished) {
                ret.* = v;
                return;
            }
            g = @max(-v, g);
            a = @max(a, g);
            if (a >= b) {
                break;
            }
        }
    }
    store(@min(hv, hv2), alpha, beta, g, depth);
    ret.* = g;
    return;
}

pub fn main() !void {
    var first = [_]usize{0} ** SIZEX;
    var tab = [_][SIZEY]Colors{[_]Colors{EMPTY} ** SIZEY} ** SIZEX;
    const heap_alloc = std.heap.page_allocator;
    const RndGen = std.rand.DefaultPrng;
    hashes = try heap_alloc.alloc(HashElem, HASH_SIZE);
    defer heap_alloc.free(hashes);
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
    abd(&first, &tab, Vals_min, Vals_max, WHITE, 0, first_hash, first_hash, &hts, &ret);
    t = std.time.milliTimestamp() - t;
    try stderr.print("time={d}\n", .{t});
    try stderr.print("ret={} runnings={}\n", .{ ret, runnings });
}

//const Inner = struct { a: u32, b: bool };
//var toto = [_][20]Inner{[_]Inner{.{ .a = 1, .b = true }} ** 20} ** 10;

