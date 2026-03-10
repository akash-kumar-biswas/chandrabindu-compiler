# BanglaScript Compiler

A statically typed, interpreted programming language with **Bangla (Romanized Bengali) keywords**, built using Flex, Bison, and C. Developed as a Compiler Design course project, BanglaScript implements a complete compiler pipeline — lexical analysis, syntax analysis, semantic checking, intermediate code generation, and tree-walk interpretation.

---

## Table of Contents

- [Overview](#overview)
- [Language Features](#language-features)
- [Prerequisites](#prerequisites)
- [Build Instructions](#build-instructions)
- [Usage](#usage)
- [Language Reference](#language-reference)
  - [Data Types](#data-types)
  - [Keywords](#keywords)
  - [Variable Declaration](#variable-declaration)
  - [Functions](#functions)
  - [Control Flow](#control-flow)
  - [Arrays and Strings](#arrays-and-strings)
  - [I/O](#io)
  - [Operators](#operators)
  - [Built-in Math Functions](#built-in-math-functions)
  - [Comments](#comments)
- [Error Handling](#error-handling)
- [Sample Program](#sample-program)
- [Project Structure](#project-structure)
- [Compiler Pipeline](#compiler-pipeline)

---

## Overview

BanglaScript programs are written in `.bs` source files. The compiler reads a source file, tokenizes it, parses it into an AST, validates semantics, generates TAC-like intermediate code, and executes the program by walking the AST.

- Output is written to both the **terminal** and `output.txt` simultaneously
- Intermediate representation is written to `intermediate.txt` after every successful parse
- All error messages (lexical, syntax, semantic, runtime) are reported in both the terminal and `output.txt`

---

## Language Features

- **Bangla keywords** — all control flow and type names use Romanized Bengali words
- **Static typing** — 7 data types with implicit numeric promotion
- **Block scoping** — C-style lexical scope; variable shadowing supported
- **User-defined functions** — typed parameters, typed return values, full recursion support
- **1D homogeneous arrays** — `talika<T>`, with runtime bounds checking and `.size()`
- **Mutable strings** — character-level indexing and mutation; array of strings with double-indexing
- **Built-in math** — `sin`, `cos`, `tan`, `log`, `log10`, `borgomul`, `uporePurno`, `nichePurno`, `porom`
- **Power operator** — `x ^^ y` evaluates `x` to the power `y`
- **Short-circuit evaluation** for `&&` and `||`
- **Pre/postfix increment & decrement** — `++`, `--`
- **Compound assignment** — `+=`, `-=`, `*=`, `/=`, `%=`
- **Bitwise operators** — `&`, `|`, `^`, `~`, `<<`, `>>`
- **TAC-like IR generation** — emitted to `intermediate.txt` after every successful parse
- **Dual output** — all print output written to both terminal and `output.txt`

---

## Prerequisites

| Tool             | Notes            |
| ---------------- | ---------------- |
| **GCC** >= 9.0   | C compiler       |
| **Flex** >= 2.6  | Lexer generator  |
| **Bison** >= 3.0 | Parser generator |
| **Make**         | Build automation |

### Windows (MSYS2 MINGW64) — Recommended

Install [MSYS2](https://www.msys2.org/), then in the MINGW64 terminal:

```bash
pacman -S mingw-w64-x86_64-gcc flex bison make
```

### Linux (Ubuntu/Debian)

```bash
sudo apt install gcc flex bison make
```

---

## Build Instructions

```bash
git clone https://github.com/<your-username>/banglascript-compiler.git
cd banglascript-compiler
make
```

The build pipeline runs in order:

1. `bison -d parser.y` → generates `parser.tab.c` and `parser.tab.h`
2. `flex lexer.l` → generates `lex.yy.c`
3. `gcc -Wall -Wno-unused-function -g lex.yy.c parser.tab.c main.c -o compiler -lm`

```bash
make clean    # Remove all generated files
```

---

## Usage

```bash
./compiler <source_file.bs>
```

**Example:**

```bash
./compiler input.bs
```

After running:

- Program output → printed to terminal and saved to `output.txt`
- Intermediate code → saved to `intermediate.txt`

**Makefile shortcuts:**

```bash
make run      # Build and run input.bs
make clean    # Remove generated files
```

---

## Language Reference

### Data Types

| Keyword         | Meaning         | C Equivalent    |
| --------------- | --------------- | --------------- |
| `purno`         | Integer         | `int`           |
| `doshomik`      | Decimal / Float | `double`        |
| `okkhor`        | Character       | `char`          |
| `shottiMiththa` | Boolean         | `bool`          |
| `khali`         | Void            | `void`          |
| `okkhorMala`    | String          | mutable `char*` |
| `talika<T>`     | Typed Array     | `T[]`           |

**Boolean literals:** `shotti` (true) · `miththa` (false)

**Implicit promotion:** `purno + doshomik` → result is `doshomik`

---

### Keywords

#### Control Flow

| Keyword       | Meaning    |
| ------------- | ---------- |
| `jodi`        | `if`       |
| `naholeJodi`  | `else if`  |
| `nahole`      | `else`     |
| `ghurao`      | `for`      |
| `jotokkhon`   | `while`    |
| `nirbachon`   | `switch`   |
| `dhoro`       | `case`     |
| `onnotha`     | `default`  |
| `thamo`       | `break`    |
| `cholteThako` | `continue` |
| `ferao`       | `return`   |

#### Functions & Program

| Keyword  | Meaning              |
| -------- | -------------------- |
| `kaj`    | function declaration |
| `mukkho` | entry point (`main`) |

#### I/O

| Keyword      | Meaning              |
| ------------ | -------------------- |
| `dekhao`     | print (no newline)   |
| `dekhaoLine` | print (with newline) |
| `nao`        | read input           |

---

### Variable Declaration

```
## Single variable
x: purno = 42;
pi: doshomik = 3.14;
ch: okkhor = 'A';
flag: shottiMiththa = shotti;
name: okkhorMala = "akash";

## Uninitialized
y: purno;

## Multiple variables (count must match)
a, b, c: purno = 1, 2, 3;

## Array (initialized)
nums: talika<purno> = [10, 20, 30];

## Array (uninitialized — populated via nao)
arr: talika<purno>;
```

---

### Functions

Every program must have exactly one `mukkho` (entry point) function.

```
kaj add(a: purno, b: purno) -> purno {
    ferao a + b;
}

kaj greet(name: okkhorMala) -> khali {
    dekhaoLine("Hello, ", name);
}

kaj mukkho() -> purno {
    result: purno = add(3, 7);
    dekhaoLine("Sum = ", result);
    greet("Akash");
    ferao 0;
}
```

- Non-void functions must use `ferao expression;`
- Void (`khali`) functions use `ferao;` or may omit the return
- Recursion is fully supported
- Function parameters may include array types: `param: talika<purno>`

---

### Control Flow

**If / Else if / Else**

```
jodi (x > 10) {
    dekhaoLine("baro");
} naholeJodi (x == 10) {
    dekhaoLine("shoman");
} nahole {
    dekhaoLine("choto");
}
```

Braces are always required, even for single-statement bodies.

**For loop**

```
ghurao(i: purno = 0; i < 5; i++) {
    dekhao(i, " ");
}
```

The loop variable may be declared inline in the init expression.

**While loop**

```
jotokkhon (x > 0) {
    x--;
}
```

**Switch**

```
nirbachon (day) {
    dhoro 1:
        dekhaoLine("Monday");
        thamo;
    dhoro 2:
        dekhaoLine("Tuesday");
        thamo;
    onnotha:
        dekhaoLine("Other day");
}
```

**Break and Continue**

```
thamo;        ## exit loop or switch
cholteThako;  ## skip to next iteration
```

---

### Arrays and Strings

```
## Arrays
nums: talika<purno> = [1, 2, 3];
dekhaoLine(nums[0]);        ## access element
dekhaoLine(nums.size());    ## 3
nums[1] = 99;               ## mutate element

## Array of strings
names: talika<okkhorMala> = ["akash", "rahim"];
dekhaoLine(names[0]);       ## "akash"
dekhaoLine(names[0][2]);    ## 'a' (character at index 2)

## Strings
name: okkhorMala = "hello";
name[0] = 'H';              ## mutable character assignment
dekhaoLine(name);           ## "Hello"
dekhaoLine(name.size());    ## 5
```

---

### I/O

```
## Print without newline
dekhao("x = ", x);

## Print with newline
dekhaoLine("Value = ", x, ", y = ", y);

## Read a scalar value
nao(x);

## Read array — reads a full line of space-separated values
nao(arr);
```

---

### Operators

| Category              | Operators                        |
| --------------------- | -------------------------------- |
| Arithmetic            | `+` `-` `*` `/` `%` `^^` (power) |
| Assignment            | `=` `+=` `-=` `*=` `/=` `%=`     |
| Increment / Decrement | `++` `--` (prefix and postfix)   |
| Relational            | `<` `>` `<=` `>=` `==` `!=`      |
| Logical               | `&&` `\|\|` `!`                  |
| Bitwise               | `&` `\|` `^` `~` `<<` `>>`       |

---

### Built-in Math Functions

| Function        | Description       | Return Type |
| --------------- | ----------------- | ----------- |
| `borgomul(x)`   | Square root       | `doshomik`  |
| `porom(x)`      | Absolute value    | `purno`     |
| `uporePurno(x)` | Ceiling           | `doshomik`  |
| `nichePurno(x)` | Floor             | `doshomik`  |
| `sin(x)`        | Sine              | `doshomik`  |
| `cos(x)`        | Cosine            | `doshomik`  |
| `tan(x)`        | Tangent           | `doshomik`  |
| `log(x)`        | Natural logarithm | `doshomik`  |
| `log10(x)`      | Base-10 logarithm | `doshomik`  |
| `x ^^ y`        | x to the power y  | `doshomik`  |

---

### Comments

```
## Single-line comment

#*
   Multi-line
   comment
*#
```

---

## Error Handling

All errors (along with normal output) are reported in both the terminal and `output.txt`. The compiler exits immediately on error with a descriptive message and line number.

### Lexical Errors

```
Lexical Error: Invalid token '@' at line 6
Lexical Error: Unterminated multi-line comment at line 12
```

### Syntax Errors

```
syntax error, unexpected token at line 8
```

### Semantic Errors

```
Semantic Error: Undeclared identifier 'y' at line 10
Semantic Error: Redeclaration of 'x' in the same scope at line 5
Semantic Error: Argument count mismatch for 'jog' at line 14
Semantic Error: 'thamo' used outside loop/switch at line 20
Semantic Error: Missing return in non-void function 'calculate'
Semantic Error: Array index must be purno at line 9
```

### Runtime Errors

```
Runtime Error: Array index 5 out of bounds (size 3) at line 11
Runtime Error: Division by zero at line 7
```

---

## Sample Program

```
## Recursive factorial and array prefix sum

kaj factorial(n: purno) -> purno {
    jodi (n <= 1) {
        ferao 1;
    }
    ferao n * factorial(n - 1);
}

kaj mukkho() -> purno {
    ## Factorial
    dekhaoLine("5! = ", factorial(5));

    ## Math built-ins
    dekhaoLine("sqrt(144) = ", borgomul(144.0));
    dekhaoLine("2^^10 = ", 2 ^^ 10);

    ## String mutation
    name: okkhorMala = "akash";
    name[0] = 'A';
    dekhaoLine("Name = ", name);

    ## For loop with inline variable
    ghurao(i: purno = 0; i < 5; i++) {
        dekhao(i, " ");
    }
    dekhaoLine("");

    ## Switch
    day: purno = 2;
    nirbachon (day) {
        dhoro 1: dekhaoLine("Monday"); thamo;
        dhoro 2: dekhaoLine("Tuesday"); thamo;
        onnotha: dekhaoLine("Other day");
    }

    ferao 0;
}
```

**Output:**

```
5! = 120
sqrt(144) = 12.000000
2^^10 = 1024.000000
Name = Akash
0 1 2 3 4
Tuesday
```

---

## Project Structure

```
banglascript-compiler/
├── lexer.l              # Flex lexer — tokenizes source, handles comments
├── parser.y             # Bison parser — AST, semantic checks, interpreter, IR generator
├── main.c               # Entry point — orchestrates the full compiler pipeline
├── Makefile             # Build automation
│
├── input.bs             # Sample BanglaScript program
├── output.txt           # Program output (generated at runtime)
├── intermediate.txt     # TAC-like intermediate code (generated at runtime)
│
└── test_errors/
    ├── invalid_token.bs  # Lexical error test
    ├── syntax_error.bs   # Syntax error test
    └── semantic_error.bs # Semantic error test
```

> `lex.yy.c`, `parser.tab.c`, `parser.tab.h`, and `compiler`/`compiler.exe` are generated at build time and not committed to the repository.

---

## Compiler Pipeline

```
input.bs
    │
    ▼
┌────────────────────────────────┐
│  Flex Lexer  (lexer.l)         │  Tokenizes source, tracks line numbers
│                                │  → Lexical Error on invalid characters
└───────────────┬────────────────┘
                │ token stream
                ▼
┌────────────────────────────────┐
│  Bison Parser  (parser.y)      │  Builds AST, registers all functions
│                                │  Structural semantic checks at parse time
│                                │  → Syntax Error, structural Semantic Errors
└───────────────┬────────────────┘
                │ AST + function table
                ▼
┌────────────────────────────────┐
│  IR Generator  (parser.y)      │  Emits TAC-like intermediate code
└───────────────┬────────────────┘
                │
                ▼  intermediate.txt
┌────────────────────────────────┐
│  Interpreter  (parser.y)       │  Tree-walks AST from mukkho()
│                                │  Scoped symbol table, type checking
│                                │  → Runtime Errors
└───────────────┬────────────────┘
                │
                ▼
         stdout  +  output.txt
```

---

## Academic Context

This project was developed as part of a **Compiler Design Lab** course and demonstrates a full compilation pipeline:

| Phase             | Implementation                                              |
| ----------------- | ----------------------------------------------------------- |
| Lexical Analysis  | Flex-based tokenizer with error recovery                    |
| Syntax Analysis   | Bison LALR(1) parser with complete grammar                  |
| Semantic Analysis | Scoped symbol table, type checking, control flow validation |
| Intermediate Code | TAC-like IR with labels, temps, and function blocks         |
| Interpretation    | Direct AST tree-walk with runtime error detection           |

---

## License

This project is licensed under the [MIT License](LICENSE).
