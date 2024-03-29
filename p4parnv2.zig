const std = @import("std");
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const gpa_alloc = gpa.allocator();
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const context = std.Thread.SpawnConfig{ .stack_size = 1024 * 1024 };
// 27 bits use 2GB
const NB_BITS: u8 = 32;
const SIZEX: usize = 7;
const SIZEY: usize = 6;
const RUNMAX = 8;
const PARDEPTH = 2;
const DEBUG = true;
// SIZEX=4 SIZEY=5 NB_BITS=32 RUNMAX=8 ret=0 time=0.005s
// SIZEX=4 SIZEY=6 NB_BITS=32 RUNMAX=8 ret=0 time=0.028s
// SIZEX=4 SIZEY=7 NB_BITS=32 RUNMAX=8 ret=0 time=0.094s
// SIZEX=4 SIZEY=8 NB_BITS=32 RUNMAX=8 ret=0 time=1.155s
// SIZEX=4 SIZEY=9 NB_BITS=32 RUNMAX=8 ret=0 time=3.255s
// SIZEX=4 SIZEY=10 NB_BITS=32 RUNMAX=8 ret=0 time=35.343s
// SIZEX=4 SIZEY=11 NB_BITS=32 RUNMAX=8 ret=0 time=96.898s
// SIZEX=4 SIZEY=12 NB_BITS=32 RUNMAX=8 ret=0 time=1750.152s
// SIZEX=4 SIZEY=12 NB_BITS=32 RUNMAX=8 PARDEPTH=4 ret=0 time=753.285s
// SIZEX=5 SIZEY=4 NB_BITS=32 RUNMAX=8 ret=0 time=0.007s
// SIZEX=5 SIZEY=5 NB_BITS=32 RUNMAX=8 ret=0 time=0.071s
// SIZEX=5 SIZEY=6 NB_BITS=32 RUNMAX=8 ret=0 time=0.299s
// SIZEX=5 SIZEY=7 NB_BITS=32 RUNMAX=8 ret=0 time=3.751s
// SIZEX=5 SIZEY=8 NB_BITS=32 RUNMAX=8 ret=0 time=19.158s
// SIZEX=5 SIZEY=9   NB_BITS=32 RUNMAX=8 ret=0 time=193.117s
// SIZEX=6 SIZEY=4 NB_BITS=32 RUNMAX=8 ret=-1 time=0.05s
// SIZEX=6 SIZEY=5 NB_BITS=32 RUNMAX=8 ret=0 time=0.54s
// SIZEX=6 SIZEY=6 NB_BITS=32 RUNMAX=8 ret=-1 time=10.013s
// SIZEX=6 SIZEY=7 NB_BITS=32 RUNMAX=8 ret=1 time=86.996s
// SIZEX=6 SIZEY=8 NB_BITS=32 RUNMAX=8 ret=-1 time=4001.369s
// SIZEX=7 SIZEY=4 NB_BITS=32 RUNMAX=8 ret=0 time=0.46s
// SIZEX=7 SIZEY=5 NB_BITS=32 RUNMAX=8 ret=0 time=7.393s
// SIZEX=7 SIZEY=6 NB_BITS=32 RUNMAX=8 ret=1 time=134.317s
// SIZEX=7 SIZEY=6 NB_BITS=32 RUNMAX=8 PARDEPTH=1 ret=1 time=111.768s
// SIZEX=7 SIZEY=6 NB_BITS=32 RUNMAX=8 PARDEPTH=2 ret=1 time=113.972s
// SIZEX=7 SIZEY=6 NB_BITS=32 RUNMAX=8 PARDEPTH=3 ret=1 time=132.344s
// SIZEX=7 SIZEY=6 NB_BITS=32 RUNMAX=8 PARDEPTH=4 ret=1 time=117.132s
// SIZEX=7 SIZEY=7 NB_BITS=32 RUNMAX=8 ret=0 time=27006.757s
// SIZEX=8 SIZEY=3 NB_BITS=32 RUNMAX=8 ret=0 time=0.157s
// SIZEX=8 SIZEY=4 NB_BITS=32 RUNMAX=8 ret=-1 time=5.996s
// SIZEX=8 SIZEY=5 NB_BITS=32 RUNMAX=8 ret=1 time=103.798s
// SIZEX=8 SIZEY=6 NB_BITS=32 RUNMAX=8 ret=-1 time=645387.705s
// SIZEX=9 SIZEY=2 NB_BITS=32 RUNMAX=8 ret=0 time=0.01s
// SIZEX=9 SIZEY=3 NB_BITS=32 RUNMAX=8 ret=0 time=2.493s
// SIZEX=9 SIZEY=4 NB_BITS=32 RUNMAX=8 ret=-1 time=85.732s
// SIZEX=9 SIZEY=5 NB_BITS=32 RUNMAX=8 ret=1 time=2815.818s
// SIZEX=9 SIZEY=5 NB_BITS=32 RUNMAX=8 PARDEPTH=4 ret=1 time=1696.559s
// SIZEX=10 SIZEY=3 NB_BITS=32 RUNMAX=8 ret=0 time=11.922s
// SIZEX=10 SIZEY=4 NB_BITS=32 RUNMAX=8 ret=-1 time=6023.398s
// SIZEX=11 SIZEY=3 NB_BITS=32 RUNMAX=8 ret=0 time=496.535s

var prt: u8 = 0;
fn myprint(comptime format: []const u8, args: anytype) void {
    if (DEBUG) {
        while (@cmpxchgWeak(u8, &prt, 0, 1, .SeqCst, .SeqCst) != null) {}
        stderr.print(format, args) catch unreachable;
        @atomicStore(u8, &prt, 0, .SeqCst);
    }
}

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
const Val_half: Vals = 126;
const Val_finished: Vals = 125;
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
        myprint("starting={}\n", .{runnings});
        @atomicStore(u8, &runnings_m, 0, .SeqCst);
        return true;
    }
    @atomicStore(u8, &runnings_m, 0, .SeqCst);
    return false;
}
fn dec_run() void {
    while (@cmpxchgWeak(u8, &runnings_m, 0, 1, .SeqCst, .SeqCst) != null) {}
    myprint("stopping={}\n", .{runnings});
    _ = @atomicRmw(u8, &runnings, .Sub, 1, .SeqCst);
    @atomicStore(u8, &runnings_m, 0, .SeqCst);
}

const indexes = init: {
    var t: [SIZEX]usize = undefined;
    for (&t, 0..) |*b, ix| b.* = (SIZEX - 1) / 2 + (ix + 1) / 2 * (2 * (ix % 2)) - (ix + 1) / 2;
    break :init t;
};

const Status = enum { Stopped, Free, Running };

fn ab(first: *[SIZEX]usize, tab: *[SIZEX][SIZEY]Colors, alpha: *Vals, beta: *Vals, color: Colors, depth: Depth, hv: Sigs, hv2: Sigs, hts: *bool, v: *Vals, idx: usize) void {
    var a = -alpha.*;
    var b = -beta.*;
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
    var status = [_]Status{Status.Stopped} ** SIZEX;
    var ix: usize = 0;
    var free: bool = true;
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
    while (true) {
        b = @min(b, -beta.*);
        if ((ix == SIZEX) and (free)) {
            @atomicStore(Vals, v, Val_half, .SeqCst);
        }
        if (((ix == SIZEX) and (nb_runs == 0)) or (a >= b) or (@atomicLoad(bool, hts, .SeqCst))) {
            @atomicStore(bool, &my_hts, true, .SeqCst);
            for (indexes) |x| {
                if (thrs[x]) |t| {
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
                store(@min(hv, hv2), -alpha.*, -beta.*, g, depth);
                @atomicStore(Vals, v, g, .SeqCst);
            }
            return;
        }
        while ((ix < SIZEX) and (first[indexes[ix]] == SIZEY)) {
            ix += 1;
        }
        if ((ix < SIZEX) and (first[indexes[ix]] < SIZEY) and free) {
            var x = indexes[ix];
            var y = first[x];
            ix += 1;
            runs[nb_runs] = x;
            nb_runs += 1;
            var nfirst = gpa_alloc.create([SIZEX]usize) catch unreachable;
            firsts[x] = nfirst;
            for (first, 0..) |t, i| {
                nfirst[i] = t;
            }
            var ntab = gpa_alloc.create([SIZEX][SIZEY]Colors) catch unreachable;
            tabs[x] = ntab;
            for (tab.*, 0..) |t, i| {
                for (t, 0..) |tt, j| {
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
            myprint("depth={}\n", .{depth});
            if (depth < PARDEPTH)
                thrs[x] = std.Thread.spawn(context, ab, .{ nfirst, ntab, &b, &a, -color, depth + 1, nhv, nhv2, &my_hts, &vv[x], idx * 10 + x + 1 }) catch unreachable
            else
                thrs[x] = std.Thread.spawn(context, abd, .{ nfirst, ntab, &b, &a, -color, depth + 1, nhv, nhv2, &my_hts, &vv[x], idx * 10 + x + 1 }) catch unreachable;
            status[x] = Status.Running;
            free = false;
        }
        var i: usize = 0;
        var incr: bool = true;
        while (i < nb_runs) {
            incr = true;
            var x = runs[i];
            if (vv[x] != Val_working) {
                if (vv[x] == Val_half) {
                    if (status[x] == Status.Running) {
                        status[x] = Status.Free;
                        free = true;
                    }
                } else {
                    nb_runs -= 1;
                    runs[i] = runs[nb_runs];
                    incr = false;
                    if (status[x] == Status.Running) {
                        free = true;
                    }
                    status[x] = Status.Stopped;
                    if (thrs[x]) |t| {
                        t.join();
                        thrs[x] = null;
                    }
                    if (vv[x] != Val_finished) {
                        g = @max(-vv[x], g);
                        a = @max(a, g);
                        myprint("ab g={} a={} b={}\n", .{ g, a, b });
                    }
                }
            }
            if (incr) i += 1;
        }
        std.time.sleep(100_000);
    }
}

fn abd(first: *[SIZEX]usize, tab: *[SIZEX][SIZEY]Colors, alpha: *Vals, beta: *Vals, color: Colors, depth: Depth, hv: Sigs, hv2: Sigs, hts: *bool, v: *Vals, idx: usize) void {
    myprint("enter abd={}\n", .{idx});
    var a = -alpha.*;
    var b = -beta.*;
    var v_inf: Vals = undefined;
    var v_sup: Vals = undefined;
    if (retrieve(@min(hv, hv2), &v_inf, &v_sup)) {
        if (v_inf == v_sup) {
            @atomicStore(Vals, v, v_inf, .SeqCst);
            myprint("leave abd={} v={}\n", .{ idx, v.* });
            return;
        }
        if (v_inf >= b) {
            @atomicStore(Vals, v, v_inf, .SeqCst);
            myprint("leave abd={} v={}\n", .{ idx, v.* });
            return;
        }
        if (v_sup <= a) {
            @atomicStore(Vals, v, v_sup, .SeqCst);
            myprint("leave abd={} v={}\n", .{ idx, v.* });
            return;
        }
        a = @max(a, v_inf);
        b = @min(b, v_sup);
    }
    for (indexes) |x| {
        const y = first[x];
        if ((y != SIZEY) and (eval(tab, x, y, color))) {
            @atomicStore(Vals, v, 1, .SeqCst);
            myprint("leave abd={} v={}\n", .{ idx, v.* });
            return;
        }
    }
    if (depth == MAXDEPTH) {
        @atomicStore(Vals, v, 0, .SeqCst);
        myprint("leave abd={} v={}\n", .{ idx, v.* });
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
        b = @min(b, -beta.*);
        if ((ix == SIZEX) and (nb_runs != 0)) {
            @atomicStore(Vals, v, Val_half, .SeqCst);
        }
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
                store(@min(hv, hv2), -alpha.*, -beta.*, g, depth);
                @atomicStore(Vals, v, g, .SeqCst);
            }
            myprint("leave abd={} v={}\n", .{ idx, v.* });
            return;
        }
        while ((ix < SIZEX) and (first[indexes[ix]] == SIZEY)) {
            ix += 1;
        }
        if ((ix < SIZEX) and (first[indexes[ix]] < SIZEY) and inc_run()) {
            var x = indexes[ix];
            var y = first[x];
            ix += 1;
            runs[nb_runs] = x;
            nb_runs += 1;
            var nfirst = gpa_alloc.create([SIZEX]usize) catch unreachable;
            firsts[x] = nfirst;
            for (first, 0..) |t, i| {
                nfirst[i] = t;
            }
            var ntab = gpa_alloc.create([SIZEX][SIZEY]Colors) catch unreachable;
            tabs[x] = ntab;
            for (tab.*, 0..) |t, i| {
                for (t, 0..) |tt, j| {
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
            thrs[x] = std.Thread.spawn(context, abs, .{ nfirst, ntab, &b, &a, -color, depth + 1, nhv, nhv2, &my_hts, &vv[x], idx * 10 + x + 1 }) catch unreachable;
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
                    myprint("update abd g={} a={} b={} idx={}\n", .{ g, a, b, idx });
                }
            }
        }
        std.time.sleep(100_000);
    }
}

fn abs(first: *[SIZEX]usize, tab: *[SIZEX][SIZEY]Colors, alpha: *Vals, beta: *Vals, color: Colors, depth: Depth, hv: Sigs, hv2: Sigs, hts: *bool, ret: *Vals, idx: usize) void {
    myprint("enter abs={}\n", .{idx});
    if (@atomicLoad(bool, hts, .SeqCst)) {
        ret.* = Val_finished;
        return;
    }
    var a = -alpha.*;
    var b = -beta.*;
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
            myprint("searching idx={}\n", .{idx * 10 + x + 1});
            const v = abs2(first, tab, -b, -a, -color, depth + 1, nhv, nhv2, hts);
            myprint("solved idx={} v={}\n", .{ idx * 10 + x + 1, v });
            first[x] -= 1;
            tab[x][y] = EMPTY;
            if (v == Val_finished) {
                ret.* = v;
                return;
            }
            g = @max(-v, g);
            a = @max(a, g);
            b = @min(b, -beta.*);
            if (a >= b) {
                break;
            }
        }
    }
    store(@min(hv, hv2), -alpha.*, -beta.*, g, depth);
    ret.* = g;
    myprint("leave abs={}\n", .{idx});
    return;
}

fn abs2(first: *[SIZEX]usize, tab: *[SIZEX][SIZEY]Colors, alpha: Vals, beta: Vals, color: Colors, depth: Depth, hv: Sigs, hv2: Sigs, hts: *bool) Vals {
    if (@atomicLoad(bool, hts, .SeqCst)) {
        return Val_finished;
    }
    var a = alpha;
    var b = beta;
    var v_inf: Vals = undefined;
    var v_sup: Vals = undefined;
    if (retrieve(@min(hv, hv2), &v_inf, &v_sup)) {
        if (v_inf == v_sup) {
            return v_inf;
        }
        if (v_inf >= b) {
            return v_inf;
        }
        if (v_sup <= a) {
            return v_sup;
        }
        a = @max(a, v_inf);
        b = @min(b, v_sup);
    }
    for (indexes) |x| {
        const y = first[x];
        if ((y != SIZEY) and (eval(tab, x, y, color))) {
            return 1;
        }
    }
    if (depth == MAXDEPTH) {
        return 0;
    }
    var g: Vals = Vals_min;
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
            const v = abs2(first, tab, -b, -a, -color, depth + 1, nhv, nhv2, hts);
            first[x] -= 1;
            tab[x][y] = EMPTY;
            if (v == Val_finished) {
                return v;
            }
            g = @max(-v, g);
            a = @max(a, g);
            if (a >= b) {
                break;
            }
        }
    }
    store(@min(hv, hv2), alpha, beta, g, depth);
    return g;
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
    for (&hashesw) |*b| {
        for (b) |*a| a.* = rnd.random().int(Sigs);
    }
    for (&hashesb) |*b| {
        for (b) |*a| a.* = rnd.random().int(Sigs);
    }
    first_hash = rnd.random().int(Sigs);
    var t = std.time.milliTimestamp();
    var ret: Vals = Val_working;
    var hts = false;
    var alpha: Vals = 1;
    var beta: Vals = -1;
    ab(&first, &tab, &alpha, &beta, WHITE, 0, first_hash, first_hash, &hts, &ret, 0);
    t = std.time.milliTimestamp() - t;
    var t2: f64 = @intToFloat(f64, t) / 1000.0;
    try stderr.print("SIZEX={} SIZEY={} NB_BITS={} RUNMAX={} PARDEPTH={} ret={} time={d}s\n", .{ SIZEX, SIZEY, NB_BITS, RUNMAX, PARDEPTH, ret, t2 });
}

//const Inner = struct { a: u32, b: bool };
//var toto = [_][20]Inner{[_]Inner{.{ .a = 1, .b = true }} ** 20} ** 10;

