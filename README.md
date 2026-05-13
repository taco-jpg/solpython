# solpython

A Python-to-EVM compiler written entirely in Solidity. Feed it Python source code as a string, get EVM-compatible bytecode out — no off-chain tooling required.

644 tests across 46 test suites.

## Architecture

Six-phase compiler pipeline, each phase implemented as a Solidity contract:

```
Python source (string)
       │
       ▼
  ┌──────────┐
  │  Lexer   │  Tokenizes source into token stream
  └────┬─────┘
       │ Token[]
       ▼
  ┌──────────┐
  │  Parser  │  Recursive descent → AST (struct array in storage)
  └────┬─────┘
       │ ASTNode[]
       ▼
  ┌───────────────┐
  │   Semantic    │  Symbol table, scope resolution, type inference
  │   Analyzer    │
  └────┬──────────┘
       │
       ▼
  ┌───────────────┐
  │     Code      │  AST → custom stack-based bytecode
  │   Generator   │
  └────┬──────────┘
       │ bytes (bytecode)
       ▼
  ┌──────────┐
  │    VM    │  Stack machine executes bytecode
  └──────────┘
```

Alternative backends:
- **Solidity Backend** — AST → Solidity source code transpiler
- **Yul Backend** — AST → Yul IR transpiler

## Supported Python Features

**Core:**
- Integer arithmetic (`+`, `-`, `*`, `/`, `//`, `%`, `**`) with negative numbers
- Augmented assignment (`+=`, `-=`, `*=`, `/=`)
- Comparisons (`==`, `!=`, `<`, `>`, `<=`, `>=`, `is`, `is not`)
- Chained comparisons (`a < b < c`)
- Boolean operators (`and`, `or`, `not`)
- Ternary expressions (`a if cond else b`)
- `if` / `elif` / `else`
- `while` loops
- `for` loops with `range()`, list iteration, `break`, `continue`
- `for...else` / `while...else`
- Function definitions with recursion, default parameters, keyword arguments
- Nested function definitions
- `return` statements
- `pass` statement

**Data Types:**
- Integers (tagged, -2^62 to 2^62-1)
- Booleans (`True`, `False`) with proper tagging
- `None` type with safety checks
- Strings with methods (`upper`, `lower`, `split`, `contains`, `charAt`, slice)
- Lists with indexing, negative indexing, `len()`, `append()`
- Dicts with string/int keys, `items()`, `values()`, `get()`, `update()`
- Sets with `add()`, `remove()`, `in` operator
- Tuples with unpacking (`a, b = 1, 2`)
- Float (6-digit fixed-point)

**Builtins:**
- `print()` — integer and string output
- `len()`, `type()`, `isinstance()`
- `range()`, `enumerate()`, `zip()`
- `map()`, `filter()`
- `sorted()`, `reversed()`
- `abs()`, `min()`, `max()`
- f-strings and `%s`/`%d` formatting

**Advanced:**
- `try` / `except` / `finally` / `raise`
- `class` with methods, `self`, single inheritance
- `import` / `from...import` with static linking
- `global` / `nonlocal` keywords
- Virtual file system (VFS) for module loading
- Garbage collection (reference counting)
- Constant folding and dead code elimination
- Structured error messages with line/column info

## Build & Test

Requires [Foundry](https://book.getfoundry.sh/).

```shell
forge build          # compile
forge test           # run all 644 tests
forge test -vvv      # verbose output
forge test --match-test testFibonacci   # run a single test
```

## Example

```python
def fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)

print(fib(10))  # → 55
```

This compiles to bytecode that runs entirely on-chain via the Solidity VM contract.

## Project Structure

```
src/
  types/                  AST node, token, and type info structs
  libraries/              String utility library
  phases/
    Lexer.sol             Tokenizer
    Parser.sol            Recursive descent parser
    SemanticAnalyzer.sol  Symbol table, scope resolution
    CodeGenerator.sol     AST → bytecode
    VM.sol                Stack-based bytecode interpreter
    SolidityBackend.sol   AST → Solidity source transpiler
    YulBackend.sol        AST → Yul IR transpiler
  optimizer/
    ConstantFolder.sol    Compile-time constant folding
  gc/
    RefCounter.sol        Reference counting GC
  vfs/
    VFS.sol               Virtual file system
  venv/
    Venv.sol              Compilation environment
  PythonCompiler.sol      Top-level orchestrator

test/
  46 test suites covering lexer, parser, semantic analysis,
  code generation, VM execution, and end-to-end integration.

  Key files:
    Integration.t.sol     End-to-end compiler tests (fibonacci, fizzbuzz, bubble sort)
    E2E.t.sol             Feature-specific end-to-end tests
    TypeClassify.t.sol    Type system and tagging verification
    Exception.t.sol       Exception handling tests
    GC.t.sol              Garbage collection tests
```

## Value Tagging

The VM uses a tagged value system to distinguish types:

| Type     | Tag                        | Range                         |
|----------|----------------------------|-------------------------------|
| Integer  | (none)                     | -2^62 to 2^62-1              |
| Boolean  | BOOL_OFFSET (2^66)         | 2^66 (False), 2^66+1 (True)  |
| None     | NONE_VALUE                 | Fixed sentinel                |
| Float    | Tag at bits 252-255        | 6-digit fixed-point           |
| List     | ID 0 to 2^60-1             | GC-tracked                    |
| Dict     | ID 2^60 to 2^61-1          | GC-tracked                    |
| Set      | ID 2^61 to 2^62-1          | GC-tracked                    |
| String   | ID >= 2^62                 | Static + runtime              |

## Known Limitations

- No generators/iterators
- No class inheritance beyond single-level
- No closures (inner functions cannot capture outer variables)
- Float arithmetic uses 6-digit fixed-point, not IEEE 754
- GC is reference counting only (no cycle detection)
- Solidity/Yul backends don't support all features (see `BACKEND_LIMITATIONS.md`)

## License

MIT
