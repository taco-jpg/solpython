"""Compile Solidity contracts and produce JSON artifacts for the Python package."""

import json
import os
import subprocess
import sys
from pathlib import Path

SOLC_VERSION = "0.8.20"
SRC_DIR = Path(__file__).parent.parent / "src"
ARTIFACTS_DIR = Path(__file__).parent / "contracts" / "artifacts"

# Contracts we need to deploy from Python
TARGET_CONTRACTS = ["PythonCompiler", "VM"]


def _find_solc() -> str:
    """Find solc binary — try solcx, then system solc, then forge."""
    try:
        import solcx
        solcx.install_solc(SOLC_VERSION)
        return str(Path(solcx.get_solcx_install_folder()) / f"solc-{SOLC_VERSION}")
    except ImportError:
        pass

    # Try system solc
    result = subprocess.run(["which", "solc"], capture_output=True, text=True)
    if result.returncode == 0:
        return result.stdout.strip()

    # Try forge
    result = subprocess.run(["which", "forge"], capture_output=True, text=True)
    if result.returncode == 0:
        # Use forge to compile, then extract artifacts
        return "forge"

    print("Error: No Solidity compiler found.")
    print("Install one of:")
    print("  pip install py-solc-x")
    print("  brew install solidity  (or equivalent)")
    print("  curl -L https://foundry.paradigm.xyz | bash && foundryup")
    sys.exit(1)


def _compile_with_forge():
    """Compile using Foundry and extract artifacts."""
    project_dir = Path(__file__).parent.parent
    result = subprocess.run(
        ["forge", "build"],
        cwd=project_dir,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Forge build failed:\n{result.stderr}")
        sys.exit(1)

    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)

    for name in TARGET_CONTRACTS:
        # Foundry stores artifacts in out/ContractName.sol/ContractName.json
        artifact_path = project_dir / "out" / f"{name}.sol" / f"{name}.json"
        if not artifact_path.exists():
            print(f"Warning: artifact not found at {artifact_path}")
            continue

        data = json.loads(artifact_path.read_text())
        # Extract just abi and bytecode
        output = {
            "abi": data.get("abi", []),
            "bytecode": data.get("bytecode", {}).get("object", ""),
        }
        out_path = ARTIFACTS_DIR / f"{name}.json"
        out_path.write_text(json.dumps(output, indent=2))
        print(f"  Wrote {out_path}")


def _compile_with_solcx(solc_path: str):
    """Compile using solcx."""
    import solcx

    sources = {}
    src_dir = SRC_DIR

    # Collect all .sol files
    for sol_file in src_dir.rglob("*.sol"):
        rel = sol_file.relative_to(src_dir.parent)
        sources[str(rel)] = {"content": sol_file.read_text()}

    # Need to also find OpenZeppelin or other deps if used
    # For now, our contracts are self-contained

    output = solcx.compile_standard(
        {
            "language": "Solidity",
            "sources": {k: {"content": v["content"]} for k, v in sources.items()},
            "settings": {
                "outputSelection": {
                    "*": {
                        "*": ["abi", "evm.bytecode.object"],
                    }
                },
                "remappings": [],
            },
        },
        solc_binary=solc_path,
        allow_paths=[str(src_dir.parent)],
    )

    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)

    for name in TARGET_CONTRACTS:
        # Find the contract in the output
        for source_path, contracts in output.get("contracts", {}).items():
            if name in contracts:
                contract = contracts[name]
                artifact = {
                    "abi": contract.get("abi", []),
                    "bytecode": contract.get("evm", {}).get("bytecode", {}).get("object", ""),
                }
                if artifact["bytecode"]:
                    out_path = ARTIFACTS_DIR / f"{name}.json"
                    out_path.write_text(json.dumps(artifact, indent=2))
                    print(f"  Wrote {out_path}")
                    break
        else:
            print(f"Warning: contract '{name}' not found in compilation output")


def build():
    """Compile Solidity contracts and generate artifacts."""
    print("Compiling Solidity contracts...")
    solc = _find_solc()

    if solc == "forge":
        _compile_with_forge()
    else:
        _compile_with_solcx(solc)

    print("Done!")


if __name__ == "__main__":
    build()
