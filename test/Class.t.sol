// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Lexer} from "../src/phases/Lexer.sol";
import {Parser} from "../src/phases/Parser.sol";
import {SemanticAnalyzer} from "../src/phases/SemanticAnalyzer.sol";
import {CodeGenerator} from "../src/phases/CodeGenerator.sol";
import {VM} from "../src/phases/VM.sol";

contract ClassTest is Test {
    event Print(uint256[] values);
    event PrintString(string value);

    function _compile(string memory src) internal returns (bytes memory) {
        Lexer lexer = new Lexer();
        lexer.tokenize(src);
        Parser parser = new Parser();
        parser.parse(lexer);
        SemanticAnalyzer analyzer = new SemanticAnalyzer();
        analyzer.analyze(parser);
        CodeGenerator gen = new CodeGenerator();
        return gen.generate(parser);
    }

    function _run(string memory src) internal returns (VM) {
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();
        pyVm.execute(bytecode);
        return pyVm;
    }

    function _getLastPrint() internal returns (uint256) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 printTopic = keccak256("Print(uint256[])");
        for (uint256 i = logs.length; i > 0; i--) {
            if (logs[i - 1].topics[0] == printTopic) {
                uint256[] memory vals = abi.decode(logs[i - 1].data, (uint256[]));
                return vals[0];
            }
        }
        return type(uint256).max;
    }

    // ==================== Basic Class Tests ====================

    function testClassDefinition() public {
        // Class definition should compile and execute without error
        string memory src = "class Foo:\n    pass\n";
        _run(src);
    }

    function testInstantiation() public {
        // Instantiation should create an instance
        string memory src = "class Foo:\n    pass\nobj = Foo()\n";
        _run(src);
    }

    function testInitCalled() public {
        // __init__ should be called on instantiation
        string memory src = "class Foo:\n    def __init__(self):\n        self.x = 42\nobj = Foo()\nprint(obj.x)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 42, "__init__ should set self.x = 42");
    }

    function testSelfStoreAttr() public {
        // self.x = val should store attribute
        string memory src = "class Foo:\n    def __init__(self, v):\n        self.v = v\nobj = Foo(100)\nprint(obj.v)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 100, "self.v should be 100");
    }

    function testSelfLoadAttr() public {
        // self.x should read attribute
        string memory src = "class Foo:\n    def __init__(self):\n        self.x = 42\n    def get_x(self):\n        return self.x\nobj = Foo()\nprint(obj.get_x())\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 42, "self.x should read 42");
    }

    // ==================== Method Tests ====================

    function testMethodCall() public {
        // obj.method() should work
        string memory src = "class Foo:\n    def bar(self):\n        return 1\nobj = Foo()\nprint(obj.bar())\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 1, "obj.bar() should return 1");
    }

    function testMethodCallWithArgs() public {
        // obj.method(a, b) should work
        string memory src = "class Foo:\n    def add(self, a, b):\n        return a + b\nobj = Foo()\nprint(obj.add(3, 4))\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 7, "obj.add(3, 4) should return 7");
    }

    function testTwoInstancesIndependent() public {
        // Two instances should have independent attributes
        string memory src = "class Foo:\n    def __init__(self, v):\n        self.v = v\na = Foo(1)\nb = Foo(2)\nprint(a.v)\nprint(b.v)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 printTopic = keccak256("Print(uint256[])");
        uint256[] memory results = new uint256[](2);
        uint256 idx = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == printTopic && idx < 2) {
                uint256[] memory vals = abi.decode(logs[i].data, (uint256[]));
                results[idx] = vals[0];
                idx++;
            }
        }
        assertEq(results[0], 1, "a.v should be 1");
        assertEq(results[1], 2, "b.v should be 2");
    }

    function testClassNoInit() public {
        // Class with no __init__ should still be instantiable
        string memory src = "class Foo:\n    pass\nobj = Foo()\nprint(1)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 1, "Class with no __init__ should work");
    }

    function testInitAttributeReadable() public {
        // Attribute set in __init__ should be readable after construction
        string memory src = "class Foo:\n    def __init__(self):\n        self.x = 42\nobj = Foo()\nprint(obj.x)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 42, "Attribute from __init__ should be readable");
    }

    function testMethodCallsAnotherMethod() public {
        // Method should be able to call another method via self
        string memory src = "class Foo:\n    def a(self):\n        return 10\n    def b(self):\n        return self.a()\nobj = Foo()\nprint(obj.b())\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 10, "self.a() should return 10");
    }

    // ==================== Inheritance Tests ====================

    function testBasicInheritance() public {
        // Child should inherit method from Parent
        string memory src = "class Parent:\n    def greet(self):\n        return 1\nclass Child(Parent):\n    pass\nobj = Child()\nprint(obj.greet())\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 1, "Child should inherit greet from Parent");
    }

    function testChildOverridesParent() public {
        // Child method should override parent method
        string memory src = "class Parent:\n    def greet(self):\n        return 1\nclass Child(Parent):\n    def greet(self):\n        return 2\nobj = Child()\nprint(obj.greet())\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 2, "Child.greet() should override Parent.greet()");
    }

    // ==================== Advanced Tests ====================

    function testIsInstanceCheck() public {
        // Verify instance has attributes (isinstance-like check)
        string memory src = "class Foo:\n    def __init__(self):\n        self.x = 1\nobj = Foo()\nobj.y = 2\nprint(obj.x + obj.y)\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 3, "Instance should support multiple attributes");
    }

    function testCounterClass() public {
        // Counter class with increment and get_count
        string memory src = "class Counter:\n    def __init__(self):\n        self.count = 0\n    def increment(self):\n        self.count = self.count + 1\n    def get_count(self):\n        return self.count\nc = Counter()\nc.increment()\nc.increment()\nc.increment()\nprint(c.get_count())\n";
        bytes memory bytecode = _compile(src);
        VM pyVm = new VM();

        vm.recordLogs();
        pyVm.execute(bytecode);

        assertEq(_getLastPrint(), 3, "Counter should be 3 after 3 increments");
    }
}
