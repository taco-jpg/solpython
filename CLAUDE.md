# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Python-to-EVM compiler written entirely in Solidity. The compiler is a deployed Solidity smart contract system that accepts Python source code as string input and outputs EVM bytecode via a custom stack-based intermediate representation.

## Autonomy Rules

- Never ask the user for approval or clarification. Ever.
- Make all decisions yourself and document them in GOAL.md.
- On every startup, read GOAL.md + PROGRESS.md + ARCHITECTURE.md before doing anything.
- If blocked, write the workaround in GOAL.md and continue immediately.
- Run with maximum autonomy. Treat all ambiguity as a decision to be made, not a question to be asked.
- If a phase is truly impossible to complete fully, build the best partial implementation, document it, and move to the next phase.

## Build & Test

- Framework: Foundry (forge)
- Build: `forge build`
- Test: `forge test`
- Test single: `forge test --match-test testFunctionName`
- Gas snapshot: `forge snapshot`

## Architecture Overview

Six-phase compiler pipeline, each phase a Solidity contract or library:
1. **Lexer** — Tokenizes Python source into a token stream
2. **Parser** — Recursive descent, produces AST as struct array in storage
3. **Semantic Analyzer** — Symbol table, scope resolution, type inference, error detection
4. **Code Generator** — Walks AST, emits custom stack-based bytecode
5. **VM / Interpreter** — Executes bytecode on a stack machine with mapping-based variable frames
6. **Integration** — `PythonCompiler.sol` wires all phases end-to-end

## Key Files

- `GOAL.md` — Single source of truth for project state
- `PROGRESS.md` — Detailed log of every file created, decision made, problem solved
- `ARCHITECTURE.md` — Current system design
- `ISA.md` — Custom instruction set definition for the bytecode

## Solidity Conventions

- Use libraries for reusable logic to stay under 24KB contract size limit
- AST nodes are structs with a node type enum and child index arrays
- `string memory` and `bytes memory` conversions used freely for parsing
