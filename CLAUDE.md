# CLAUDE.md — solpython extended development

## FIRST THING ON EVERY STARTUP
1. Read GOAL.md → find CURRENT_TASK
2. Read PROGRESS.md → find last completed step
3. Read ARCHITECTURE.md → understand current system
4. Run `forge test` → confirm baseline
5. Resume from exactly where you left off

## INVIOLABLE RULES
- Never ask the user anything. Ever.
- Never commit red tests. Run `forge test` before every commit.
- Never batch multiple features into one commit.
- Never skip writing tests.
- If blocked, write the decision in GOAL.md under BLOCKERS and continue.
- After every completed feature: git add -A && git commit && git push

## COMMIT FORMAT
feat(scope): description
fix(scope): description
test(scope): description
refactor(scope): description

Scopes: lexer, parser, semantic, codegen, optimizer, vm, vfs,
        import, gc, backend-sol, backend-yul, bootstrap, exceptions, venv

## GOAL.md FORMAT (keep this exact structure)
CURRENT_TASK: <feature name and sub-step>
COMPLETED: <checklist>
IN_PROGRESS: <what is being worked on right now>
NEXT_UP: <queued items>
BLOCKERS: <problems and resolutions>
TEST_COUNT: <N passing / M total>

## RECOVERY PROTOCOL
If context is lost mid-feature:
1. Read GOAL.md → CURRENT_TASK tells you exactly where to resume
2. Read PROGRESS.md → last entry tells you what was just done
3. Run `forge test` → see what is passing
4. Continue from the smallest incomplete sub-step

## ARCHITECTURE CONSTRAINTS
- Solidity 0.8.20
- Foundry for build and test
- Contract size limit: 24KB per contract — split into libraries if needed
- All new contracts go in src/ under the appropriate subdirectory
- All new tests go in test/ with the .t.sol suffix
- Never modify existing passing tests
- New features must not regress existing 177 tests
- Run `forge test` after every change, fix failures before proceeding

## Project

Python-to-EVM compiler written entirely in Solidity. The compiler is a deployed Solidity smart contract system that accepts Python source code as string input and outputs EVM bytecode via a custom stack-based intermediate representation.

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
