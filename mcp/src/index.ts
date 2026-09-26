#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { resolve } from "node:path";
import { homedir } from "node:os";
import { type Capture, loadCaptures, search, withinDays } from "./vault.js";

/**
 * Wrist MCP server. Read-only access to Wrist captures that the iPhone app exports to an
 * Obsidian vault (one Markdown note per capture). Runs locally over stdio.
 *
 *   node dist/src/index.js --vault "/path/to/vault/Wrist"
 */
function vaultDir(): string {
  const flag = process.argv.indexOf("--vault");
  const raw = flag >= 0 ? process.argv[flag + 1] : process.env.WRIST_VAULT;
  if (!raw) {
    console.error("wrist-mcp: pass --vault /path/to/vault/Wrist or set WRIST_VAULT.");
    process.exit(1);
  }
  return resolve(raw.replace(/^~(?=$|\/)/, homedir()));
}

const dir = vaultDir();
const server = new McpServer({ name: "wrist-mcp-server", version: "0.1.0" });

const captureSummary = z.object({
  id: z.string(),
  title: z.string(),
  created: z.string().describe("ISO 8601 timestamp"),
  summary: z.string(),
  openTodos: z.number(),
  tags: z.array(z.string()),
  path: z.string().describe("Note path relative to the Wrist folder"),
});

function brief(c: Capture): z.infer<typeof captureSummary> {
  return {
    id: c.id,
    title: c.title,
    created: c.created,
    summary: c.summary,
    openTodos: c.todos.filter((t) => !t.done).length,
    tags: c.tags,
    path: c.path,
  };
}

function line(c: Capture): string {
  const date = c.created.slice(0, 16).replace("T", " ");
  return `- **${c.title}** (${date}, id \`${c.id}\`)${c.summary ? `: ${c.summary}` : ""}`;
}

async function captures(): Promise<Capture[]> {
  return loadCaptures(dir);
}

function failure(error: unknown) {
  return { isError: true, content: [{ type: "text" as const, text: error instanceof Error ? error.message : String(error) }] };
}

server.registerTool(
  "wrist_search_captures",
  {
    title: "Search Wrist captures",
    description:
      "Search the user's voice captures (recorded on Apple Watch/iPhone with Wrist) by keywords. Matches titles, tags, summaries, to-dos and transcripts, best match first. Use wrist_get_capture for the full transcript of a result.",
    inputSchema: {
      query: z.string().min(1).describe("Keywords, e.g. 'Priya launch beta'"),
      limit: z.number().int().min(1).max(50).default(10).describe("Maximum results (default 10)"),
      days: z.number().int().min(1).optional().describe("Only captures from the last N days"),
    },
    outputSchema: {
      results: z.array(captureSummary.extend({ snippet: z.string() })),
      total: z.number(),
    },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  async ({ query, limit, days }) => {
    try {
      const pool = (await captures()).filter((c) => days === undefined || withinDays(c, days));
      const hits = search(pool, query);
      const results = hits.slice(0, limit).map((h) => ({ ...brief(h.capture), snippet: h.snippet }));
      const text = results.length
        ? results.map((r) => `${line(hits.find((h) => h.capture.id === r.id)!.capture)}\n  > ${r.snippet}`).join("\n")
        : `No captures match "${query}". Try fewer or different keywords, or wrist_recent_captures.`;
      return { content: [{ type: "text", text }], structuredContent: { results, total: hits.length } };
    } catch (error) {
      return failure(error);
    }
  },
);

server.registerTool(
  "wrist_get_capture",
  {
    title: "Get a Wrist capture",
    description: "Get one capture in full: summary, to-dos with done state, transcript and provenance (which models transcribed and summarized it).",
    inputSchema: { id: z.string().describe("Capture id from a search or list result") },
    outputSchema: {
      id: z.string(),
      title: z.string(),
      created: z.string(),
      source: z.string(),
      durationSeconds: z.number().nullable(),
      transcribedBy: z.string().nullable(),
      summarizedBy: z.string().nullable(),
      tags: z.array(z.string()),
      summary: z.string(),
      todos: z.array(z.object({ text: z.string(), done: z.boolean() })),
      transcript: z.string(),
      path: z.string(),
    },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  async ({ id }) => {
    try {
      const capture = (await captures()).find((c) => c.id.toLowerCase() === id.toLowerCase());
      if (!capture) return failure(`No capture with id ${id}. Use wrist_search_captures or wrist_recent_captures to find ids.`);
      const todos = capture.todos.map((t) => `- [${t.done ? "x" : " "}] ${t.text}`).join("\n");
      const text = [
        `# ${capture.title}`,
        `${capture.created} · ${capture.source}${capture.summarizedBy ? ` · summary by ${capture.summarizedBy}` : ""}`,
        capture.summary,
        todos && `## To-dos\n${todos}`,
        capture.transcript && `## Transcript\n${capture.transcript}`,
      ]
        .filter(Boolean)
        .join("\n\n");
      return { content: [{ type: "text", text }], structuredContent: { ...capture } };
    } catch (error) {
      return failure(error);
    }
  },
);

server.registerTool(
  "wrist_list_open_todos",
  {
    title: "List open Wrist to-dos",
    description: "List to-dos that are not yet ticked off across all captures, newest capture first.",
    inputSchema: {
      days: z.number().int().min(1).optional().describe("Only to-dos from captures in the last N days"),
    },
    outputSchema: {
      todos: z.array(z.object({ text: z.string(), captureId: z.string(), captureTitle: z.string(), created: z.string() })),
    },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  async ({ days }) => {
    try {
      const todos = (await captures())
        .filter((c) => days === undefined || withinDays(c, days))
        .flatMap((c) => c.todos.filter((t) => !t.done).map((t) => ({ text: t.text, captureId: c.id, captureTitle: c.title, created: c.created })));
      const text = todos.length
        ? todos.map((t) => `- [ ] ${t.text} — from "${t.captureTitle}" (${t.created.slice(0, 10)})`).join("\n")
        : "No open to-dos.";
      return { content: [{ type: "text", text }], structuredContent: { todos } };
    } catch (error) {
      return failure(error);
    }
  },
);

server.registerTool(
  "wrist_recent_captures",
  {
    title: "Recent Wrist captures",
    description: "List the user's most recent captures with their summaries. Good for 'what did I capture today/this week'.",
    inputSchema: {
      days: z.number().int().min(1).max(365).default(7).describe("How far back to look (default 7 days)"),
      limit: z.number().int().min(1).max(100).default(20).describe("Maximum captures (default 20)"),
    },
    outputSchema: { captures: z.array(captureSummary), total: z.number() },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  async ({ days, limit }) => {
    try {
      const recent = (await captures()).filter((c) => withinDays(c, days));
      const shown = recent.slice(0, limit);
      const text = shown.length ? shown.map(line).join("\n") : `No captures in the last ${days} days.`;
      return { content: [{ type: "text", text }], structuredContent: { captures: shown.map(brief), total: recent.length } };
    } catch (error) {
      return failure(error);
    }
  },
);

await server.connect(new StdioServerTransport());
console.error(`wrist-mcp: serving captures from ${dir}`);
