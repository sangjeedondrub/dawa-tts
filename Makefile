# Makefile for dawa-tts

.PHONY: all build clean test help

# Default target
all: build

# Build the C++ module
build:
	@echo "Building dawa-tts module..."
	@mkdir -p build
	@cd build && cmake .. && cmake --build . --config Release
	@echo "Build complete: dawa-tts-module.dylib"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@if [ -d build ]; then \
		cd build && rm -f CMakeCache.txt && rm -f *.dylib && rm -f *.so; \
		cd .. && rmdir build 2>/dev/null || true; \
	fi
	@rm -f dawa-tts-module.dylib dawa-tts-module.so
	@echo "Clean complete"

# Deep clean (remove entire build directory)
distclean:
	@echo "Deep cleaning..."
	@rm -rf build
	@rm -f dawa-tts-module.dylib dawa-tts-module.so
	@echo "Deep clean complete"

# Run ERT tests
test:
	@echo "Running ERT tests..."
	@emacs -Q --batch \
		-l dawa-tts-lang.el \
		-l dawa-tts-chunk.el \
		-l test-dawa-tts.el \
		-f ert-run-tests-batch-and-exit

# Run interactive multilingual test
test-interactive:
	@echo "Starting interactive test..."
	@emacs -Q \
		-l dawa-tts.el \
		-l test-dawa-tts.el \
		--eval "(dawa-tts-test-multilingual)"

# Rebuild (clean + build)
rebuild: clean build

# Check if module exists
check:
	@if [ -f dawa-tts-module.dylib ] || [ -f dawa-tts-module.so ]; then \
		echo "✓ Module found"; \
		ls -lh dawa-tts-module.* 2>/dev/null || true; \
	else \
		echo "✗ Module not found. Run 'make build'"; \
		exit 1; \
	fi

# Show help
help:
	@echo "Dawa-TTS Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  make              - Build the module (default)"
	@echo "  make build        - Build the C++ module"
	@echo "  make clean        - Clean build artifacts"
	@echo "  make distclean    - Remove entire build directory"
	@echo "  make test         - Run ERT tests"
	@echo "  make test-interactive - Run interactive multilingual test"
	@echo "  make rebuild      - Clean and rebuild"
	@echo "  make check        - Check if module exists"
	@echo "  make help         - Show this help"
