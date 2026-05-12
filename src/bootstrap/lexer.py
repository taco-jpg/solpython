# Python Lexer — Self-hosting bootstrap
# This lexer is written in the subset of Python that the Solidity compiler supports.
# It tokenizes Python source code into a list of tokens.
# Each token is a list: [type, lexeme, line, column]

# Token type constants (matching Token.sol enum order)
T_INTEGER = 0
T_FLOAT = 1
T_STRING = 2
T_BOOL_TRUE = 3
T_BOOL_FALSE = 4
T_NONE_VAL = 5
T_IDENTIFIER = 6
T_KW_DEF = 7
T_KW_RETURN = 8
T_KW_IF = 9
T_KW_ELSE = 10
T_KW_ELIF = 11
T_KW_WHILE = 12
T_KW_FOR = 13
T_KW_IN = 14
T_KW_PASS = 15
T_KW_BREAK = 16
T_KW_CONTINUE = 17
T_KW_IMPORT = 18
T_KW_FROM = 19
T_KW_CLASS = 20
T_KW_AND = 21
T_KW_OR = 22
T_KW_NOT = 23
T_KW_IS = 24
T_KW_LAMBDA = 25
T_KW_PRINT = 26
T_OP_PLUS = 27
T_OP_MINUS = 28
T_OP_STAR = 29
T_OP_SLASH = 30
T_OP_DSLASH = 31
T_OP_PERCENT = 32
T_OP_DSTAR = 33
T_OP_ASSIGN = 34
T_OP_PLUS_ASSIGN = 35
T_OP_MINUS_ASSIGN = 36
T_OP_STAR_ASSIGN = 37
T_OP_SLASH_ASSIGN = 38
T_OP_EQ = 39
T_OP_NEQ = 40
T_OP_LT = 41
T_OP_GT = 42
T_OP_LTE = 43
T_OP_GTE = 44
T_LPAREN = 45
T_RPAREN = 46
T_LBRACKET = 47
T_RBRACKET = 48
T_LBRACE = 49
T_RBRACE = 50
T_COMMA = 51
T_COLON = 52
T_DOT = 53
T_SEMICOLON = 54
T_NEWLINE = 55
T_INDENT = 56
T_DEDENT = 57
T_EOF = 58
T_ERROR = 59


def is_alpha(c):
    return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"


def is_digit(c):
    return c >= "0" and c <= "9"


def is_alnum(c):
    return is_alpha(c) or is_digit(c)


def keyword_type(word):
    if word == "def":
        return T_KW_DEF
    if word == "return":
        return T_KW_RETURN
    if word == "if":
        return T_KW_IF
    if word == "else":
        return T_KW_ELSE
    if word == "elif":
        return T_KW_ELIF
    if word == "while":
        return T_KW_WHILE
    if word == "for":
        return T_KW_FOR
    if word == "in":
        return T_KW_IN
    if word == "pass":
        return T_KW_PASS
    if word == "break":
        return T_KW_BREAK
    if word == "continue":
        return T_KW_CONTINUE
    if word == "import":
        return T_KW_IMPORT
    if word == "from":
        return T_KW_FROM
    if word == "class":
        return T_KW_CLASS
    if word == "and":
        return T_KW_AND
    if word == "or":
        return T_KW_OR
    if word == "not":
        return T_KW_NOT
    if word == "is":
        return T_KW_IS
    if word == "lambda":
        return T_KW_LAMBDA
    if word == "print":
        return T_KW_PRINT
    if word == "True":
        return T_BOOL_TRUE
    if word == "False":
        return T_BOOL_FALSE
    if word == "None":
        return T_NONE_VAL
    return T_IDENTIFIER


def tokenize(source):
    tokens = []
    pos = 0
    line = 1
    col = 1
    indent_stack = [0]
    src_len = len(source)

    while pos < src_len:
        c = source[pos]

        # Skip spaces and tabs (not at start of line)
        if c == " " or c == "\t":
            pos += 1
            col += 1
            continue

        # Skip comments
        if c == "#":
            while pos < src_len and source[pos] != "\n":
                pos += 1
            continue

        # Newline
        if c == "\n":
            tokens.append([T_NEWLINE, "\\n", line, col])
            pos += 1
            line += 1
            col = 1

            # Handle indentation
            indent = 0
            while pos < src_len and source[pos] == " ":
                indent += 1
                pos += 1

            # Skip blank lines
            if pos < src_len and source[pos] == "\n":
                continue
            if pos >= src_len:
                continue

            if indent > indent_stack[len(indent_stack) - 1]:
                indent_stack.append(indent)
                tokens.append([T_INDENT, "", line, 1])
            else:
                while indent < indent_stack[len(indent_stack) - 1]:
                    indent_stack.pop()
                    tokens.append([T_DEDENT, "", line, 1])
            col = indent + 1
            continue

        # Numbers
        if is_digit(c):
            start = pos
            while pos < src_len and is_digit(source[pos]):
                pos += 1
            lexeme = source[start:pos]
            tokens.append([T_INTEGER, lexeme, line, col])
            col += pos - start
            continue

        # Identifiers and keywords
        if is_alpha(c):
            start = pos
            while pos < src_len and is_alnum(source[pos]):
                pos += 1
            word = source[start:pos]
            tt = keyword_type(word)
            tokens.append([tt, word, line, col])
            col += pos - start
            continue

        # String literals
        if c == '"' or c == "'":
            quote = c
            start = pos
            pos += 1
            col += 1
            while pos < src_len and source[pos] != quote:
                if source[pos] == "\\":
                    pos += 1
                    col += 1
                pos += 1
                col += 1
            if pos < src_len:
                pos += 1
                col += 1
            lexeme = source[start:pos]
            tokens.append([T_STRING, lexeme, line, col])
            continue

        # Two-character operators
        if pos + 1 < src_len:
            two = source[pos:pos + 2]
            if two == "==":
                tokens.append([T_OP_EQ, "==", line, col])
                pos += 2
                col += 2
                continue
            if two == "!=":
                tokens.append([T_OP_NEQ, "!=", line, col])
                pos += 2
                col += 2
                continue
            if two == "<=":
                tokens.append([T_OP_LTE, "<=", line, col])
                pos += 2
                col += 2
                continue
            if two == ">=":
                tokens.append([T_OP_GTE, ">=", line, col])
                pos += 2
                col += 2
                continue
            if two == "**":
                tokens.append([T_OP_DSTAR, "**", line, col])
                pos += 2
                col += 2
                continue
            if two == "//":
                tokens.append([T_OP_DSLASH, "//", line, col])
                pos += 2
                col += 2
                continue
            if two == "+=":
                tokens.append([T_OP_PLUS_ASSIGN, "+=", line, col])
                pos += 2
                col += 2
                continue
            if two == "-=":
                tokens.append([T_OP_MINUS_ASSIGN, "-=", line, col])
                pos += 2
                col += 2
                continue
            if two == "*=":
                tokens.append([T_OP_STAR_ASSIGN, "*=", line, col])
                pos += 2
                col += 2
                continue
            if two == "/=":
                tokens.append([T_OP_SLASH_ASSIGN, "/=", line, col])
                pos += 2
                col += 2
                continue

        # Single-character operators
        if c == "+":
            tokens.append([T_OP_PLUS, "+", line, col])
            pos += 1
            col += 1
            continue
        if c == "-":
            tokens.append([T_OP_MINUS, "-", line, col])
            pos += 1
            col += 1
            continue
        if c == "*":
            tokens.append([T_OP_STAR, "*", line, col])
            pos += 1
            col += 1
            continue
        if c == "/":
            tokens.append([T_OP_SLASH, "/", line, col])
            pos += 1
            col += 1
            continue
        if c == "%":
            tokens.append([T_OP_PERCENT, "%", line, col])
            pos += 1
            col += 1
            continue
        if c == "=":
            tokens.append([T_OP_ASSIGN, "=", line, col])
            pos += 1
            col += 1
            continue
        if c == "<":
            tokens.append([T_OP_LT, "<", line, col])
            pos += 1
            col += 1
            continue
        if c == ">":
            tokens.append([T_OP_GT, ">", line, col])
            pos += 1
            col += 1
            continue
        if c == "(":
            tokens.append([T_LPAREN, "(", line, col])
            pos += 1
            col += 1
            continue
        if c == ")":
            tokens.append([T_RPAREN, ")", line, col])
            pos += 1
            col += 1
            continue
        if c == "[":
            tokens.append([T_LBRACKET, "[", line, col])
            pos += 1
            col += 1
            continue
        if c == "]":
            tokens.append([T_RBRACKET, "]", line, col])
            pos += 1
            col += 1
            continue
        if c == "{":
            tokens.append([T_LBRACE, "{", line, col])
            pos += 1
            col += 1
            continue
        if c == "}":
            tokens.append([T_RBRACE, "}", line, col])
            pos += 1
            col += 1
            continue
        if c == ",":
            tokens.append([T_COMMA, ",", line, col])
            pos += 1
            col += 1
            continue
        if c == ":":
            tokens.append([T_COLON, ":", line, col])
            pos += 1
            col += 1
            continue
        if c == ".":
            tokens.append([T_DOT, ".", line, col])
            pos += 1
            col += 1
            continue
        if c == ";":
            tokens.append([T_SEMICOLON, ";", line, col])
            pos += 1
            col += 1
            continue

        # Unknown character
        tokens.append([T_ERROR, c, line, col])
        pos += 1
        col += 1

    # Emit trailing DEDENTs
    while len(indent_stack) > 1:
        indent_stack.pop()
        tokens.append([T_DEDENT, "", line, col])

    tokens.append([T_EOF, "", line, col])
    return tokens


def token_type_name(tt):
    if tt == T_INTEGER:
        return "INTEGER"
    if tt == T_IDENTIFIER:
        return "IDENTIFIER"
    if tt == T_STRING:
        return "STRING"
    if tt == T_KW_DEF:
        return "KW_DEF"
    if tt == T_KW_RETURN:
        return "KW_RETURN"
    if tt == T_KW_IF:
        return "KW_IF"
    if tt == T_KW_ELSE:
        return "KW_ELSE"
    if tt == T_KW_WHILE:
        return "KW_WHILE"
    if tt == T_KW_FOR:
        return "KW_FOR"
    if tt == T_KW_IN:
        return "KW_IN"
    if tt == T_KW_PRINT:
        return "KW_PRINT"
    if tt == T_OP_PLUS:
        return "OP_PLUS"
    if tt == T_OP_MINUS:
        return "OP_MINUS"
    if tt == T_OP_STAR:
        return "OP_STAR"
    if tt == T_OP_ASSIGN:
        return "OP_ASSIGN"
    if tt == T_OP_EQ:
        return "OP_EQ"
    if tt == T_LPAREN:
        return "LPAREN"
    if tt == T_RPAREN:
        return "RPAREN"
    if tt == T_LBRACKET:
        return "LBRACKET"
    if tt == T_RBRACKET:
        return "RBRACKET"
    if tt == T_COMMA:
        return "COMMA"
    if tt == T_COLON:
        return "COLON"
    if tt == T_NEWLINE:
        return "NEWLINE"
    if tt == T_INDENT:
        return "INDENT"
    if tt == T_DEDENT:
        return "DEDENT"
    if tt == T_EOF:
        return "EOF"
    if tt == T_BOOL_TRUE:
        return "BOOL_TRUE"
    if tt == T_BOOL_FALSE:
        return "BOOL_FALSE"
    if tt == T_NONE_VAL:
        return "NONE_VAL"
    if tt == T_KW_IMPORT:
        return "KW_IMPORT"
    if tt == T_KW_FROM:
        return "KW_FROM"
    if tt == T_KW_CLASS:
        return "KW_CLASS"
    if tt == T_KW_AND:
        return "KW_AND"
    if tt == T_KW_OR:
        return "KW_OR"
    if tt == T_KW_NOT:
        return "KW_NOT"
    if tt == T_KW_BREAK:
        return "KW_BREAK"
    if tt == T_KW_CONTINUE:
        return "KW_CONTINUE"
    if tt == T_KW_PASS:
        return "KW_PASS"
    if tt == T_KW_ELIF:
        return "KW_ELIF"
    return "UNKNOWN"
