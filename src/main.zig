const std = @import("std");
const z = @import("z_std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    // const allocator = gpa.allocator();

    const v = z.version();
    std.debug.print("Zstd version: {s}\n", .{v});
}

test "basic compress and decompress" {
    const allocator = std.testing.allocator;

    const cctx = try z.init_compressor(.{});
    defer _ = z.free_compressor(cctx);

    const dctx = try z.init_decompressor(.{});
    defer _ = z.free_decompressor(dctx);

    const input = "Hello, world!" ** 1000;
    const compressed_data = try z.compress(
        allocator,
        cctx,
        input,
    );
    defer allocator.free(compressed_data);
    std.debug.print(
        "data: {d} -> Compressed: {d}\n",
        .{ input.len, compressed_data.len },
    );

    const decompressed_data = try z.decompress(
        allocator,
        dctx,
        compressed_data,
    );
    defer allocator.free(decompressed_data);

    std.debug.print(
        "data: {d} -> compress: {d} -> decompress: {d}\n",
        .{ input.len, compressed_data.len, decompressed_data.len },
    );

    try std.testing.expectEqualSlices(
        u8,
        input,
        decompressed_data,
    );
}
test "context reuse with different data types" {
    const allocator = std.testing.allocator;

    const cctx = z.init_compressor(.{ .compression_level = 22 }) catch |err| {
        std.log.err("Failed to init compressor: {any}", .{err});
        return;
    };
    defer _ = z.free_compressor(cctx);

    const dctx = z.init_decompressor(.{}) catch |err| {
        std.log.err("Failed to init decompressor: {any}", .{err});
        return;
    };
    defer _ = z.free_decompressor(dctx);

    // 1) Text data
    const in = "Hello, world!" ** 1000;
    const compressed_data = try z.compress(
        allocator,
        cctx,
        in,
    );
    defer allocator.free(compressed_data);
    std.debug.print(
        "data: {d} -> Compressed: {d}\n",
        .{ in.len, compressed_data.len },
    );

    const decompressed_data = try z.decompress(
        allocator,
        dctx,
        compressed_data,
    );
    defer allocator.free(decompressed_data);

    std.debug.print(
        "data: {d} -> compress: {d} -> decompress: {d}\n",
        .{ in.len, compressed_data.len, decompressed_data.len },
    );

    try std.testing.expectEqualSlices(
        u8,
        in,
        decompressed_data,
    );

    // Reset contexts to be able to reuse them
    z.reset_compressor_session(cctx) catch |err| {
        std.log.err("Failed to reset compressor session: {any}", .{err});
        return;
    };
    try z.reset_decompressor_session(dctx);

    // 2) Image data
    const img = std.fs.cwd().openFile("src/tests/test.png", .{}) catch |err| {
        std.log.err("Failed to open test.png: {any}", .{err});
        return;
    };
    defer img.close();
    const stat = try img.stat();
    const img_data = try img.readToEndAlloc(
        allocator,
        stat.size,
    );
    defer allocator.free(img_data);
    const compressed_img = try z.compress(
        allocator,
        cctx,
        img_data,
    );
    defer allocator.free(compressed_img);

    const decompressed_img = try z.decompress(
        allocator,
        dctx,
        compressed_img,
    );
    defer allocator.free(decompressed_img);

    std.debug.print(
        "img: {d} -> compress: {d} -> decompress: {d}\n",
        .{ img_data.len, compressed_img.len, decompressed_img.len },
    );

    try std.testing.expectEqualSlices(
        u8,
        img_data,
        decompressed_img,
    );

    z.reset_compressor_session(cctx) catch |err| {
        std.log.err("Failed to reset compressor session: {any}", .{err});
        return;
    };
    try z.reset_decompressor_session(dctx);

    // 3) PDF data
    const pdf = std.fs.cwd().openFile("src/tests/test.pdf", .{}) catch |err| {
        std.log.err("Failed to open test.pdf: {any}", .{err});
        return;
    };
    defer pdf.close();
    const stat_pdf = try pdf.stat();
    const pdf_data = try pdf.readToEndAlloc(
        allocator,
        stat_pdf.size,
    );
    std.debug.print("PDF size: {d}\n", .{pdf_data.len});
    defer allocator.free(pdf_data);
    const compressed_pdf = try z.compress(
        allocator,
        cctx,
        pdf_data,
    );
    defer allocator.free(compressed_pdf);

    const decompressed_pdf = try z.decompress(
        allocator,
        dctx,
        compressed_pdf,
    );
    defer allocator.free(decompressed_pdf);

    std.debug.print(
        "pdf: {d} -> compress: {d} -> decompress: {d}\n",
        .{ pdf_data.len, compressed_pdf.len, decompressed_pdf.len },
    );
    try std.testing.expect(decompressed_pdf.len == pdf_data.len);
}

test "streaming compress and decompress file" {
    const allocator = std.testing.allocator;

    // Open img file
    {
        const file = std.fs.cwd().openFile("src/tests/test.png", .{}) catch |err| {
            std.log.err("Failed to open test.png: {any}", .{err});
            return;
        };
        defer file.close();

        const stat = try file.stat();
        const file_size = stat.size;

        // Create compression context
        const cctx = try z.init_compressor(.{});
        defer _ = z.free_compressor(cctx);

        // Prepare output buffer for compressed data
        const out_buffer_size = z.getStreamOutSize();
        const compressed_buffer = try allocator.alloc(
            u8,
            file_size + out_buffer_size,
        );
        defer allocator.free(compressed_buffer);
        var compressed_size: usize = 0;

        // Read and compress in chunks
        const chunk_size = z.getStreamInSize();
        std.debug.print("Chunk size: {d}\n", .{chunk_size});
        const read_buffer = try allocator.alloc(u8, chunk_size);
        defer allocator.free(read_buffer);

        var total_read: usize = 0;
        while (total_read < file_size) {
            const bytes_read = try file.read(read_buffer);
            std.debug.print("Chunk read {d} bytes\n", .{bytes_read});
            if (bytes_read == 0) break;
            total_read += bytes_read;

            var in_buf = z.ZSTD_inBuffer{
                .src = read_buffer.ptr,
                .size = bytes_read,
                .pos = 0,
            };

            const is_last_chunk = total_read >= file_size;
            const end_op = if (is_last_chunk) z.ZSTD_EndDirective.ZSTD_e_end else z.ZSTD_EndDirective.ZSTD_e_continue;

            // Compress this chunk
            while (in_buf.pos < in_buf.size or (is_last_chunk and end_op == .ZSTD_e_end)) {
                var out_buf = z.ZSTD_outBuffer{
                    .dst = compressed_buffer.ptr + compressed_size,
                    .size = compressed_buffer.len - compressed_size,
                    .pos = 0,
                };

                const remaining = try z.compressStream(cctx, &out_buf, &in_buf, end_op);
                compressed_size += out_buf.pos;

                if (is_last_chunk and remaining == 0) break;
            }
        }
        std.debug.print("Streaming: file {d} -> compressed {d}\n", .{ file_size, compressed_size });

        // Now decompress using streaming
        const dctx = try z.init_decompressor(.{});
        defer _ = z.free_decompressor(dctx);

        const decompressed_buffer = try allocator.alloc(u8, file_size);
        defer allocator.free(decompressed_buffer);
        var decompressed_size: usize = 0;

        var in_pos: usize = 0;
        const decompress_in_size = z.getDecompressStreamInSize();

        while (in_pos < compressed_size) {
            const chunk_to_read = @min(decompress_in_size, compressed_size - in_pos);

            var in_buf = z.ZSTD_inBuffer{
                .src = compressed_buffer.ptr + in_pos,
                .size = chunk_to_read,
                .pos = 0,
            };

            while (in_buf.pos < in_buf.size) {
                var out_buf = z.ZSTD_outBuffer{
                    .dst = decompressed_buffer.ptr + decompressed_size,
                    .size = decompressed_buffer.len - decompressed_size,
                    .pos = 0,
                };

                const hint = try z.decompressStream(dctx, &out_buf, &in_buf);
                decompressed_size += out_buf.pos;

                if (hint == 0) break;
            }

            in_pos += in_buf.pos;
        }

        std.debug.print("Streaming: decompressed {d} bytes\n", .{decompressed_size});
        try std.testing.expectEqual(file_size, decompressed_size);

        // Verify content matches original
        try file.seekTo(0);
        const original = try file.readToEndAlloc(allocator, file_size);
        defer allocator.free(original);
        try std.testing.expectEqualSlices(u8, original, decompressed_buffer[0..decompressed_size]);
    }
    {
        const file = std.fs.cwd().openFile("src/tests/test.pdf", .{}) catch |err| {
            std.log.err("Failed to open test.png: {any}", .{err});
            return;
        };
        defer file.close();

        const stat = try file.stat();
        const file_size = stat.size;

        // Create compression context
        const cctx = try z.init_compressor(.{});
        defer _ = z.free_compressor(cctx);

        // Prepare output buffer for compressed data
        const out_buffer_size = z.getStreamOutSize();
        const compressed_buffer = try allocator.alloc(
            u8,
            file_size + out_buffer_size,
        );
        defer allocator.free(compressed_buffer);
        var compressed_size: usize = 0;

        // Read and compress in chunks
        const chunk_size = z.getStreamInSize();
        std.debug.print("Chunk size: {d}\n", .{chunk_size});
        const read_buffer = try allocator.alloc(u8, chunk_size);
        defer allocator.free(read_buffer);

        var total_read: usize = 0;
        while (total_read < file_size) {
            const bytes_read = try file.read(read_buffer);
            std.debug.print("Chunk read {d} bytes\n", .{bytes_read});
            if (bytes_read == 0) break;
            total_read += bytes_read;

            var in_buf = z.ZSTD_inBuffer{
                .src = read_buffer.ptr,
                .size = bytes_read,
                .pos = 0,
            };

            const is_last_chunk = total_read >= file_size;
            const end_op = if (is_last_chunk) z.ZSTD_EndDirective.ZSTD_e_end else z.ZSTD_EndDirective.ZSTD_e_continue;

            // Compress this chunk
            while (in_buf.pos < in_buf.size or (is_last_chunk and end_op == .ZSTD_e_end)) {
                var out_buf = z.ZSTD_outBuffer{
                    .dst = compressed_buffer.ptr + compressed_size,
                    .size = compressed_buffer.len - compressed_size,
                    .pos = 0,
                };

                const remaining = try z.compressStream(cctx, &out_buf, &in_buf, end_op);
                compressed_size += out_buf.pos;

                if (is_last_chunk and remaining == 0) break;
            }
        }

        std.debug.print("Streaming: file {d} -> compressed {d}\n", .{ file_size, compressed_size });

        // Now decompress using streaming
        const dctx = try z.init_decompressor(.{});
        defer _ = z.free_decompressor(dctx);

        const decompressed_buffer = try allocator.alloc(u8, file_size);
        defer allocator.free(decompressed_buffer);
        var decompressed_size: usize = 0;

        var in_pos: usize = 0;
        const decompress_in_size = z.getDecompressStreamInSize();

        while (in_pos < compressed_size) {
            const chunk_to_read = @min(decompress_in_size, compressed_size - in_pos);

            var in_buf = z.ZSTD_inBuffer{
                .src = compressed_buffer.ptr + in_pos,
                .size = chunk_to_read,
                .pos = 0,
            };

            while (in_buf.pos < in_buf.size) {
                var out_buf = z.ZSTD_outBuffer{
                    .dst = decompressed_buffer.ptr + decompressed_size,
                    .size = decompressed_buffer.len - decompressed_size,
                    .pos = 0,
                };

                const hint = try z.decompressStream(dctx, &out_buf, &in_buf);
                decompressed_size += out_buf.pos;

                if (hint == 0) break;
            }

            in_pos += in_buf.pos;
        }

        std.debug.print("Streaming: decompressed {d} bytes\n", .{decompressed_size});
        try std.testing.expectEqual(file_size, decompressed_size);

        // Verify content matches original
        try file.seekTo(0);
        const original = try file.readToEndAlloc(allocator, file_size);
        defer allocator.free(original);
        try std.testing.expectEqualSlices(u8, original, decompressed_buffer[0..decompressed_size]);
    }
}

test "compression recipes" {
    const allocator = std.testing.allocator;

    const text_data = "Hello, World! This is a test of text compression." ** 20;

    // Test different recipes
    const recipes = [_]z.CompressionRecipe{
        .fast,
        .balanced,
        .text,
        .structured_data,
    };

    for (recipes) |recipe| {
        const cctx = try z.init_compressor(.{ .recipe = recipe });
        defer _ = z.free_compressor(cctx);

        const compressed = try z.compress(allocator, cctx, text_data);
        defer allocator.free(compressed);

        std.debug.print(
            "Recipe {s}: {d} -> {d} bytes ({d:.1}% ratio)\n",
            .{
                @tagName(recipe),
                text_data.len,
                compressed.len,
                @as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(text_data.len)) * 100.0,
            },
        );

        const dctx = try z.init_decompressor(.{});
        defer _ = z.free_decompressor(dctx);

        const decompressed = try z.decompress(
            allocator,
            dctx,
            compressed,
        );
        defer allocator.free(decompressed);

        try std.testing.expectEqualSlices(u8, text_data, decompressed);
    }
}

test "dictionary compression" {
    const allocator = std.testing.allocator;

    // Simulate multiple similar JSON-like strings
    const sample1 = "{\"name\":\"Alice\",\"age\":30,\"city\":\"New York\"}";
    const sample2 = "{\"name\":\"Bob\",\"age\":25,\"city\":\"Los Angeles\"}";
    // const sample3 = "{\"name\":\"Charlie\",\"age\":35,\"city\":\"Chicago\"}";

    // Use first sample as dictionary
    const dictionary = sample1;

    const cctx = try z.init_compressor(.{});
    defer _ = z.free_compressor(cctx);

    // Compress with dictionary
    const compressed_with_dict = try z.compress_with_dict(
        allocator,
        cctx,
        sample2,
        dictionary,
        3,
    );
    defer allocator.free(compressed_with_dict);

    // Compress without dictionary for comparison
    const compressed_without_dict = try z.compress(allocator, cctx, sample2);
    defer allocator.free(compressed_without_dict);

    std.debug.print(
        "Dictionary compression: {d} bytes (with dict) vs {d} bytes (without dict)\n",
        .{ compressed_with_dict.len, compressed_without_dict.len },
    );

    // Decompress with dictionary
    const dctx = try z.init_decompressor(.{});
    defer _ = z.free_decompressor(dctx);

    const decompressed = try z.decompress_with_dict(
        allocator,
        dctx,
        compressed_with_dict,
        dictionary,
        sample2.len,
    );
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, sample2, decompressed);
}

test "decompressor with memory limit" {
    const allocator = std.testing.allocator;

    const data = "Test data" ** 100;

    // Compress normally
    const cctx = try z.init_compressor(.{});
    defer _ = z.free_compressor(cctx);

    const compressed = try z.compress(allocator, cctx, data);
    defer allocator.free(compressed);

    // Decompress with memory limit (window log 20 = 1MB max)
    const dctx = try z.init_decompressor(.{ .max_window_log = 20 });
    defer _ = z.free_decompressor(dctx);

    const decompressed = try z.decompress(
        allocator,
        dctx,
        compressed,
    );
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, data, decompressed);
    std.debug.print("Decompression with memory limit: SUCCESS\n", .{});
}
