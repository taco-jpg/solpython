// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Lexer} from "./phases/Lexer.sol";
import {Parser} from "./phases/Parser.sol";
import {SemanticAnalyzer} from "./phases/SemanticAnalyzer.sol";
import {ConstantFolder} from "./optimizer/ConstantFolder.sol";
import {CodeGenerator} from "./phases/CodeGenerator.sol";
import {SolidityBackend} from "./phases/SolidityBackend.sol";
import {VM} from "./phases/VM.sol";

contract PythonCompiler {
    event Print(uint256[] values);
    event Result(uint256 value);

    // Error storage for getErrors()
    string[] private errors;

    function compile(string memory source) public returns (bytes memory) {
        errors = new string[](0); // reset errors

        Lexer lexer = new Lexer();
        lexer.tokenize(source);

        Parser parser = new Parser();
        parser.parse(lexer);

        SemanticAnalyzer analyzer = new SemanticAnalyzer();
        analyzer.analyze(parser);

        // Collect semantic errors
        uint256 errCount = analyzer.getErrorCount();
        for (uint256 i = 0; i < errCount; i++) {
            errors.push(string(abi.encodePacked("[Semantic] ", analyzer.getError(i))));
        }

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

    function compileToSolidity(string memory source) public returns (string memory) {
        errors = new string[](0);

        Lexer lexer = new Lexer();
        lexer.tokenize(source);

        Parser parser = new Parser();
        parser.parse(lexer);

        SemanticAnalyzer analyzer = new SemanticAnalyzer();
        analyzer.analyze(parser);

        uint256 errCount = analyzer.getErrorCount();
        for (uint256 i = 0; i < errCount; i++) {
            errors.push(string(abi.encodePacked("[Semantic] ", analyzer.getError(i))));
        }

        SolidityBackend backend = new SolidityBackend();
        return backend.generate(parser);
    }

    function getErrors() public view returns (string[] memory) {
        return errors;
    }
}
