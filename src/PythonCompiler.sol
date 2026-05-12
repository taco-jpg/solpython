// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Lexer} from "./phases/Lexer.sol";
import {Parser} from "./phases/Parser.sol";
import {SemanticAnalyzer} from "./phases/SemanticAnalyzer.sol";
import {ConstantFolder} from "./optimizer/ConstantFolder.sol";
import {CodeGenerator} from "./phases/CodeGenerator.sol";
import {VM} from "./phases/VM.sol";

contract PythonCompiler {
    event Print(uint256[] values);
    event Result(uint256 value);

    function compile(string memory source) public returns (bytes memory) {
        Lexer lexer = new Lexer();
        lexer.tokenize(source);

        Parser parser = new Parser();
        parser.parse(lexer);

        SemanticAnalyzer analyzer = new SemanticAnalyzer();
        analyzer.analyze(parser);

        ConstantFolder folder = new ConstantFolder();
        folder.fold(parser);

        CodeGenerator gen = new CodeGenerator();
        return gen.generate(parser);
    }

    function compileAndExecute(string memory source) public returns (uint256) {
        bytes memory bytecode = compile(source);

        VM vm = new VM();
        vm.execute(bytecode);

        return 0;
    }
}
