GPR      := dgt_smartboard.gpr
BIN      := bin/chesslink
RAW_DUMP := bin/raw_dump
TESTS    := bin/tests
ENCODE   := bin/clkb_encode
DECODE   := bin/clkb_decode

.PHONY: all build clean run run-raw test compress-book decompress-book help

all: build

build:
	mkdir -p bin obj
	gprbuild -P $(GPR)

clean:
	gprclean -P $(GPR)
	rm -f bin/chesslink bin/raw_dump bin/tests bin/clkb_encode bin/clkb_decode

run: build
	./$(BIN)

run-raw: build
	./$(RAW_DUMP)

test: build
	./$(TESTS)

compress-book: build
	./$(ENCODE)

decompress-book: build
	./$(DECODE)

help:
	@echo "Targets:"
	@echo "  build           - Build everything (default)"
	@echo "  clean           - Remove all build artifacts"
	@echo "  run             - Build and run chesslink"
	@echo "  run-raw         - Build and run raw_dump (serial port diagnostics)"
	@echo "  test            - Build and run the test suite"
	@echo "  compress-book   - Encode data/openings.dat -> data/openings.clkb"
	@echo "  decompress-book - Decode data/openings.clkb -> data/openings.dat"
	@echo "  help            - Show this message"
