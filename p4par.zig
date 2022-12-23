const std = @import("std");
const stdout = std.io.getStdOut().writer();

var p: u8 = 0;
fn f1(a: u32, tp: *u64) void {
    var i: u64 = 0;
    while (i < 100_000_000) {
        while (@cmpxchgWeak(u8, &p, 0, 1, .SeqCst, .SeqCst) != null) {}
        tp.* += a;
        @atomicStore(u8, &p, 0, .SeqCst);
        i += 1;
    }
}

fn f1b(a: u32, tp: *u64) void {
    var i: u64 = 0;
    while (i < 100_000_000) {
        while (@cmpxchgWeak(u8, &p, 0, 1, .SeqCst, .Acquire) != null) {}
        tp.* += a;
        @atomicStore(u8, &p, 0, .Release);
        i += 1;
    }
}

var m: std.Thread.Mutex = std.Thread.Mutex{};
fn f2(a: u32, tp: *u64) void {
    var i: u64 = 0;
    while (i < 100_000_000) {
        std.Thread.Mutex.lock(&m);
        tp.* += a;
        std.Thread.Mutex.unlock(&m);
        i += 1;
    }
}

fn f3(a: u32, tp: *u64) void {
    var i: u64 = 0;
    while (i < 100_000_000) {
        tp.* += a;
        i += 1;
    }
}

fn f4(a: u32, tp: *u64) void {
    var i: u64 = 0;
    var tmp: u64 = 0;
    while (i < 100_000_000) {
        tmp += a;
        i += 1;
    }
    tp.* += tmp;
}

pub fn main() !void {
    var tp1: u64 = undefined;
    var tp2: u64 = undefined;
    var ti: i64 = undefined;
    var te: i64 = undefined;
    var t1: std.Thread = undefined;
    var t2: std.Thread = undefined;
    const v = std.Thread.SpawnConfig{ .stack_size = 32768 };
    //Works 500ms
    tp1 = 0;
    tp2 = 0;
    ti = std.time.milliTimestamp();
    f3(1, &tp1);
    f3(2, &tp1);
    te = std.time.milliTimestamp();
    try stdout.print("{} {}\n", .{ tp1 + tp2, te - ti });

    //Works slower 800ms
    tp1 = 0;
    tp2 = 0;
    ti = std.time.milliTimestamp();
    t1 = try std.Thread.spawn(v, f3, .{ 2, &tp1 });
    t2 = try std.Thread.spawn(v, f3, .{ 1, &tp2 });
    t1.join();
    t2.join();
    te = std.time.milliTimestamp();
    try stdout.print("{} {}\n", .{ tp1 + tp2, te - ti });

    //Fails miserably with an incorrect result 800ms
    tp1 = 0;
    tp2 = 0;
    ti = std.time.milliTimestamp();
    t1 = try std.Thread.spawn(v, f3, .{ 2, &tp1 });
    t2 = try std.Thread.spawn(v, f3, .{ 1, &tp1 });
    t1.join();
    t2.join();
    te = std.time.milliTimestamp();
    try stdout.print("{} {}\n", .{ tp1 + tp2, te - ti });

    //Works 500ms
    tp1 = 0;
    tp2 = 0;
    ti = std.time.milliTimestamp();
    f4(1, &tp1);
    f4(2, &tp1);
    te = std.time.milliTimestamp();
    try stdout.print("{} {}\n", .{ tp1 + tp2, te - ti });

    //Works faster 250ms, but might fail (even if unlikely ) if we had used the same variable in the two threads
    tp1 = 0;
    tp2 = 0;
    ti = std.time.milliTimestamp();
    t1 = try std.Thread.spawn(v, f4, .{ 2, &tp1 });
    t2 = try std.Thread.spawn(v, f4, .{ 1, &tp2 });
    t1.join();
    t2.join();
    te = std.time.milliTimestamp();
    try stdout.print("{} {}\n", .{ tp1 + tp2, te - ti });

    //Works much slower ~7500ms but timings are extremely variable
    tp1 = 0;
    tp2 = 0;
    ti = std.time.milliTimestamp();
    t1 = try std.Thread.spawn(v, f1b, .{ 2, &tp1 });
    t2 = try std.Thread.spawn(v, f1b, .{ 1, &tp1 });
    t1.join();
    t2.join();
    te = std.time.milliTimestamp();
    try stdout.print("{} {}\n", .{ tp1 + tp2, te - ti });

    //Works at the same speed ~7500ms. Same variability
    tp1 = 0;
    tp2 = 0;
    ti = std.time.milliTimestamp();
    t1 = try std.Thread.spawn(v, f1b, .{ 2, &tp1 });
    t2 = try std.Thread.spawn(v, f1b, .{ 1, &tp2 });
    t1.join();
    t2.join();
    te = std.time.milliTimestamp();
    try stdout.print("{} {}\n", .{ tp1 + tp2, te - ti });

    //Works even slower ~15000ms. Same variability
    tp1 = 0;
    tp2 = 0;
    ti = std.time.milliTimestamp();
    t1 = try std.Thread.spawn(v, f2, .{ 2, &tp1 });
    t2 = try std.Thread.spawn(v, f2, .{ 1, &tp1 });
    t1.join();
    t2.join();
    te = std.time.milliTimestamp();
    try stdout.print("{} {}\n", .{ tp1 + tp2, te - ti });

    //Works at the same speed ~15000ms. Same variability
    tp1 = 0;
    tp2 = 0;
    ti = std.time.milliTimestamp();
    t1 = try std.Thread.spawn(v, f2, .{ 2, &tp1 });
    t2 = try std.Thread.spawn(v, f2, .{ 1, &tp2 });
    t1.join();
    t2.join();
    te = std.time.milliTimestamp();
    try stdout.print("{} {}\n", .{ tp1 + tp2, te - ti });
}

//const Inner = struct { a: u32, b: bool };
//var toto = [_][20]Inner{[_]Inner{.{ .a = 1, .b = true }} ** 20} ** 10;

