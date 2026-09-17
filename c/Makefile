CC     := cc
CFLAGS := -std=c99 -Wall -Wextra -O2 -Ilib
AR     := ar

LIBDIR := lib
LIB    := $(LIBDIR)/libdgtboard.a

BINDIR := bin

BASIC      := $(BINDIR)/dgt_example
SCAN       := $(BINDIR)/dgt_scan
UCI_ENGINE := $(BINDIR)/dgt_uci_engine
TEST       := $(BINDIR)/dgt_test_moves

.PHONY: all test clean

all: $(BASIC) $(SCAN) $(UCI_ENGINE)

$(LIB): $(LIBDIR)/dgtboard.o
	$(AR) rcs $@ $^

$(BASIC): examples/basic/example.o $(LIB) | $(BINDIR)
	$(CC) $(CFLAGS) -o $@ $< -L$(LIBDIR) -ldgtboard

$(SCAN): examples/scan/scan.o $(LIB) | $(BINDIR)
	$(CC) $(CFLAGS) -o $@ $< -L$(LIBDIR) -ldgtboard

$(UCI_ENGINE): examples/uci_engine/uci_engine.o $(LIB) | $(BINDIR)
	$(CC) $(CFLAGS) -o $@ $< -L$(LIBDIR) -ldgtboard

$(BINDIR):
	mkdir -p $(BINDIR)

%.o: %.c lib/dgtboard.h
	$(CC) $(CFLAGS) -c -o $@ $<

test: tests/test_moves.c $(LIBDIR)/dgtboard.c $(LIBDIR)/dgtboard.h | $(BINDIR)
	$(CC) $(CFLAGS) -o $(TEST) tests/test_moves.c
	./$(TEST)

clean:
	rm -f $(LIBDIR)/*.o $(LIB)
	rm -f examples/*/*.o
	rm -f $(BASIC) $(SCAN) $(UCI_ENGINE) $(TEST)
