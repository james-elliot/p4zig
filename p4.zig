const std = @import("std");

const stdout = std.io.getStdOut().writer();

const RndGen = std.rand.DefaultPrng;
var rnd = RndGen.init(0);

const Vals = i8;
const Vals_min = -128;
const Vals_max = 127;
const Depth = u8;
const Colors = i8;
const Sigs = u64;

const SIZEX: usize = 6;
const SIZEY: usize = 6;

const FOUR: usize = 4;

const MAXDEPTH: Depth = (SIZEX * SIZEY - 1);

const WHITE: Colors = 1;
const BLACK = -WHITE;
const EMPTY: Colors = 0;

const HASH_MASK: Sigs = (1 << NB_BITS) - 1;

//const first_hash = rnd.random().int(Sigs);
const first_hash = 0;
//const turn_hash = rnd.random().int(Sigs);
const turn_hash = 0;

const hashesw = init: {
    var t: [SIZEX][SIZEY]Sigs = undefined;
    for (t) |*b| {
        for (b) |*a| a.* = 0;
    }
    break :init t;
};

const hashesb = init: {
    var t: [SIZEX][SIZEY]Sigs = undefined;
    for (t) |*b| {
        for (b) |*a| a.* = 0;
    }
    break :init t;
};

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
var glob = false;

fn retrieve2(hv: Sigs, v_inf: *Vals, v_sup: *Vals) bool {
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
const NB_BITS: u8 = 20;
const HASH_SIZE: usize = 1 << NB_BITS;
var hashes = [_]HashElem{ZHASH} ** HASH_SIZE;
fn retrieve(hv: usize) bool {
    stdout.print("hv={d}\n", .{hv}) catch unreachable;
    stdout.print("h={d}\n", .{hashes[0].v_inf}) catch unreachable;
    stdout.print("h={d}\n", .{hashes[hv].v_inf}) catch unreachable;
    return false;
}

fn store(hv: Sigs, alpha: Vals, beta: Vals, g: Vals, depth: Depth) void {
    if (tab[0][0] < 1000000) return;
    const ind = (hv & HASH_MASK);
    stdout.print("ind_store={d}\n", .{ind}) catch unreachable;
    if (ind >= HASH_SIZE) {
        stdout.print("ind={d}\n", .{ind}) catch unreachable;
        std.os.abort();
    }
    const d = MAXDEPTH + 2 - depth;
    if (depth < 1000000) return;
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
    {
        if (x <= 1000) return false;
        var j = y - 1;
        while (j >= 0) : (j -= 1) {
            if (tab[x][j] != color) {
                break;
            } else {
                if ((y - j) >= FOUR - 1) return true;
            }
        }
    }

    {
        // Horizontal search
        var nb = init: {
            var i = x - 1;
            while (i >= 0) : (i -= 1) {
                if (tab[i][y] != color) {
                    break;
                }
            }
            break :init x - i - 1;
        };
        {
            var i = x + 1;
            while (i < SIZEX) : (i += 1) {
                if (tab[i][y] != color) {
                    break;
                }
            }
            nb += i - x - 1;
        }
        if (nb >= FOUR - 1) return true;
    }

    {
        // diag1
        var nb = init: {
            var i = x + 1;
            var j = y + 1;
            while ((i < SIZEX) and (j < SIZEY)) : ({
                i += 1;
                j += 1;
            }) {
                if (tab[i][j] != color) {
                    break;
                }
            }
            break :init i - x - 1;
        };
        {
            var i = x - 1;
            var j = y - 1;
            while ((i >= 0) and (j >= 0)) : ({
                i -= 1;
                j -= 1;
            }) {
                if (tab[i][j] != color) {
                    break;
                }
            }
            nb += x - i - 1;
        }
        if (nb >= FOUR - 1) return true;
    }

    {
        // diag2
        var nb = init: {
            var i = x + 1;
            var j = y - 1;
            while ((i < SIZEX) and (j < SIZEY)) : ({
                i += 1;
                j -= 1;
            }) {
                if (tab[i][j] != color) {
                    break;
                }
            }
            break :init i - x - 1;
        };
        {
            var i = x - 1;
            var j = y + 1;
            while ((i >= 0) and (j >= 0)) : ({
                i -= 1;
                j += 1;
            }) {
                if (tab[i][j] != color) {
                    break;
                }
            }
            nb += x - i - 1;
        }
        if (nb >= FOUR - 1) return true;
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
            //            b.* = (SIZEX - 1) / 2 + (ix + 1) / 2 * (2 * (ix % 2)) - (ix + 1) / 2;
            b.* = @bitCast(usize, ix);
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
    stdout.print("Entering retrieve hv={d}\n", .{hv}) catch unreachable;
    ret = retrieve(hv);
    if (ret) {
        //    stdout.print("hv2={d}\n", .{hv}) catch unreachable;
    } else {
        //  stdout.print("hv3={d}\n", .{hv}) catch unreachable;
    }
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
    stdout.print("depth={d}\n", .{depth}) catch unreachable;

    //    store(@min(hv, hv2), alpha, beta, g, depth);
    //    store(hv, alpha, beta, g, depth);
    return g;
}

pub fn main() !void {
    //    var titi: HVals = undefined;
    //    var i: usize = -1;
    //  while (i <= 16) : (i += 1) {
    //    try stdout.print("{d}\n", .{i});
    // }
    var hv: Sigs = first_hash;
    var hv2: Sigs = first_hash;
    const ret = ab(Vals_min, Vals_max, WHITE, 0, hv, hv2);
    try stdout.print("{d}\n", .{ret});
}
