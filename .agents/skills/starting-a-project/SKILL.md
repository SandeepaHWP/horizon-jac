---
name: starting-a-project
description: Use when creating a new Jac project or adding structure to a loose .jac file: from an empty directory to a project with jac.toml and archwire.jac, modules with impl and test annexes, lint and format settings, that checks, builds, tests and formats with neojac.
---
# Starting a neojac project

## When to use this

Use it to start a project from nothing, or to turn one `.jac` file into a project that has tests and settings. It assumes `writing-jac`. A project whose code runs in several places (a server and a browser, a CPython space) declares its spaces in the same `archwire.jac`: continue in `building-an-app` once the layout below is in place. Python packages are `using-python-packages`.

## Before you start

```sh
neojac docs toolchain/projects     # what makes a project, the layout, what neojac writes
neojac docs reference/jac-toml     # every key of jac.toml
```

## Steps

### 1. Make the directory and its jac.toml

The directory that holds `jac.toml` is the project's root: neojac reads its settings there, imports stop climbing there, and neojac keeps what it makes in `.jac/` there.

```sh
mkdir shelf && cd shelf
```

`jac.toml`:

```toml
[project]
name = "shelf"

[check.lint]
ignore = ["strip-comments", "strip-docstrings"]

[test]
directories = ["."]
```

- `[project]` names the project. Its `exclude` lists what in the tree is not the project's source (`neojac docs toolchain/projects`).
- `[check.lint]` chooses the lint rules `neojac check` reports. With none named they are `"clean"`, and that is intended: the style rules, every body in an `impl` in `impl/`, and no comment or docstring, where `neojac fmt --fix` takes the code. This project keeps its comments and docstrings, so it ignores the two rules that strip them; choose other rules by name from `neojac docs toolchain/lint`.
- `[test] directories` is where `neojac test` looks when it is given no paths.
- Add `[fmt] exclude = ["gen/*"]` for generated code or programs meant not to compile.

### 2. Write a module as declarations, with an impl annex

A module that other modules use reads best as its declarations and docstrings, with the bodies in its annex `impl/<module>.impl.jac`. The annex is part of the module: it sees the module's imports and names without importing them.

`store.jac`:

<!-- example: not checked: one module of a project; its bodies are in impl/store.impl.jac -->
```jac
"""A shelf of items and their counts."""

obj Shelf {
    has counts: dict[str, int] = {};

    """Add `n` of `name`."""
    def add(name: str, n: int = 1);

    """How many of `name` there are."""
    def count(name: str) -> int;

    """Every name, most stocked first."""
    def ranked -> list[str];
}
```

`impl/store.impl.jac`, each impl restating its declaration's signature exactly:

<!-- example: not checked: the impl annex of store.jac above -->
```jac
impl Shelf.add(name: str, n: int = 1) {
    self.counts[name] = self.counts.get(name, 0) + n;
}

impl Shelf.count(name: str) -> int {
    return self.counts.get(name, 0);
}

impl Shelf.ranked -> list[str] {
    return sorted(self.counts.keys(), key=lambda (k: str) -> int { -self.counts[k] });
}
```

If you write the impls in the module first, `neojac fmt --fix .` moves them into `impl/` under `impls-in-annex`.

### 3. Write the tests in a test annex

`store.test.jac` beside the module, or `test/store.test.jac`. It sees the module's names without importing them, and a build leaves it out.

<!-- example: not checked: the test annex of store.jac above -->
```jac
test "an empty shelf counts nothing" {
    assert Shelf().count("pen") == 0;
}

test "adds accumulate" {
    s = Shelf();
    s.add("pen");
    s.add("pen", 2);
    assert s.count("pen") == 3;
}
```

### 4. Write the main module, and wire it to what it uses

`main.jac`, the program's entry. It writes no import of `store`: a project's modules take their imports of each other from the project's `archwire.jac`.

<!-- example: not checked: a module of the project above, wired `Shelf` by its archwire.jac -->
```jac
with entry {
    s = Shelf();
    s.add("pen", 3);
    s.add("ink");
    print(s.ranked(), s.count("pen"));
}
```

`archwire.jac`, at the root, puts every module in a layer and states each import as a wire:

<!-- example: not checked: a graph layers block is valid only in a file named archwire.jac, beside the modules it groups -->
```jac
graph layers {
    """The shelf, and the program that fills it."""
    layer shelf { main | store; }
}

graph import {
    store ++> main { Shelf }
}
```

- Every project has one, and every command holds the whole project to it: a module in no layer is E2201, and an import of a project module written in a module is E1144, which gives the wire to add.
- A subdirectory is a dotted path: `lib/money.jac` is `lib.money`, as in `lib.money ++> main { Price }`.
- Imports of anything else stay in the module: `import os;`, a Python or npm package.
- Wires between two layers need an edge rule (`neojac docs language/modules-layers`). One layer needs none, which is enough to start.
- `neojac arch` draws the project from it.

### 5. Ignore what neojac writes

`.gitignore`:

```text
.jac/
dist/
```

`.jac/` holds build records, the test runners in `.jac/test/<platform>/`, and the Python environment; `dist/` holds apps' artifacts. Both are made again by the commands. Compiled code lives in a cache outside the project (`neojac docs toolchain/cache`). Commit `jac.lock` if one appears.

## What a correct result looks like

Run from the root:

```sh
neojac check main.jac                 # quiet, status 0: main and what it imports, with lint
neojac check store.jac                # quiet: store's own tests are checked here, not from main
neojac build main.jac -o shelf && ./shelf
neojac test                           # every module with tests under [test] directories
neojac fmt --check .                  # quiet, status 0
```

```text
['pen', 'ink'] 3
neojac test: 1 module with tests, 1 to build, on macos-aarch64
store.jac: 2 passed

2 passed; 1 of 1 module passed in 0.53s
```

## Mistakes to expect

| Symptom | Cause | Fix |
|---|---|---|
| E2087 | A declaration with no body: the annex is missing or misnamed | `impl/<module>.impl.jac`, named after the module |
| W3010 | An impl's signature differs from its declaration's | Copy the declaration's signature |
| E2016, E2017 | An impl for a body written inline, or a second impl | One body per declaration |
| W3056 `[impls-in-annex]` | An impl in the module, or an annex beside it | `neojac fmt --fix .` |
| E2231 | The project has no `archwire.jac` | Write it at the root (step 4) |
| E1144 | A module imports another module of the project | Delete the import and add the wire the message gives to `archwire.jac` |
| E2201 | A module, or a `.py` or `.js` file, that no layer names | Name it in a layer, or list what is not source under `[project] exclude` |
| E1146 | A wire brings a name its module never uses | Remove the name from the wire |
| W1100 | An import names no module | Check the name, and that the file is under the root |
| `no tests found`, status 5 | Nothing under the paths has a `test` block | Check `[test] directories`, or name the module |
| A setting seems ignored | It is in a `jac.toml` that is not the root's | One `jac.toml`, at the top |
| A test annex's error not reported by `check main.jac` | Only the main module's tests are checked | `neojac check store.jac` or `neojac test` |

## Where to look things up

| Question | Command |
|---|---|
| Project layout, annexes, variants, `.jac/` | `neojac docs toolchain/projects` |
| Every `jac.toml` key | `neojac docs reference/jac-toml` |
| Impl blocks and annex file names | `neojac docs language/impl` |
| Imports, packages, how a module is found | `neojac docs language/modules` |
| The lint rules to select | `neojac docs toolchain/lint` |
| Tests and `neojac test` | `neojac docs language/tests`, `neojac docs toolchain/test` |
| Layers and wires (`archwire.jac`) | `neojac docs language/modules-wiring` |
| Spaces and apps (`archwire.jac`) | `neojac docs apps/index` |
