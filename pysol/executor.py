"""Execute Python source via the on-chain compiler and VM."""

import json
from pathlib import Path

_ARTIFACTS_DIR = Path(__file__).parent / "contracts" / "artifacts"


def _patch_evm():
    """Disable EIP-3860 contract size limits in py-evm."""
    from eth.vm.forks.shanghai.computation import ShanghaiComputation
    from eth.vm.forks.spurious_dragon.computation import SpuriousDragonComputation

    @classmethod
    def _no_validate(cls, message):
        pass

    @classmethod
    def _no_consume(cls, computation):
        pass

    @classmethod
    def _no_validate_code(cls, code):
        pass

    ShanghaiComputation.validate_create_message = _no_validate
    ShanghaiComputation.consume_initcode_gas_cost = _no_consume
    SpuriousDragonComputation.validate_contract_code = _no_validate_code


def _load_artifact(name: str) -> dict:
    path = _ARTIFACTS_DIR / f"{name}.json"
    if not path.exists():
        raise FileNotFoundError(
            f"Contract artifacts not found at {path}. "
            f"Run `pysol-compile` or `python -m pysol.build` first."
        )
    return json.loads(path.read_text())


def _setup_evm():
    """Create a local EVM and deploy compiler + VM contracts."""
    _patch_evm()
    from web3 import Web3
    from eth_tester import EthereumTester
    from eth_tester.backends.pyevm.main import PyEVMBackend

    genesis_params = PyEVMBackend._generate_genesis_params(
        overrides={"gas_limit": 1_000_000_000}
    )
    backend = PyEVMBackend(genesis_parameters=genesis_params)
    tester = EthereumTester(backend=backend)
    w3 = Web3(Web3.EthereumTesterProvider(ethereum_tester=tester))

    compiler_art = _load_artifact("PythonCompiler")
    vm_art = _load_artifact("VM")

    sender = w3.eth.accounts[0]
    gas = 1_000_000_000

    # Deploy PythonCompiler
    Compiler = w3.eth.contract(abi=compiler_art["abi"], bytecode=compiler_art["bytecode"])
    tx_hash = Compiler.constructor().transact({"from": sender, "gas": gas})
    receipt = w3.eth.get_transaction_receipt(tx_hash)
    compiler = w3.eth.contract(address=receipt["contractAddress"], abi=compiler_art["abi"])

    # Deploy VM
    VM = w3.eth.contract(abi=vm_art["abi"], bytecode=vm_art["bytecode"])
    tx_hash = VM.constructor().transact({"from": sender, "gas": gas})
    receipt = w3.eth.get_transaction_receipt(tx_hash)
    vm = w3.eth.contract(address=receipt["contractAddress"], abi=vm_art["abi"])

    return w3, compiler, vm, sender, gas


def _decode_output(w3, receipt) -> str:
    """Decode Print and PrintString events from transaction receipt."""
    print_topic = w3.keccak(text="Print(uint256[])").hex()
    print_str_topic = w3.keccak(text="PrintString(string)").hex()

    parts = []
    for log in receipt["logs"]:
        topic0 = log["topics"][0].hex()
        if topic0 == print_topic:
            decoded = w3.codec.decode(["uint256[]"], log["data"])
            for v in decoded[0]:
                parts.append(str(v))
        elif topic0 == print_str_topic:
            decoded = w3.codec.decode(["string"], log["data"])
            parts.append(decoded[0])

    return "\n".join(parts)


def run(source: str, *, verbose: bool = False) -> str:
    """Compile and execute Python source, return printed output."""
    w3, compiler, vm, sender, gas = _setup_evm()

    if verbose:
        print(f"[solpython] Compiling {len(source)} chars of Python...")

    bytecode = compiler.functions.compile(source).call({"from": sender, "gas": gas})

    if verbose:
        print(f"[solpython] Generated {len(bytecode)} bytes of bytecode")

    tx_hash = vm.functions.execute(bytecode).transact({"from": sender, "gas": gas})
    receipt = w3.eth.get_transaction_receipt(tx_hash)

    return _decode_output(w3, receipt)


def run_with_imports(source: str, modules: dict[str, str], *, verbose: bool = False) -> str:
    """Compile and execute Python source with imported modules."""
    w3, compiler, vm, sender, gas = _setup_evm()

    names = list(modules.keys())
    sources = [modules[n] for n in names]

    bytecode = compiler.functions.compileWithImports(source, names, sources).call(
        {"from": sender, "gas": gas}
    )

    tx_hash = vm.functions.execute(bytecode).transact({"from": sender, "gas": gas})
    receipt = w3.eth.get_transaction_receipt(tx_hash)

    return _decode_output(w3, receipt)
