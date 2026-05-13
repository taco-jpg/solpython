# Backend Limitations

## Solidity Backend

- Generated Solidity code is not verified by compiling it within the test suite
- No end-to-end test that deploys and executes the generated Solidity contract
- String handling is limited — generated code uses raw string literals
- No support for importing external contracts or libraries in generated code

## Yul Backend

- Generated Yul IR is not verified by compiling it within the test suite
- No end-to-end test that assembles and executes the generated Yul code
- Function definitions are inlined into the code block (no separate function objects)
- Memory management for lists uses raw mload/mstore without free memory pointer
