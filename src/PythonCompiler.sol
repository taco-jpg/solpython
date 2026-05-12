// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Lexer} from "./phases/Lexer.sol";
import {Parser} from "./phases/Parser.sol";
import {SemanticAnalyzer} from "./phases/SemanticAnalyzer.sol";
import {ConstantFolder} from "./optimizer/ConstantFolder.sol";
import {CodeGenerator} from "./phases/CodeGenerator.sol";
import {SolidityBackend} from "./phases/SolidityBackend.sol";
import {VM} from "./phases/VM.sol";
import {VFS} from "./vfs/VFS.sol";
import {NodeType} from "./types/ASTNode.sol";

contract PythonCompiler {
    event Print(uint256[] values);
    event Result(uint256 value);

    // Error storage for getErrors()
    string[] private errors;

    bytes1 constant B_NEWLINE = bytes1(uint8(0x0a));
    bytes1 constant B_SPACE = bytes1(uint8(0x20));
    bytes1 constant B_HASH = bytes1(uint8(0x23));

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

    /// @notice Compile with imported modules (static linking).
    ///         Imported module function definitions are prepended to the main source.
    function compileWithImports(
        string memory source,
        string[] memory moduleNames,
        string[] memory moduleSources
    ) public returns (bytes memory) {
        errors = new string[](0);

        // Build merged source: imported function defs + main source
        string memory merged = "";

        for (uint256 i = 0; i < moduleNames.length; i++) {
            // Parse each module to extract function definitions
            Lexer modLexer = new Lexer();
            modLexer.tokenize(moduleSources[i]);
            Parser modParser = new Parser();
            modParser.parse(modLexer);

            // Walk top-level statements, extract function defs as source text
            uint256 progAuxStart = modParser.getAuxIndex(0);
            uint256 progAuxCount = modParser.getAuxCount(0);
            for (uint256 j = 0; j < progAuxCount; j++) {
                uint256 stmtIdx = modParser.getAuxData(progAuxStart + j);
                if (modParser.getNodeType(stmtIdx) == NodeType.FUNCTION_DEF) {
                    string memory funcSrc = _extractFuncSource(moduleSources[i], modParser, stmtIdx);
                    merged = string(abi.encodePacked(merged, funcSrc, "\n"));
                }
            }
        }

        // Append main source
        merged = string(abi.encodePacked(merged, source));

        // Compile merged source
        string memory mergedSource = merged;

        Lexer lexer = new Lexer();
        lexer.tokenize(mergedSource);

        Parser parser = new Parser();
        parser.parse(lexer);

        SemanticAnalyzer analyzer = new SemanticAnalyzer();
        analyzer.analyze(parser);

        uint256 errCount = analyzer.getErrorCount();
        for (uint256 i = 0; i < errCount; i++) {
            errors.push(string(abi.encodePacked("[Semantic] ", analyzer.getError(i))));
        }

        ConstantFolder folder = new ConstantFolder();
        folder.fold(parser);

        CodeGenerator gen = new CodeGenerator();
        return gen.generate(parser);
    }

    /// @notice Compile with imports resolved from a VFS.
    ///         Parses source for import statements, reads modules from VFS, compiles with static linking.
    function compileWithVFS(string memory source, VFS vfs) public returns (bytes memory) {
        // Parse source to find import statements
        Lexer lexer = new Lexer();
        lexer.tokenize(source);
        Parser parser = new Parser();
        parser.parse(lexer);

        // Collect module names from IMPORT_STMT nodes
        uint256 progAuxStart = parser.getAuxIndex(0);
        uint256 progAuxCount = parser.getAuxCount(0);

        string[] memory modNames = new string[](progAuxCount);
        string[] memory modSources = new string[](progAuxCount);
        uint256 modCount = 0;

        for (uint256 i = 0; i < progAuxCount; i++) {
            uint256 stmtIdx = parser.getAuxData(progAuxStart + i);
            if (parser.getNodeType(stmtIdx) == NodeType.IMPORT_STMT) {
                string memory modName = parser.getStrValue(stmtIdx);
                // Try reading from VFS: try "modName.py" first, then "modName"
                string memory path = string(abi.encodePacked(modName, ".py"));
                if (vfs.fileExists(path)) {
                    modNames[modCount] = modName;
                    modSources[modCount] = vfs.readFile(path);
                    modCount++;
                } else if (vfs.fileExists(modName)) {
                    modNames[modCount] = modName;
                    modSources[modCount] = vfs.readFile(modName);
                    modCount++;
                }
                // If not found in VFS, skip (will error at compile time if needed)
            }
        }

        // Trim arrays to actual count
        string[] memory names = new string[](modCount);
        string[] memory sources = new string[](modCount);
        for (uint256 i = 0; i < modCount; i++) {
            names[i] = modNames[i];
            sources[i] = modSources[i];
        }

        return compileWithImports(source, names, sources);
    }

    /// @notice Extract a function definition's source text from the original source.
    ///         Uses the lexer's line tracking to find the function's line range.
    function _extractFuncSource(
        string memory source,
        Parser parser,
        uint256 funcNodeIdx
    ) internal view returns (string memory) {
        uint256 funcLine = parser.getLine(funcNodeIdx);

        bytes memory src = bytes(source);
        uint256 line = 1;
        uint256 funcStart = 0;
        bool foundStart = false;

        for (uint256 i = 0; i < src.length; i++) {
            if (line == funcLine && !foundStart) {
                funcStart = i;
                foundStart = true;
            }
            if (src[i] == B_NEWLINE) {
                line++;
            }
        }

        if (!foundStart) return "";

        uint256 indent = 0;
        for (uint256 i = funcStart; i < src.length; i++) {
            if (src[i] == B_SPACE) indent++;
            else break;
        }

        uint256 funcEnd = src.length;

        for (uint256 i = funcStart; i < src.length; i++) {
            if (src[i] == B_NEWLINE) {
                uint256 nextStart = i + 1;
                if (nextStart < src.length) {
                    uint256 nextIndent = 0;
                    for (uint256 j = nextStart; j < src.length; j++) {
                        if (src[j] == B_SPACE) nextIndent++;
                        else break;
                    }
                    if (nextIndent <= indent && nextStart + nextIndent < src.length) {
                        bytes1 firstChar = src[nextStart + nextIndent];
                        if (firstChar != B_NEWLINE && firstChar != B_HASH) {
                            funcEnd = nextStart;
                            break;
                        }
                    }
                }
            }
        }

        uint256 len = funcEnd - funcStart;
        bytes memory result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = src[funcStart + i];
        }
        return string(result);
    }
}
