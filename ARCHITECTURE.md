# ARCHITECTURE.md — Python-to-EVM Compiler

## Overview

A Python-to-EVM compiler implemented entirely as Solidity smart contracts. The compiler accepts Python source code as a string, processes it through a multi-phase pipeline, and produces custom stack-based bytecode that can be executed by an on-chain VM.

## Pipeline

```
Python Source Code (string)
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
  │   Semantic    │  Symbol table, scope resolution, type inference, error detection
  │   Analyzer    │
  └────┬──────────┘
       │ Annotated AST
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
       │
       ▼
  Execution Result
```

## Contract Structure

```
src/
├── PythonCompiler.sol          # Top-level orchestrator (Phase 6)
├── phases/
│   ├── Lexer.sol               # Phase 1: Tokenizer
│   ├── Parser.sol              # Phase 2: AST builder
│   ├── SemanticAnalyzer.sol    # Phase 3: Analysis
│   └── CodeGenerator.sol       # Phase 4: Bytecode emitter
├── vm/
│   └── VM.sol                  # Phase 5: Bytecode interpreter
├── libraries/
│   ├── TokenLib.sol            # Token types and helpers
│   ├── ASTLib.sol              # AST node types and helpers
│   └── StringLib.sol           # String/bytes manipulation utilities
└── types/
    ├── Token.sol               # Token struct and TokenType enum
    └── ASTNode.sol             # ASTNode struct and NodeType enum

test/
├── Lexer.t.sol                 # Lexer unit tests
├── Parser.t.sol                # Parser unit tests
├── SemanticAnalyzer.t.sol      # Semantic analysis tests
├── CodeGenerator.t.sol         # Code generation tests
├── VM.t.sol                    # VM unit tests
└── Integration.t.sol           # End-to-end compiler tests
```

## Key Design Decisions

### AST Representation
AST nodes are stored as a flat array of structs in contract storage. Each node contains:
- `NodeType` enum (e.g., FunctionDef, IfStatement, BinaryOp, etc.)
- Child indices (not pointers) into the node array
- Literal values where applicable (for number/string/bool nodes)
- Source location for error reporting

This avoids pointer complexity and makes serialization trivial.

### Token Stream
Tokens are stored as an array of structs. Each token has:
- `TokenType` enum
- Lexeme (the actual string)
- Literal value (for numbers/strings)
- Line number and column for error reporting

### Bytecode ISA
Custom stack-based instruction set defined in ISA.md. Instructions are single bytes with optional operand bytes. The VM uses a value stack and a mapping-based frame for local variables.

### Contract Size Management
- Libraries for shared logic (StringLib, TokenLib, ASTLib)
- Phases are separate contracts that can be composed
- If a single contract exceeds 24KB, split into sub-contracts with delegatecall

### String Handling
Solidity's limited string manipulation is the primary challenge. The lexer operates on `bytes` for character-by-character scanning, converting to `string memory` only for token storage. Helper functions in StringLib handle common operations.

## Data Flow

1. **Input**: `string memory pythonSource` passed to `PythonCompiler.compile()`
2. **Lexer**: Scans bytes, produces `Token[] memory` stored temporarily
3. **Parser**: Consumes `Token[]`, builds `ASTNode[]` in storage
4. **Semantic Analyzer**: Walks AST, populates symbol table mappings, annotates nodes with type info
5. **Code Generator**: Walks annotated AST, emits `bytes memory bytecode`
6. **VM**: Executes bytecode, returns result (or prints via events)

## Limitations (Known)
- No global variables across functions (Phase 3 scope)
- No import system (stdlib not available)
- No generators/iterators
- Float arithmetic uses 6-digit fixed-point (FLOAT_SCALE = 1,000,000), not IEEE 754 — precision is limited to ~6 significant digits
- String operations limited to comparison, concatenation, and basic methods (upper/lower/slice/split/contains/charAt)
