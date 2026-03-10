CC      = gcc
CFLAGS  = -Wall -Wno-unused-function -g
LIBS    = -lm

TARGET  = chandrabindu

SRC     = lex.yy.c parser.tab.c main.c

all: $(TARGET)

# Step 1: Run Bison to generate parser.tab.c and parser.tab.h
parser.tab.c parser.tab.h: parser.y
	bison -d parser.y

# Step 2: Run Flex to generate lex.yy.c (depends on parser.tab.h for token defs)
lex.yy.c: lexer.l parser.tab.h
	flex lexer.l

# Step 3: Compile everything
$(TARGET): $(SRC)
	$(CC) $(CFLAGS) $(SRC) -o $(TARGET) $(LIBS)

# Run with default input
run: $(TARGET)
	./$(TARGET) input.bs

# Run test files
test-valid: $(TARGET)
	./$(TARGET) tests/valid/test1.bs

test-syntax: $(TARGET)
	./$(TARGET) tests/syntax_error.bs

test-semantic: $(TARGET)
	./$(TARGET) tests/semantic_error.bs

test-invalid-token: $(TARGET)
	./$(TARGET) tests/invalid_token.bs

clean:
	rm -f lex.yy.c parser.tab.c parser.tab.h $(TARGET) output.txt

.PHONY: all run test-valid test-syntax test-semantic test-invalid-token clean
