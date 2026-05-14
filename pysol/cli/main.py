"""CLI entry point — mimics CPython's interface."""

import argparse
import sys
import os
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(
        prog="solpython",
        description="Python-to-EVM compiler — run Python on-chain",
    )
    parser.add_argument("script", nargs="?", help="Python script file to run")
    parser.add_argument("-c", dest="command", help="Python command to execute")
    parser.add_argument("-v", "--verbose", action="store_true", help="Show compilation details")
    parser.add_argument("--version", action="store_true", help="Show version and exit")
    parser.add_argument("--build", action="store_true", help="Compile Solidity contracts and exit")
    parser.add_argument("--backend", choices=["vm", "solidity", "yul"], default="vm",
                        help="Backend: vm (execute, default), solidity (transpile), yul (transpile)")

    args = parser.parse_args()

    if args.version:
        from pysol import __version__
        print(f"solpython {__version__}")
        return

    if args.build:
        from pysol.build import build
        build()
        return

    if args.command:
        source = args.command
        if not source.endswith("\n"):
            source += "\n"
        _execute(source, verbose=args.verbose, backend=args.backend)
        return

    if args.script:
        if not os.path.exists(args.script):
            print(f"solpython: can't open file '{args.script}': No such file or directory")
            sys.exit(1)
        _execute_file(args.script, verbose=args.verbose, backend=args.backend)
        return

    _repl(verbose=args.verbose)


def _execute(source: str, *, verbose: bool = False, backend: str = "vm"):
    from pysol.executor import run, compile_to_solidity, compile_to_yul
    try:
        if backend == "solidity":
            output = compile_to_solidity(source, verbose=verbose)
        elif backend == "yul":
            output = compile_to_yul(source, verbose=verbose)
        else:
            output = run(source, verbose=verbose)
        if output:
            print(output)
    except FileNotFoundError as e:
        print(str(e))
        sys.exit(1)
    except Exception as e:
        print(f"solpython: error: {e}", file=sys.stderr)
        if verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


def _execute_file(path: str, *, verbose: bool = False, backend: str = "vm"):
    from pysol.executor import run_file, compile_to_solidity, compile_to_yul
    try:
        if backend in ("solidity", "yul"):
            source = Path(path).read_text()
            if backend == "solidity":
                output = compile_to_solidity(source, verbose=verbose)
            else:
                output = compile_to_yul(source, verbose=verbose)
        else:
            output = run_file(path, verbose=verbose)
        if output:
            print(output)
    except FileNotFoundError as e:
        print(str(e))
        sys.exit(1)
    except Exception as e:
        print(f"solpython: error: {e}", file=sys.stderr)
        if verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


def _repl(*, verbose: bool = False):
    from pysol import __version__
    print(f"solpython {__version__}")
    print('Type "exit()" or Ctrl-D to exit.')
    print()

    while True:
        try:
            line = input(">>> ")
        except (EOFError, KeyboardInterrupt):
            print()
            break

        if not line.strip():
            continue
        if line.strip() in ("exit()", "quit()"):
            break

        source = line + "\n"
        if line.rstrip().endswith(":"):
            while True:
                try:
                    cont = input("... ")
                except (EOFError, KeyboardInterrupt):
                    print()
                    break
                if not cont.strip():
                    break
                source += cont + "\n"

        try:
            _execute(source, verbose=verbose)
        except SystemExit:
            pass


if __name__ == "__main__":
    main()
