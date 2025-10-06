# ==========================================
# Zstd static library builder for Zig
# ==========================================

ZSTD_VERSION := 1.5.7
ZSTD_URL := https://github.com/facebook/zstd/releases/download/v$(ZSTD_VERSION)/zstd-$(ZSTD_VERSION).tar.gz
ZSTD_ARCHIVE := zstd-$(ZSTD_VERSION).tar.gz
ZSTD_DIR := zstd-$(ZSTD_VERSION)
PREFIX := vendor/zstd

.PHONY: all clean download extract build install

all: $(PREFIX)/libzstd.a

# ------------------------------------------
# Download source
# ------------------------------------------
download:
	@echo "==> Downloading Zstd $(ZSTD_VERSION)..."
	curl -L $(ZSTD_URL) -o $(ZSTD_ARCHIVE)

# ------------------------------------------
# Extract source
# ------------------------------------------
extract: download
	@echo "==> Extracting..."
	tar -xzf $(ZSTD_ARCHIVE)

# ------------------------------------------
# Build static lib
# ------------------------------------------
build: extract
	@echo "==> Building static lib..."
	$(MAKE) -C $(ZSTD_DIR)/lib libzstd.a

# ------------------------------------------
# Copy to deps/
# ------------------------------------------
install: build
	@echo "==> Installing to $(PREFIX)..."
	mkdir -p $(PREFIX)
	cp $(ZSTD_DIR)/lib/libzstd.a $(PREFIX)/
	cp -r $(ZSTD_DIR)/lib/zstd.h $(PREFIX)/
	cp -r $(ZSTD_DIR)/lib/zstd_errors.h $(PREFIX)/
	cp -r $(ZSTD_DIR)/lib/dictBuilder $(PREFIX)/dictBuilder

# ------------------------------------------
# Cleanup
# ------------------------------------------
clean:
	@echo "==> Cleaning..."
	rm -rf $(ZSTD_DIR) $(ZSTD_ARCHIVE) $(PREFIX)

# Convenience shortcut
$(PREFIX)/libzstd.a: install
