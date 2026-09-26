import { readdir, readFile, stat } from "node:fs/promises";
import { join, relative } from "node:path";

/** A capture as written by Wrist's Obsidian export (see ObsidianExporter.swift). */
export interface Capture {
  id: string;
  title: string;
  created: string;
  source: string;
  durationSeconds: number | null;
  transcribedBy: string | null;
  summarizedBy: string | null;
  tags: string[];
  summary: string;
  todos: { text: string; done: boolean }[];
  transcript: string;
  path: string;
}

/** Parses one Wrist note. Returns null for notes Wrist didn't write (no `wrist-id`). */
export function parseCapture(markdown: string, path: string): Capture | null {
  const match = /^---\n([\s\S]*?)\n---\n?([\s\S]*)$/.exec(markdown.replace(/\r\n/g, "\n"));
  if (!match) return null;
  const meta: Record<string, string> = {};
  for (const line of match[1].split("\n")) {
    const colon = line.indexOf(":");
    if (colon > 0) meta[line.slice(0, colon).trim()] = line.slice(colon + 1).trim();
  }
  const id = meta["wrist-id"];
  if (!id) return null;

  const unquote = (value: string | undefined) => value?.replace(/^"(.*)"$/, "$1") ?? null;
  const tags = (meta["tags"] ?? "")
    .replace(/^\[|\]$/g, "")
    .split(",")
    .map((t) => t.trim())
    .filter((t) => t && t !== "wrist");

  const body = match[2];
  const title = /^# (.+)$/m.exec(body)?.[1]?.trim() ?? "Untitled capture";
  const sections = splitSections(body);
  const todos = (sections.get("To-dos") ?? "")
    .split("\n")
    .map((line) => /^- \[( |x|X)\] (.+)$/.exec(line.trim()))
    .filter((m): m is RegExpExecArray => m !== null)
    .map((m) => ({ text: m[2].trim(), done: m[1].toLowerCase() === "x" }));

  return {
    id,
    title,
    created: meta["created"] ?? "",
    source: meta["source"] ?? "unknown",
    durationSeconds: meta["duration"] ? Number(meta["duration"]) : null,
    transcribedBy: unquote(meta["transcribed-by"]),
    summarizedBy: unquote(meta["summarized-by"]),
    tags,
    summary: (sections.get("") ?? "").replace(/^# .+$/m, "").trim(),
    todos,
    transcript: (sections.get("Transcript") ?? "").trim(),
    path,
  };
}

/** Splits a note body on `## ` headings; the text before the first heading has key "". */
function splitSections(body: string): Map<string, string> {
  const sections = new Map<string, string>();
  let current = "";
  let lines: string[] = [];
  for (const line of body.split("\n")) {
    const heading = /^## (.+)$/.exec(line);
    if (heading) {
      sections.set(current, lines.join("\n"));
      current = heading[1].trim();
      lines = [];
    } else {
      lines.push(line);
    }
  }
  sections.set(current, lines.join("\n"));
  return sections;
}

/** Loads every Wrist capture under `dir`, newest first. Re-read on each call so edits show up immediately. */
export async function loadCaptures(dir: string): Promise<Capture[]> {
  const info = await stat(dir).catch(() => null);
  if (!info?.isDirectory()) {
    throw new Error(`Wrist folder not found: ${dir}. Pass --vault /path/to/vault/Wrist (the folder Wrist exports to).`);
  }
  const captures: Capture[] = [];
  for (const file of await walk(dir)) {
    const capture = parseCapture(await readFile(file, "utf8"), relative(dir, file));
    if (capture) captures.push(capture);
  }
  return captures.sort((a, b) => b.created.localeCompare(a.created));
}

async function walk(dir: string): Promise<string[]> {
  const entries = await readdir(dir, { withFileTypes: true });
  const files = await Promise.all(
    entries
      .filter((e) => !e.name.startsWith("."))
      .map((e) => (e.isDirectory() ? walk(join(dir, e.name)) : Promise.resolve(e.name.endsWith(".md") ? [join(dir, e.name)] : []))),
  );
  return files.flat();
}

/** Simple term-frequency search across title, tags, summary, to-dos and transcript. */
export function search(captures: Capture[], query: string): { capture: Capture; score: number; snippet: string }[] {
  const terms = query.toLowerCase().split(/\W+/).filter((t) => t.length > 2);
  if (terms.length === 0) return [];
  return captures
    .map((capture) => {
      const weighted = [
        [capture.title, 3],
        [capture.tags.join(" "), 3],
        [capture.summary, 2],
        [capture.todos.map((t) => t.text).join(" "), 2],
        [capture.transcript, 1],
      ] as const;
      let score = 0;
      for (const [text, weight] of weighted) {
        const lower = text.toLowerCase();
        for (const term of terms) if (lower.includes(term)) score += weight;
      }
      return { capture, score, snippet: snippet(capture.transcript || capture.summary, terms) };
    })
    .filter((r) => r.score > 0)
    .sort((a, b) => b.score - a.score || b.capture.created.localeCompare(a.capture.created));
}

function snippet(text: string, terms: string[], radius = 160): string {
  const lower = text.toLowerCase();
  const hit = terms.map((t) => lower.indexOf(t)).filter((i) => i >= 0).sort((a, b) => a - b)[0] ?? 0;
  const start = Math.max(0, hit - radius);
  const end = Math.min(text.length, hit + radius);
  return (start > 0 ? "…" : "") + text.slice(start, end).trim() + (end < text.length ? "…" : "");
}

export function withinDays(capture: Capture, days: number, now = Date.now()): boolean {
  const created = Date.parse(capture.created);
  return Number.isFinite(created) && now - created <= days * 86_400_000;
}
