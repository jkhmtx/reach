# Reach

Extend your grasp!

Reach is a CLI tool that builds a dependency graph of your code.

Reach uses a plugin system to extend support to any language of your choosing, or any AST-adjacent concept you want to rudely jam into its machinery.

From a single entrypoint, Reach walks the dependency graph, crosses language boundaries when necessary (and possible), and builds a graph in memory. It prints the graph to `stdout`. How you use it from there is up to you!

Reach works out of the box for Rust, JavaScript, TypeScript, and Python.

## Usage

### Print a graph to stdout

Flags and options may be supplied in any order, before or after the entrypoint file path.

```shell-session
$ reach [entrypoint file path]
```

Example output for `reach src/main.rs`:

```text
src/graph.rs=data/schema.json
src/main.rs=src/cli.rs
src/main.rs=src/graph.rs
```

Each line is one edge, `from=to`. Paths are relative to the directory of the config file. Output is sorted, so the same input gives the same output.

Reach does not run `cargo`, `node`, `python` or any other toolchain, and it does not use the network. Imports it cannot resolve are printed as placeholder nodes with the specifier as written. Third-party packages are printed as leaf nodes and are not walked.

#### Flags

- `--config <path>`: the config file. The default is `./reach.toml`.
- `--format <format>`: `json`, `tree` or `kvp`. The default is `kvp`.
  - `kvp`: one edge per line, `from=to`.
  - `tree`: an indented tree from the entrypoint. A file that was already printed is shown again with a `(*)` marker and its dependencies are not repeated. This also handles cycles.
  - `json`: a versioned object with `nodes` and `edges` arrays. It is the only format that includes package nodes (crates, npm packages, Python distributions) and their `contains` edges.
- `--depth <n>`: stop the walk `n` edges away from the entrypoint.
- `--strict`: exit with a non-zero code if any import is unresolved.
- `--no-cache`: do not read or write the cache for this run.

## Writing Plugins

A plugin adds a language to Reach. Plugins are declarative: a plugin is a TOML manifest, tree-sitter queries and a tree-sitter grammar compiled to WebAssembly. Plugins do not run code. The built-in Rust, JavaScript, TypeScript and Python support uses the same plugin format.

### Plugin layout

```text
plugins/go/
├── plugin.toml
├── grammar.wasm
└── queries/
    └── imports.scm
```

Register the plugin in `reach.toml` with a path relative to the config file:

```toml
[plugins]
go = "./plugins/go"
```

### Grammar

`grammar.wasm` is a tree-sitter grammar built for WebAssembly:

```shell-session
$ tree-sitter build --wasm --output grammar.wasm path/to/tree-sitter-go
```

### Queries

`queries/imports.scm` is a tree-sitter query. Each `@specifier` capture is one import. Reach removes the quotes around string captures.

```scheme
(import_spec
  path: (interpreted_string_literal) @specifier)
```

### Manifest

`plugin.toml` defines the language, the files it applies to and how to turn a specifier into file paths.

```toml
[language]
name = "go"
extensions = ["go"]
grammar = "grammar.wasm"

[queries]
imports = "queries/imports.scm"

[package]
manifest = "go.mod"
name = { regex = '^module\s+(\S+)' }

[[resolve]]
kind = "import"
strip_prefix = "{package.name}/"
candidates = ["{package.root}/{specifier}/*.go"]

[[resolve]]
kind = "import"
external = true
```

#### `[language]`

- `name`: the language name. It must be unique across loaded plugins.
- `extensions`: file extensions this plugin parses, without the dot.
- `grammar`: path to the `.wasm` grammar, relative to `plugin.toml`.

#### `[queries]`

- `imports`: path to the query file that captures import specifiers.

#### `[package]`

Defines how Reach finds the package that a file belongs to. Reach searches upward from each file for `manifest`. The directory that contains it is the package root.

- `manifest`: the manifest file name.
- `name`: how to read the package name from the manifest. `regex` uses the first capture group. `toml_key` and `json_key` read a dotted key, for example `toml_key = "package.name"`.

#### `[[resolve]]`

Resolve rules are tried in order. The first rule that matches a specifier produces the edges.

- `kind`: the edge kind, one of `import`, `re-export`, `type-only`, `dynamic` or `data`.
- `match`: a regex the specifier must match. If omitted, the rule matches every specifier.
- `strip_prefix`: a prefix to remove from the specifier. If the specifier does not start with it, the rule does not match.
- `candidates`: path templates. Reach tries each one in order and uses the first one that matches at least one file. A glob creates one edge per matched file.
- `external`: if `true`, the specifier becomes an external leaf node and is not walked.

A specifier that matches no rule becomes a placeholder node.

Templates support these variables:

- `{specifier}`: the specifier after `strip_prefix`.
- `{dir}`: the directory of the importing file.
- `{package.root}`: the package root directory.
- `{package.name}`: the package name.

### Testing a plugin

Run Reach on a file in the plugin's language with `--format tree --strict`. Imports your rules do not resolve make the run exit with a non-zero code.

## Configuration Reference

Reach reads `./reach.toml`, or the file passed with `--config`. It does not search parent directories. Paths in the file are relative to the directory of the config file. All keys are optional.

```toml
format = "kvp"
depth = 10
strict = false
cache = true

[plugins]
go = "./plugins/go"
```

### Top-level keys

- `format`: the default output format, `json`, `tree` or `kvp`. The `--format` flag overrides it.
- `depth`: the default walk depth. There is no limit if this is omitted. The `--depth` flag overrides it.
- `strict`: if `true`, exit with a non-zero code when any import is unresolved. The `--strict` flag sets it to `true`.
- `cache`: if `false`, Reach does not read or write the cache. The default is `true`.

### `[plugins]`

Maps a plugin name to a plugin directory. See [Writing Plugins](#writing-plugins).

### Cache

Reach caches the parse results of each file in `.reach/cache`, next to the config file. Entries are keyed by file content hash. Add `.reach/` to `.gitignore`. Run `reach cache clean` to delete the cache.
