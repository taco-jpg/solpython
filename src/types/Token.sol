// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

enum TokenType {
    // Literals
    INTEGER,
    FLOAT,
    STRING,
    BOOL_TRUE,
    BOOL_FALSE,
    NONE_VAL,

    // Identifiers
    IDENTIFIER,

    // Keywords
    KW_DEF,
    KW_RETURN,
    KW_IF,
    KW_ELSE,
    KW_ELIF,
    KW_WHILE,
    KW_FOR,
    KW_IN,
    KW_PASS,
    KW_BREAK,
    KW_CONTINUE,
    KW_IMPORT,
    KW_FROM,
    KW_CLASS,
    KW_AND,
    KW_OR,
    KW_NOT,
    KW_IS,
    KW_LAMBDA,
    KW_PRINT,
    KW_TRY,
    KW_EXCEPT,
    KW_FINALLY,
    KW_RAISE,

    // Arithmetic operators
    OP_PLUS,       // +
    OP_MINUS,      // -
    OP_STAR,       // *
    OP_SLASH,      // /
    OP_DSLASH,     // //
    OP_PERCENT,    // %
    OP_DSTAR,      // **
    OP_ASSIGN,     // =

    // Augmented assignment
    OP_PLUS_ASSIGN,   // +=
    OP_MINUS_ASSIGN,  // -=
    OP_STAR_ASSIGN,   // *=
    OP_SLASH_ASSIGN,  // /=

    // Comparison operators
    OP_EQ,         // ==
    OP_NEQ,        // !=
    OP_LT,         // <
    OP_GT,         // >
    OP_LTE,        // <=
    OP_GTE,        // >=

    // Delimiters
    LPAREN,        // (
    RPAREN,        // )
    LBRACKET,      // [
    RBRACKET,      // ]
    LBRACE,        // {
    RBRACE,        // }
    COMMA,         // ,
    COLON,         // :
    DOT,           // .
    SEMICOLON,     // ;

    // Special tokens
    NEWLINE,
    INDENT,
    DEDENT,
    EOF,

    // F-string
    FSTRING,

    // Error
    ERROR
}

struct Token {
    TokenType tokenType;
    string lexeme;
    uint256 intValue;     // For integer literals
    uint256 line;
    uint256 column;
}
