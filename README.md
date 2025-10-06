# Zig-std

Goal: not use the system library `zstd` but build a standalone library that wraps the C library for learning.

The library is in "src/root.izg". We produce:

1. a stateless API
2. a stateful API with a context
3. streaming capability

## ZSTD documentation

- documentation link:

<https://facebook.github.io/zstd/doc/api_manual_latest.html#Chapter4>

## Build static archive of `zstd`

Build a static object `lib_zstd.a` with:

```sh
make
```
