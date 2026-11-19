"""Writes ErrorList.h from Firefox's xpcom/base/ErrorList.py without running that file.

Gecko's build generates ErrorList.h with error_list_h() in ErrorList.py (xpcom/base/moz.build,
export tier). The site mode build has no Gecko build, so this reads ErrorList.py as data: it
parses the file with the ast module and evaluates only the statement shapes the file uses
(modules["X"] = Mod(n), with modules["X"]:, errors["X"] = <int | errors["Y"] | a + b | a - b |
FAILURE(n) | SUCCESS(n)>, MODULE_BASE_OFFSET = n). Any other shape stops with an error, so a
change in a later Firefox shows up instead of being skipped.

The output is the text error_list_h() writes, byte for byte, with no extra error files
(MOZ_EXTRA_ERROR_DEFINITIONS is not set for iOS). The site mode workflow compares the two on CI.

Usage: python3 -I errorlist_h.py <ErrorList.py> <output ErrorList.h>
"""

import ast
import sys

SEVERITY_SUCCESS = 0
SEVERITY_ERROR = 1


def generate(source_path):
    with open(source_path, encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=source_path)

    modules = {}
    errors = {}
    base_offset = None
    active = [None]

    def key_of(node, name):
        if (
            isinstance(node, ast.Subscript)
            and isinstance(node.value, ast.Name)
            and node.value.id == name
            and isinstance(node.slice, ast.Constant)
            and isinstance(node.slice.value, str)
        ):
            return node.slice.value
        return None

    def evaluate(node):
        if isinstance(node, ast.Constant) and type(node.value) is int:
            return node.value
        key = key_of(node, "errors")
        if key is not None:
            return errors[key]
        if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub)):
            left, right = evaluate(node.left), evaluate(node.right)
            return left + right if isinstance(node.op, ast.Add) else left - right
        if (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id in ("FAILURE", "SUCCESS")
            and len(node.args) == 1
            and not node.keywords
        ):
            if active[0] is None:
                raise SystemExit(f"line {node.lineno}: {node.func.id} outside a module block")
            if base_offset is None:
                raise SystemExit(f"line {node.lineno}: {node.func.id} before MODULE_BASE_OFFSET")
            severity = SEVERITY_ERROR if node.func.id == "FAILURE" else SEVERITY_SUCCESS
            return (severity << 31) | ((active[0] + base_offset) << 16) | evaluate(node.args[0])
        raise SystemExit(f"line {node.lineno}: unsupported expression {ast.dump(node)}")

    def run(statements, top):
        nonlocal base_offset
        for statement in statements:
            if isinstance(statement, ast.Assign) and len(statement.targets) == 1:
                target = statement.targets[0]
                module_key = key_of(target, "modules")
                error_key = key_of(target, "errors")
                if module_key is not None:
                    value = statement.value
                    if not (
                        isinstance(value, ast.Call)
                        and isinstance(value.func, ast.Name)
                        and value.func.id == "Mod"
                        and len(value.args) == 1
                        and not value.keywords
                    ):
                        raise SystemExit(f"line {statement.lineno}: unsupported module line")
                    modules[module_key] = evaluate(value.args[0])
                    continue
                if error_key is not None:
                    errors[error_key] = evaluate(statement.value)
                    continue
                if isinstance(target, ast.Name):
                    if target.id == "MODULE_BASE_OFFSET":
                        base_offset = evaluate(statement.value)
                        continue
                    if target.id in ("NS_ERROR_SEVERITY_SUCCESS", "NS_ERROR_SEVERITY_ERROR"):
                        expected = SEVERITY_SUCCESS if target.id.endswith("SUCCESS") else SEVERITY_ERROR
                        if evaluate(statement.value) != expected:
                            raise SystemExit(f"line {statement.lineno}: {target.id} changed")
                        continue
                    if (
                        target.id in ("modules", "errors")
                        and isinstance(statement.value, ast.Dict)
                        and not statement.value.keys
                    ):
                        continue  # modules = {} and errors = {}
                raise SystemExit(f"line {statement.lineno}: unsupported assignment")
            if isinstance(statement, ast.With) and top:
                module_key = None
                if len(statement.items) == 1 and statement.items[0].optional_vars is None:
                    module_key = key_of(statement.items[0].context_expr, "modules")
                if module_key is None:
                    raise SystemExit(f"line {statement.lineno}: unsupported with statement")
                active[0] = modules[module_key]
                run(statement.body, False)
                active[0] = None
                continue
            if top and isinstance(statement, (ast.Import, ast.ImportFrom, ast.FunctionDef, ast.ClassDef)):
                continue  # the generator functions and the Mod class
            if isinstance(statement, ast.Expr) and isinstance(statement.value, ast.Constant):
                continue  # docstrings
            raise SystemExit(
                f"line {statement.lineno}: unsupported statement {type(statement).__name__}"
            )

    run(tree.body, True)
    if base_offset is None:
        raise SystemExit("no MODULE_BASE_OFFSET")

    # The text of error_list_h() in ErrorList.py.
    out = [
        "\n/* THIS FILE IS GENERATED BY ErrorList.py - DO NOT EDIT */\n\n"
        "#ifndef ErrorList_h__\n#define ErrorList_h__\n\n#include <stdint.h>\n\n",
        f"#define NS_ERROR_MODULE_BASE_OFFSET {base_offset}\n",
    ]
    for module, number in modules.items():
        out.append(f"#define NS_ERROR_MODULE_{module} {number}\n")
    items = [f"  {error} = 0x{value:X}" for error, value in errors.items()]
    out.append("\nenum class nsresult : uint32_t\n{\n" + ",\n".join(items) + "\n};\n\n")
    items = [f"  {error} = nsresult::{error}" for error in errors]
    out.append("\nconst nsresult\n" + ",\n".join(items) + "\n;\n\n#endif // ErrorList_h__\n")
    return "".join(out), len(modules), len(errors)


def main(source_path, output_path):
    text, module_count, error_count = generate(source_path)
    with open(output_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(f"ErrorList.h: {module_count} modules, {error_count} errors")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: errorlist_h.py <ErrorList.py> <output ErrorList.h>")
    main(sys.argv[1], sys.argv[2])
