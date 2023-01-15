# p4zig
P4 solver in Zig

A little bit faster than C, faster than Rust. However, still lot of bugs in the compiler... 
The parallel v2 version is extremely fast and solves the classical 7x6 in less than 2 minutes
on an 8 cores i9-9900K. There is still a bug which happens very unfrequently when using a PARDEPTH>=4 
with small sizes.
Compile with:
```
zig build-exe -O ReleaseFast p4parnv2.zig

