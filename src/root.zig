//! Bindings and wrappers for Zstandard (zstd) compression library.
//!
//! Source: https://facebook.github.io/zstd/doc/api_manual_latest.html
//!
//! This module provides a stateless API, a stateful API, and a streaming API.
//!
//! The tests in main.zig provide examples of how to use the different APIs.
const std = @import("std");

///Most ZSTD_* functions returning a size_t value can be tested for error,
///using ZSTD_isError().
/// @@return 1 if error, 0 otherwise
extern "c" fn ZSTD_isError(code: usize) c_uint;
extern "c" fn ZSTD_getErrorName(code: usize) [*c]const u8;

extern "c" fn ZSTD_versionString() [*c]const u8;

pub fn version() []const u8 {
    return std.mem.span(ZSTD_versionString());
}

/// Compresses `src` content as a single zstd compressed frame into already allocated `dst`.
/// NOTE: Providing `dstCapacity >= ZSTD_compressBound(srcSize)` guarantees that zstd will have
/// enough space to successfully compress the data.
/// @return : compressed size written into `dst` (<= `dstCapacity),
/// or an error code if it fails (which can be tested using ZSTD_isError()).
extern "c" fn ZSTD_compress(
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: ?*const anyopaque,
    srcSize: usize,
    compressionLevel: c_int,
) usize;

/// `compressedSize` : must be the _exact_ size of some number of compressed and/or skippable frames.
/// Multiple compressed frames can be decompressed at once with this method.
/// The result will be the concatenation of all decompressed frames, back to back.
/// `dstCapacity` is an upper bound of originalSize to regenerate.
///  First frame's decompressed size can be extracted using ZSTD_getFrameContentSize().
///  If maximum upper bound isn't known, prefer using streaming mode to decompress data.
/// @return : the number of bytes decompressed into `dst` (<= `dstCapacity`),
/// or an errorCode if it fails (which can be tested using ZSTD_isError()).
extern "c" fn ZSTD_decompress(
    dst: ?*anyopaque,
    dstCapacity: usize,
    src: ?*const anyopaque,
    compressedSize: usize,
) usize;

/// maximum compressed size in worst case single-pass scenario.
/// When invoking `ZSTD_compress()`, or any other one-pass compression function,
/// it's recommended to provide @dstCapacity >= ZSTD_compressBound(srcSize)
/// as it eliminates one potential failure scenario,
/// aka not enough room in dst buffer to write the compressed frame.
/// Note : ZSTD_compressBound() itself can fail, if @srcSize >= ZSTD_MAX_INPUT_SIZE.
/// In which case, ZSTD_compressBound() will return an error code
/// which can be tested using ZSTD_isError().
extern "c" fn ZSTD_compressBound(srcSize: usize) usize;

// -----------------------------------
// === Stateless "Simple Core" API ===
// -----------------------------------

pub fn compress(allocator: std.mem.Allocator, input: []const u8, level: i32) ![]u8 {
    const bound = ZSTD_compressBound(input.len);
    if (ZSTD_isError(bound) == 1) {
        std.log.err("Zstd error: {s}", .{ZSTD_getErrorName(bound)});
        return error.ZstdError;
    }

    const out = try allocator.alloc(u8, bound);
    errdefer allocator.free(out);

    const written_size = ZSTD_compress(
        out.ptr,
        bound,
        input.ptr,
        input.len,
        level,
    );
    if (ZSTD_isError(written_size) == 1) {
        std.log.err("Zstd error: {s}", .{ZSTD_getErrorName(written_size)});
        return error.ZstdError;
    }
    return allocator.realloc(out, written_size);
}

pub fn decompress(allocator: std.mem.Allocator, input: []const u8, output_size: usize) ![]u8 {
    const out = try allocator.alloc(u8, output_size);
    errdefer allocator.free(out);
    const written = ZSTD_decompress(
        out.ptr,
        output_size,
        input.ptr,
        input.len,
    );
    if (ZSTD_isError(written) == 1) {
        std.log.err("Zstd error: {s}", .{ZSTD_getErrorName(written)});
        return error.ZstdError;
    }
    return allocator.realloc(out, written);
}

// ---------------------------------------
// === Stateful "Explicit Context" API ===
// ---------------------------------------

pub const ZSTD_CCtx = extern struct {};
pub const ZSTD_DCtx = extern struct {};
// pub const ZSTD_CCtx = extern struct {};

const ZSTD_cParameter = enum(i16) {
    ZSTD_c_compressionLevel = 100,
    ZSTD_c_windowLog = 101,
    ZSTD_c_hashLog = 102,
    ZSTD_c_chainLog = 103,
    ZSTD_c_searchLog = 104,
    ZSTD_c_minMatch = 105,
    ZSTD_c_targetLength = 106,
    ZSTD_c_strategy = 107,
    ZSTD_c_targetCBlockSize = 130,
    ZSTD_c_enableLongDistanceMatching = 160,
    ZSTD_c_ldmHashLog = 161,
    ZSTD_c_ldmMinMatch = 162,
    ZSTD_c_ldmBucketSizeLog = 163,
    ZSTD_c_ldmHashRateLog = 164,
    ZSTD_c_contentSizeFlag = 200,
    ZSTD_c_checksumFlag = 201,
    ZSTD_c_dictIDFlag = 202,
    ZSTD_c_nbWorkers = 400,
    ZSTD_c_jobSize = 401,
    ZSTD_c_overlapLog = 402,
};

const ZSTD_strategy = enum(i16) {
    ZSTD_fast = 1,
    ZSTD_dfast = 2,
    ZSTD_greedy = 3,
    ZSTD_lazy = 4,
    ZSTD_lazy2 = 5,
    ZSTD_btlazy2 = 6,
    ZSTD_btopt = 7,
    ZSTD_btultra = 8,
    ZSTD_btultra2 = 9,
};

const ZSTD_bounds = struct {
    @"error": usize,
    lowerBound: i16,
    upperBound: i16,
};

const ZSTD_ResetDirective = enum(i8) {
    ZSTD_reset_session_only = 0,
    ZSTD_reset_parameters = 1,
    ZSTD_reset_session_and_parameters = 2,
};

extern "c" fn ZSTD_cParam_getBounds(param: ZSTD_cParameter) ZSTD_bounds;
/// Set one compression parameter, selected by enum ZSTD_cParameter.
/// @return : an error code (which can be tested using ZSTD_isError()).
extern "c" fn ZSTD_CCtx_setParameter(cctx: *ZSTD_CCtx, param: ZSTD_cParameter, value: i16) usize;

/// @return : 0, or an error code, which can be tested with ZSTD_isError()
extern "c" fn ZSTD_CCtx_reset(cctx: *ZSTD_CCtx, reset: ZSTD_ResetDirective) usize;

/// @return : 0, or an error code, which can be tested with ZSTD_isError()
extern "c" fn ZSTD_DCtx_reset(dctx: *ZSTD_DCtx, reset: ZSTD_ResetDirective) usize;

extern "c" fn ZSTD_createCCtx() ?*ZSTD_CCtx;
extern "c" fn ZSTD_freeCCtx(cctx: *ZSTD_CCtx) usize;
extern "c" fn ZSTD_compressCCtx(
    cctx: *ZSTD_CCtx,
    dst: [*]u8,
    dstCapacity: usize,
    src: [*]const u8,
    srcSize: usize,
    compressionLevel: i16,
) usize;
extern "c" fn ZSTD_compress2(
    cctx: *ZSTD_CCtx,
    dst: [*]u8,
    dstCapacity: usize,
    src: [*]const u8,
    srcSize: usize,
) usize;

extern "c" fn ZSTD_createDCtx() ?*ZSTD_DCtx;
extern "c" fn ZSTD_freeDCtx(dctx: *ZSTD_DCtx) usize;
extern "c" fn ZSTD_decompressDCtx(
    dctx: *ZSTD_DCtx,
    dst: [*]u8,
    dstCapacity: usize,
    src: [*]const u8,
    srcSize: usize,
) usize;

extern "c" fn ZSTD_getFrameContentSize(src: *anyopaque, srcSize: usize) usize;

/// Initialize a compression context with specified compression level.
pub fn init_compressor(compressionLevel: i16) !*ZSTD_CCtx {
    const cctx = ZSTD_createCCtx();
    if (cctx) |ctx| {
        const ctx_set_result = ZSTD_CCtx_setParameter(
            ctx,
            ZSTD_cParameter.ZSTD_c_compressionLevel,
            compressionLevel,
        );
        if (ZSTD_isError(ctx_set_result) == 1) {
            std.log.err("Zstd error: {s}", .{ZSTD_getErrorName(ctx_set_result)});
            return error.ZstdError;
        }
        std.debug.print("Set compression level result: {d}\n", .{ctx_set_result});

        return ctx;
    } else {
        return error.ZstdError;
    }
}

/// Free the compression context, returning the size of memory freed.
pub fn free_compressor(ctx: *ZSTD_CCtx) usize {
    return ZSTD_freeCCtx(ctx);
}

/// Reset the compression context to be reused, keeping allocated memory.
///
/// This is more efficient than freeing and creating a new context.
///
/// Uses this when you want to compress many independent frames with the same context.
pub fn reset_compressor_session(ctx: *ZSTD_CCtx) !void {
    const reset_resut = ZSTD_CCtx_reset(ctx, ZSTD_ResetDirective.ZSTD_reset_session_only);
    if (ZSTD_isError(reset_resut) == 1) {
        std.log.err("Zstd error: {s}", .{ZSTD_getErrorName(reset_resut)});
        return error.ZstdError;
    }
}

/// Compress input data using an existing compression context with specified compression level.
pub fn compress_with_ctx_with_level_override(
    allocator: std.mem.Allocator,
    ctx: *ZSTD_CCtx,
    input: []const u8,
    compressionLevel: i16,
) ![]u8 {
    const bound = ZSTD_compressBound(input.len);
    if (ZSTD_isError(bound) == 1) {
        std.log.err("Zstd error: {s}", .{ZSTD_getErrorName(bound)});
        return error.ZstdError;
    }

    const out = try allocator.alloc(u8, bound);
    errdefer allocator.free(out);

    const written_size = ZSTD_compressCCtx(
        ctx,
        out.ptr,
        bound,
        input.ptr,
        input.len,
        compressionLevel,
    );
    if (ZSTD_isError(written_size) == 1) {
        std.log.err("Zstd error: {s}", .{ZSTD_getErrorName(written_size)});
        return error.ZstdError;
    }
    return allocator.realloc(out, written_size);
}

/// Compress input data using an existing compression context with its preset compression level.
pub fn compress_with_ctx(
    allocator: std.mem.Allocator,
    ctx: *ZSTD_CCtx,
    input: []const u8,
) ![]u8 {
    const bound = ZSTD_compressBound(input.len);
    if (ZSTD_isError(bound) == 1) {
        std.log.err("Zstd error: {s}", .{ZSTD_getErrorName(bound)});
        return error.ZstdError;
    }

    const out = try allocator.alloc(u8, bound);
    errdefer allocator.free(out);

    const written_size = ZSTD_compress2(
        ctx,
        out.ptr,
        bound,
        input.ptr,
        input.len,
    );
    if (ZSTD_isError(written_size) == 1) {
        std.log.err("Zstd error: {s}", .{ZSTD_getErrorName(written_size)});
        return error.ZstdError;
    }
    return allocator.realloc(out, written_size);
}

/// Initialize a decompression context.
pub fn init_decompressor() !*ZSTD_DCtx {
    const dctx = ZSTD_createDCtx();
    if (dctx) |ctx| {
        return ctx;
        // No parameters to set for now
    }
    return error.ZstdError;
}

/// Free the decompression context, returning the size of memory freed.
pub fn free_decompressor(ctx: *ZSTD_DCtx) usize {
    return ZSTD_freeDCtx(ctx);
}

/// Reset the decompression context to be reused, keeping allocated memory.
pub fn reset_decompressor_session(ctx: *ZSTD_DCtx) !void {
    const reset_resut = ZSTD_DCtx_reset(ctx, ZSTD_ResetDirective.ZSTD_reset_session_only);
    if (ZSTD_isError(reset_resut) == 1) {
        std.log.err("Zstd error: {s}", .{ZSTD_getErrorName(reset_resut)});
        return error.ZstdError;
    }
}

/// Decompress input data using an existing decompression context.
pub fn decompress_with_ctx(
    allocator: std.mem.Allocator,
    ctx: *ZSTD_DCtx,
    input: []const u8,
    output_size: usize,
) ![]u8 {
    const out = try allocator.alloc(u8, output_size);
    errdefer allocator.free(out);

    const written = ZSTD_decompressDCtx(
        ctx,
        out.ptr,
        output_size,
        input.ptr,
        input.len,
    );
    if (ZSTD_isError(written) == 1) {
        std.log.err("Zstd error: {s}", .{ZSTD_getErrorName(written)});
        return error.ZstdError;
    }
    return allocator.realloc(out, written);
}

// Decompression context wrapper
const ZSTD_dParameter = enum(i16) {
    ZSTD_d_windowLogMax = 100,
    ZSTD_d_experimentalParam1 = 1000,
    ZSTD_d_experimentalParam2 = 1001,
    ZSTD_d_experimentalParam3 = 1002,
    ZSTD_d_experimentalParam4 = 1003,
    ZSTD_d_experimentalParam5 = 1004,
    ZSTD_d_experimentalParam6 = 1005,
};

/// Set one decompression parameter, selected by enum ZSTD_dParameter.
/// All parameters have valid bounds.
/// Bounds can be queried using ZSTD_dParam_getBounds().
/// @return : 0, or an error code (which can be tested using ZSTD_isError()).
extern "c" fn ZSTD_DCtx_setParameter(dtx: *ZSTD_DCtx, param: ZSTD_dParameter, value: i16) usize;

// -------------------------------
// === STREAMING ===
// -------------------------------

pub const ZSTD_CStream = extern struct {};
pub const ZSTD_DStream = extern struct {};

pub const ZSTD_inBuffer = struct {
    src: *const anyopaque, // start of input buffer
    size: usize, // size of input buffer
    pos: usize, // position where reading stopped. Will be updated. Necessarily 0 <= pos <= size
};

pub const ZSTD_outBuffer = struct {
    dst: *anyopaque, // start of output buffer
    size: usize, // size of output buffer
    pos: usize, // position where writing stopped. Will be updated. Necessarily 0 <= pos <= size
};

pub const ZSTD_EndDirective = enum(i32) {
    ZSTD_e_continue = 0, // collect more input / produce more output
    ZSTD_e_flush = 1, // immediately flush whatever data is available into a block (block will be incomplete)
    ZSTD_e_end = 2, // immediately flush whatever data is available into a block, then end the frame
};

extern "c" fn ZSTD_createCStream() ?*ZSTD_CStream;
extern "c" fn ZSTD_freeCStream(zcs: *ZSTD_CStream) usize;
extern "c" fn ZSTD_compressStream2(
    cctx: *ZSTD_CCtx,
    output: *ZSTD_outBuffer,
    input: *ZSTD_inBuffer,
    endOp: ZSTD_EndDirective,
) usize;

extern "c" fn ZSTD_createDStream() ?*ZSTD_DStream;
extern "c" fn ZSTD_freeDStream(zds: *ZSTD_DStream) usize;

/// @return : recommended first input size
extern "c" fn ZSTD_initDStream(dctx: *ZSTD_DCtx) usize;
extern "c" fn ZSTD_decompressStream(
    dctx: *ZSTD_DCtx,
    output: *ZSTD_outBuffer,
    input: *ZSTD_inBuffer,
) usize;

extern "c" fn ZSTD_CStreamInSize() usize;
extern "c" fn ZSTD_CStreamOutSize() usize;
extern "c" fn ZSTD_DStreamInSize() usize;
extern "c" fn ZSTD_DStreamOutSize() usize;

/// Get recommended input buffer size for compression streaming
pub fn getStreamInSize() usize {
    return ZSTD_CStreamInSize();
}

/// Get recommended output buffer size for compression streaming
pub fn getStreamOutSize() usize {
    return ZSTD_CStreamOutSize();
}

/// Get recommended input buffer size for decompression streaming
pub fn getDecompressStreamInSize() usize {
    return ZSTD_DStreamInSize();
}

/// Get recommended output buffer size for decompression streaming
pub fn getDecompressStreamOutSize() usize {
    return ZSTD_DStreamOutSize();
}

/// Streaming compression - compresses input chunk by chunk.
///
/// Caller must call repeatedly with chunks until all input is consumed
///
/// Returns number of bytes remaining to flush (0 when done)
pub fn compressStream(
    ctx: *ZSTD_CCtx,
    output: *ZSTD_outBuffer,
    input: *ZSTD_inBuffer,
    endOp: ZSTD_EndDirective,
) !usize {
    const result = ZSTD_compressStream2(ctx, output, input, endOp);
    if (ZSTD_isError(result) == 1) {
        std.log.err("Zstd compress stream error: {s}", .{ZSTD_getErrorName(result)});
        return error.ZstdError;
    }
    return result;
}

/// Streaming decompression - decompresses input chunk by chunk.
///
/// Returns hint for next input size (or 0 if frame complete)
pub fn decompressStream(
    ctx: *ZSTD_DCtx,
    output: *ZSTD_outBuffer,
    input: *ZSTD_inBuffer,
) !usize {
    const result = ZSTD_decompressStream(ctx, output, input);
    if (ZSTD_isError(result) == 1) {
        std.log.err("Zstd decompress stream error: {s}", .{ZSTD_getErrorName(result)});
        return error.ZstdError;
    }
    return result;
}
