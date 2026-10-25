# HopperMCPServer

A standalone MCP server and plugin for Hopper Disassembler, designed to work quietly in the background without interrupting your workflow.

## Tools

The server exposes 48 tools: 34 use Hopper v6's tool names and primary input conventions, and 14 provide additional capabilities. Responses are implemented by this project. Use MCP tool discovery for the current input schemas.

### Tools aligned with Hopper v6

| Tool | Description |
| --- | --- |
| `list_documents` | List open Hopper documents. |
| `current_document` | Get the current document for the MCP connection. |
| `set_current_document` | Select the default document for the MCP connection. |
| `list_segments` | List document segments. |
| `list_procedures` | List procedure addresses and names. |
| `list_procedure_size` | List procedure sizes. |
| `list_procedure_info` | List procedure metadata. |
| `list_strings` | List recognized strings. |
| `search_strings` | Search strings using a regular expression. |
| `search_procedures` | Search procedure names using a regular expression. |
| `procedure_info` | Read a procedure's metadata and local variables. |
| `procedure_address` | Resolve a procedure to its address. |
| `current_address` | Get the current address. |
| `current_procedure` | Get the procedure at the current address. |
| `goto_address` | Select an address in the document. |
| `procedure_assembly` | Disassemble a procedure. |
| `procedure_pseudo_code` | Decompile a procedure to pseudocode. |
| `procedure_callers` | List callers of a procedure. |
| `procedure_callees` | List procedures called by a procedure. |
| `xrefs` | List references to an address. |
| `comment` | Read the comment at an address. |
| `inline_comment` | Read the inline comment at an address. |
| `set_comment` | Set or remove a comment. |
| `set_inline_comment` | Set or remove an inline comment. |
| `next_address` | Find the next item address. |
| `prev_address` | Find the previous item address. |
| `list_names` | List named addresses. |
| `search_name` | Search labels using a regular expression. |
| `address_name` | Read the label at an address. |
| `set_address_name` | Set the label at an address. |
| `set_addresses_names` | Set labels at multiple addresses. |
| `list_bookmarks` | List document bookmarks. |
| `set_bookmark` | Add or update a bookmark. |
| `unset_bookmark` | Remove a bookmark. |

### Extended Tools

| Tool | Description |
| --- | --- |
| `bridge_status` | Read bridge, Hopper version, and activation status. |
| `list_document_objects` | List documents with session object references. |
| `get_document_info` | Read file path, base address, and analysis state. |
| `get_object` | Obtain a native Hopper object reference. |
| `list_api` | Discover methods available on a native object. |
| `invoke_api` | Invoke a native Objective-C method. |
| `release_objects` | Release session object references. |
| `api_documentation` | Search native and Python API references and constants. |
| `read_bytes` | Read bytes at a virtual address. |
| `write_bytes` | Patch bytes at a virtual address. |
| `disassemble` | Disassemble instructions starting at an address. |
| `assemble` | Assemble an instruction into machine code. |
| `list_types` | List document types. |
| `save_document` | Save a Hopper database to a `.hop` file. |

Pass an explicit document name or object reference for analysis calls. `set_current_document` stores a selection per MCP connection. Use `list_document_objects` to distinguish documents with the same name.

After [building and installing](#build-manually), open a document in Hopper and run these diagnostic calls:

```sh
./.build/release/HopperMCPServer --call list_documents
./.build/release/HopperMCPServer --call procedure_pseudo_code \
  --arguments '{"document":"example.hop","procedure":"_main"}'
```

Discover private methods with `list_api` and `include_private: true`, then use `allow_private: true` when invoking them. Method availability and signatures depend on the running Hopper version.

`assemble` returns machine code; `write_bytes` applies a patch. Saving is disabled in Hopper 6.6.0-demo. Native Hopper operations run on its main thread, so long decompilations or large queries can delay UI work. A request timeout leaves an already-running native operation active.

## Build Manually

Run build commands from the repository root. Building requires a Swift 6 toolchain, Xcode Command Line Tools, and Python 3.9 or later. The package targets macOS 12 or later.

### Bridge Plugin

The bridge is compiled separately with Clang. It uses the SDK headers in `HopperSDK` and the Objective-C sources in `Plugin/`.

Choose the SDK ABI for your Hopper version:

| Hopper version | SDK ABI | Command |
| --- | --- | --- |
| 4.x | 4 | `python3 Scripts/build_plugin.py --sdk-version 4` |
| 5.x | 4 | `python3 Scripts/build_plugin.py --sdk-version 4` |
| 6.x | 6 | `python3 Scripts/build_plugin.py --sdk-version 6` |

The script applies an ad hoc signature by default. Use `--identity` to select another signing identity.

`Plugin/api-native.json` is included in the plugin bundle. It provides the SDK method catalog used by `list_api` and `invoke_api`. After updating SDK declarations, regenerate the catalogs before building either component:

```sh
python3 Scripts/generate_api.py
```

`Scripts/generate_api.py` also updates the server's API documentation and `Sources/HopperMCPServer/EmbeddedCatalog.swift`.

### HopperMCPServer

Build the Swift executable:

```sh
swift build -c release
```

After building both components, install the plugin:

```sh
./.build/release/HopperMCPServer --install-plugin ./Build/HopperMCPBridge.hopperTool
```

Restart the target Hopper application to load the plugin, then check the connection:

```sh
./.build/release/HopperMCPServer --status
```

To switch versions, build and install the corresponding bridge, then restart the target application.

## MCP Configuration

Complete [Build Manually](#build-manually), restart Hopper, and open a binary or Hopper database. The MCP client launches `HopperMCPServer` and communicates with it over stdio.

Configuration examples use the build output path `.build/release/HopperMCPServer`. You can copy or move `HopperMCPServer` to any location on your Mac, including an App bundle.

Set `command` to the executable's absolute path and update it whenever you move the server. Hopper discovery uses the bridge's registered process and App path, independently of the server's location.

The table lists default macOS configuration locations for running the server on the same Mac as Hopper. `<project>` means the workspace where you use the agent. Create the file and parent directory as needed, and merge the server entry into any existing configuration.

| Agent | User-level configuration | Project/workspace configuration |
| --- | --- | --- |
| Codex | `~/.codex/config.toml` | `<project>/.codex/config.toml` |
| Claude Code | `~/.claude.json` | `<project>/.mcp.json` |
| Cursor | `~/.cursor/mcp.json` | `<project>/.cursor/mcp.json` |

### Codex

Add this entry to `~/.codex/config.toml` for all projects, or `<project>/.codex/config.toml` for one project. Codex loads project configuration for trusted projects.

```toml
[mcp_servers.hopper_disassembler]
enabled = true
command = "/absolute/path/to/HopperMCP/.build/release/HopperMCPServer"
args = []
tool_timeout_sec = 150
```

You can also register the server through the CLI:

```sh
codex mcp add hopper_disassembler -- \
  "/absolute/path/to/HopperMCP/.build/release/HopperMCPServer"
```

Set `tool_timeout_sec = 150` in the TOML entry created by the CLI. See the [Codex MCP documentation](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).

### Claude Code

Register a user-scoped server through the CLI; this writes to `~/.claude.json`:

```sh
claude mcp add --transport stdio --scope user hopper_disassembler -- \
  "/absolute/path/to/HopperMCP/.build/release/HopperMCPServer"
```

For a shared project configuration, create `<project>/.mcp.json`:

```json
{
  "mcpServers": {
    "hopper_disassembler": {
      "type": "stdio",
      "command": "/absolute/path/to/HopperMCP/.build/release/HopperMCPServer",
      "args": [],
      "env": {}
    }
  }
}
```

Alternatively, run the CLI command from the project root with `--scope project` instead of `--scope user`. Claude Code's default `--scope local` stores a private per-project entry in `~/.claude.json`. Check the connection with `/mcp` inside Claude Code. See the [Claude Code MCP documentation](https://code.claude.com/docs/en/mcp).

### Cursor

Add a `mcpServers` entry to `~/.cursor/mcp.json` for all projects, or `<project>/.cursor/mcp.json` for one project:

```json
{
  "mcpServers": {
    "hopper_disassembler": {
      "command": "/absolute/path/to/HopperMCP/.build/release/HopperMCPServer",
      "args": [],
      "env": {}
    }
  }
}
```

See the [Cursor MCP documentation](https://cursor.com/docs/mcp).

## Credits

- [MxIris-Reverse-Engineering/HopperMCP](https://github.com/MxIris-Reverse-Engineering/HopperMCP)
