# Mini Lexer — Minimal Python lexer for bootstrap testing
# Handles only: integers, identifiers, +, -, *, /, =, (, ), newline

def mini_tokenize(source):
    tokens = []
    pos = 0
    src_len = len(source)

    while pos < src_len:
        c = source[pos]

        if c == " ":
            pos += 1
            continue

        if c == "\n":
            tokens.append(55)
            pos += 1
            continue

        if c >= "0" and c <= "9":
            start = pos
            while pos < src_len and source[pos] >= "0" and source[pos] <= "9":
                pos += 1
            tokens.append(0)
            continue

        if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_":
            start = pos
            while pos < src_len and ((source[pos] >= "a" and source[pos] <= "z") or (source[pos] >= "A" and source[pos] <= "Z") or (source[pos] >= "0" and source[pos] <= "9") or source[pos] == "_"):
                pos += 1
            tokens.append(6)
            continue

        if c == "+":
            tokens.append(27)
            pos += 1
            continue

        if c == "-":
            tokens.append(28)
            pos += 1
            continue

        if c == "*":
            tokens.append(29)
            pos += 1
            continue

        if c == "/":
            tokens.append(30)
            pos += 1
            continue

        if c == "=":
            tokens.append(34)
            pos += 1
            continue

        if c == "(":
            tokens.append(45)
            pos += 1
            continue

        if c == ")":
            tokens.append(46)
            pos += 1
            continue

        if c == "[":
            tokens.append(47)
            pos += 1
            continue

        if c == "]":
            tokens.append(48)
            pos += 1
            continue

        if c == ",":
            tokens.append(51)
            pos += 1
            continue

        if c == ":":
            tokens.append(52)
            pos += 1
            continue

        tokens.append(59)
        pos += 1

    tokens.append(58)
    return tokens
