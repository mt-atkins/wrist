# Wrist MCP server

Gives Claude Desktop, Claude Code or any MCP client read-only access to your Wrist captures.

The iPhone app saves each capture to your Obsidian vault as a Markdown note (Settings › Obsidian, a Wrist Pro feature). This server runs on your Mac and reads those notes, so your captures don't go anywhere new. The server itself sends nothing over the network.

## Setup

```sh
git clone https://github.com/mt-atkins/wrist.git
cd wrist/mcp
npm install          # also builds dist/
```

**Claude Code**

```sh
claude mcp add wrist -- node "$PWD/dist/src/index.js" --vault "/path/to/your/vault/Wrist"
```

**Claude Desktop** (`claude_desktop_config.json`)

```json
{
  "mcpServers": {
    "wrist": {
      "command": "node",
      "args": ["/path/to/wrist/mcp/dist/src/index.js", "--vault", "/path/to/your/vault/Wrist"]
    }
  }
}
```

An iCloud Drive Obsidian vault lives at `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/<Vault>`. You can also set `WRIST_VAULT` instead of passing `--vault`.

## Tools

| Tool | What it does |
|---|---|
| `wrist_search_captures` | Keyword search over titles, tags, summaries, to-dos and transcripts. Optional `days` filter. |
| `wrist_get_capture` | One capture in full: summary, to-dos, transcript, and which models transcribed and summarized it. |
| `wrist_list_open_todos` | Unticked to-dos across captures, newest first. |
| `wrist_recent_captures` | What you captured in the last N days. |

All tools are read-only and return both text and structured JSON.

## Develop

```sh
npm test    # compiles and runs the parser/search tests
npx @modelcontextprotocol/inspector node dist/src/index.js --vault /path/to/Wrist
```

The note format is defined by `ObsidianExporter.markdown(for:)` in the iOS app. `test/vault.test.ts` pins that format, so change both together.
