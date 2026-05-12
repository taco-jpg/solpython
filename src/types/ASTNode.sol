// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

enum NodeType {
    // Program
    PROGRAM,            // Root node, contains statement list

    // Statements
    FUNCTION_DEF,       // def name(params): body
    IF_STATEMENT,       // if cond: body [elif ...] [else: body]
    ELIF_BRANCH,        // elif cond: body
    ELSE_BRANCH,        // else: body
    WHILE_LOOP,         // while cond: body
    FOR_LOOP,           // for var in iterable: body
    ASSIGN,             // var = expr
    AUG_ASSIGN,         // var += expr (etc)
    RETURN_STMT,        // return expr
    PASS_STMT,          // pass
    BREAK_STMT,         // break
    CONTINUE_STMT,      // continue
    EXPR_STMT,          // expression as statement (e.g. function call)
    CLASS_DEF,          // class Name: body
    IMPORT_STMT,        // import module  or  from module import name [, name2, ...]
    TRY_STMT,           // try: body except: handler [finally: cleanup]
    EXCEPT_BRANCH,      // except [Type]: body
    FINALLY_BRANCH,     // finally: body
    RAISE_STMT,         // raise [expr]

    // Expressions
    BINARY_OP,          // a + b, a - b, etc
    UNARY_OP,           // -a, not a
    COMPARISON,         // a == b, a < b, etc
    BOOL_AND,           // a and b
    BOOL_OR,            // a or b
    BOOL_NOT,           // not a
    FUNC_CALL,          // name(args)
    LIST_LITERAL,       // [a, b, c]
    INDEX_ACCESS,       // list[i]

    // Literals
    INT_LITERAL,        // 42
    FLOAT_LITERAL,      // 3.14
    STRING_LITERAL,     // "hello"
    BOOL_LITERAL,       // True, False
    NONE_LITERAL,       // None
    IDENTIFIER_REF,     // variable reference

    // Dict and Set
    DICT_LITERAL,       // {k: v, ...}  exprAux = [k0, v0, k1, v1, ...]
    SET_LITERAL,        // {e, ...}     exprAux = [e0, e1, ...]
    DICT_ACCESS,        // d[key]  child1=dict, child2=key
    DICT_ASSIGN,        // d[key] = val  child1=dict, child2=key, child3=value
    SLICE_ACCESS,       // a[i:j]  child1=target, child2=start, child3=end

    // Class system
    ATTR_ACCESS,        // obj.attr  child1=object, strValue=attribute_name
    METHOD_CALL,        // obj.method(args)  child1=object, strValue=method_name, exprAux=args
    SELF_ASSIGN         // self.x = val  strValue=attr_name, child1=value (inside method body)
}

enum BinaryOpType {
    ADD,    // +
    SUB,    // -
    MUL,    // *
    DIV,    // /
    FDIV,   // //
    MOD,    // %
    POW     // **
}

enum UnaryOpType {
    NEG,    // -
    NOT     // not
}

enum CompOpType {
    EQ,     // ==
    NEQ,    // !=
    LT,     // <
    GT,     // >
    LTE,    // <=
    GTE,    // >=
    IN,     // in
    NOT_IN  // not in
}

enum AugAssignOp {
    PLUS_ASSIGN,    // +=
    MINUS_ASSIGN,   // -=
    STAR_ASSIGN,    // *=
    SLASH_ASSIGN    // /=
}

struct ASTNode {
    NodeType nodeType;
    // Child indices in the AST node array
    uint256 child1;     // Primary child (e.g., condition, left operand, target)
    uint256 child2;     // Secondary child (e.g., body, right operand, value)
    uint256 child3;     // Tertiary child (e.g., else body, step)
    // For nodes that have lists of children (function args, list elements, params):
    // child1 = index in auxiliary array where child indices start
    // child2 = count of children
    uint256 auxIndex;   // Index into auxiliary data array (for extra data)
    uint256 auxCount;   // Count of auxiliary items
    // Literal values
    uint256 intValue;   // For INT_LITERAL, also used for enum subtype values
    string strValue;    // For STRING_LITERAL, IDENTIFIER_REF (name), FUNCTION_DEF (name)
    // Source location
    uint256 line;
    uint256 column;
}
