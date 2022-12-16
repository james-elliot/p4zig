const std = @import("std");

const SIZEX: usize = 6;
const SIZEY: usize = 6;
const NB_BITS: u8 = 26;

const stdout = std.io.getStdOut().writer();

//const RndGen = std.rand.DefaultPrng;
//var rnd = RndGen.init(0);

var rnd_curr: u64 = 20170705;
fn my_rnd() u32 {
    const a: u64 = 742938285;
    rnd_curr = (rnd_curr * a) % ((1 << 31) - 1);
    return @truncate(u32, rnd_curr);
}

fn my_rnd64() u64 {
    const a: u64 = my_rnd();
    const b: u64 = my_rnd();
    const c: u64 = my_rnd();
    return (a + (b << 31) + (c << 62));
}

const Vals = i8;
const Vals_min = -128;
const Vals_max = 127;
const Depth = u8;
const Colors = i8;
const Sigs = u64;

const FOUR: usize = 4;

const MAXDEPTH: Depth = (SIZEX * SIZEY - 1);

const WHITE: Colors = 1;
const BLACK = -WHITE;
const EMPTY: Colors = 0;

const HASH_MASK: Sigs = (1 << NB_BITS) - 1;

//const first_hash = rnd.random().int(Sigs);
var first_hash: Sigs = undefined;
var hashesw: [SIZEX][SIZEY]Sigs = undefined;
var hashesb: [SIZEX][SIZEY]Sigs = undefined;

const HashElem = struct {
    sig: Sigs,
    v_inf: Vals,
    v_sup: Vals,
    d: Depth,
};

var tab = init: {
    var t: [SIZEX][SIZEY]Colors = undefined;
    for (t) |*b| {
        for (b) |*a| a.* = 0;
    }
    break :init t;
};

var first = [_]usize{0} ** SIZEX;

fn retrieve(hv: Sigs, v_inf: *Vals, v_sup: *Vals) bool {
    const ind: usize = (hv & HASH_MASK);
    if (hashes[ind].sig == hv) {
        v_inf.* = hashes[ind].v_inf;
        v_sup.* = hashes[ind].v_sup;
        return true;
    } else {
        return false;
    }
}

const ZHASH = HashElem{
    .sig = 0,
    .v_inf = 0,
    .v_sup = 0,
    .d = 0,
};

const HASH_SIZE: usize = 1 << NB_BITS;
var hashes = [_]HashElem{ZHASH} ** HASH_SIZE;

fn store(hv: Sigs, alpha: Vals, beta: Vals, g: Vals, depth: Depth) void {
    const ind = (hv & HASH_MASK);
    const d = MAXDEPTH + 2 - depth;
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
}

fn eval(x: usize, y: usize, color: Colors) bool {
    // For y search only below
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

fn ab(
    alpha: Vals,
    beta: Vals,
    color: Colors,
    depth: Depth,
    hv: Sigs,
    hv2: Sigs,
) Vals {
    const indexes = comptime init: {
        var t: [SIZEX]usize = undefined;
        for (t) |*b, ix| {
            b.* = (SIZEX - 1) / 2 + (ix + 1) / 2 * (2 * (ix % 2)) - (ix + 1) / 2;
        }
        break :init t;
    };
    //    stdout.print("indexes={d}\n", .{indexes}) catch unreachable;
    var a = alpha;
    var b = beta;
    var v_inf: Vals = 0;
    var v_sup: Vals = 0;
    //  stdout.print("hv={d}\n", .{hv}) catch unreachable;
    var ret = false;
    ret = retrieve(@min(hv, hv2), &v_inf, &v_sup);
    if (ret) {
        if (v_inf == v_sup) return v_inf;
        if (v_inf >= b) return v_inf;
        if (v_sup <= a) return v_sup;
        a = @max(a, v_inf);
        b = @min(b, v_sup);
    }
    for (indexes) |x| {
        const y = first[x];
        if ((y != SIZEY) and (eval(x, y, color))) return color;
    }
    if (depth == MAXDEPTH) return 0;
    var g: Vals = if (color == WHITE) Vals_min else Vals_max;
    var nhv: Sigs = undefined;
    var nhv2: Sigs = undefined;

    for (indexes) |x| {
        const y = first[x];
        if (y < SIZEY) {
            tab[x][y] = color;
            first[x] += 1;
            if (color == WHITE) {
                nhv = hv ^ hashesw[x][y];
                nhv2 = hv2 ^ hashesw[SIZEX - 1 - x][y];
            } else {
                nhv = hv ^ hashesb[x][y];
                nhv2 = hv2 ^ hashesb[SIZEX - 1 - x][y];
            }
            const v = ab(a, b, -color, depth + 1, nhv, nhv2);
            first[x] -= 1;
            tab[x][y] = EMPTY;
            if (color == WHITE) {
                if (v > g) {
                    g = v;
                    if (g > a) {
                        a = g;
                        if (a >= b) {
                            break;
                        }
                    }
                }
            } else {
                if (v < g) {
                    g = v;
                    if (g < b) {
                        b = g;
                        if (a >= b) {
                            break;
                        }
                    }
                }
            }
        }
    }
    store(@min(hv, hv2), alpha, beta, g, depth);
    return g;
}

pub fn main() !void {
    for (hashesw) |*b| {
        for (b) |*a| a.* = my_rnd64();
    }
    for (hashesb) |*b| {
        for (b) |*a| a.* = my_rnd64();
    }
    first_hash = my_rnd64();
    var hv: Sigs = first_hash;
    var hv2: Sigs = first_hash;
    const ret = ab(Vals_min, Vals_max, WHITE, 0, hv, hv2);
    try stdout.print("{d}\n", .{ret});
}
