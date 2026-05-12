# solpython

A Python-to-EVM compiler written entirely in Solidity. Feed it Python source code, get EVM-compatible bytecode out — no off-chain tooling required.

## Architecture

Six-phase compiler pipeline, each phase implemented as a Solidity contract:

```
Python source → Lexer → Parser → Semantic Analyzer → Code Generator → Bytecode
                                                                              ↓
                                                                         VM executes
```

1. **Lexer** — Tokenizes Python source into a token stream
2. **Parser** — Recursive descent parser, produces AST stored as a struct array
3. **Semantic Analyzer** — Symbol table, scope resolution, type inference, error detection
4. **Code Generator** — Walks the AST and emits custom stack-based bytecode
5. **VM** — Executes bytecode on a stack machine with mapping-based variable frames
6. **Integration** — `PythonCompiler.sol` wires all phases end-to-end

## Supported Python Features

- Integer arithmetic (`+`, `-`, `*`, `/`, `//`, `%`, `**`)
- Augmented assignment (`+=`, `-=`, `*=`, `/=`)
- Comparisons (`==`, `!=`, `<`, `>`, `<=`, `>=`)
- Boolean operators (`and`, `or`, `not`)
- `if` / `elif` / `else`
- `while` loops
- `for` loops (basic)
- Function definitions with recursion
- Lists with indexing and `len()`
- `print()` builtin

## Build & Test

Requires [Foundry](https://book.getfoundry.sh/).

```shell
forge build          # compile
forge test           # run all tests (151 passing)
forge test -vvv      # verbose output
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
  types/           AST node, token, and type info structs
  libraries/       String utility library
  phases/
    Lexer.sol      Tokenizer
    Parser.sol     Recursive descent parser
    SemanticAnalyzer.sol
    CodeGenerator.sol   AST → bytecode
    VM.sol              Stack-based bytecode interpreter
  PythonCompiler.sol    Top-level orchestrator
test/
  Lexer.t.sol, Parser.t.sol, SemanticAnalyzer.t.sol,
  CodeGenerator.t.sol, VM.t.sol, Integration.t.sol, Demo.t.sol
```

## License

MIT
