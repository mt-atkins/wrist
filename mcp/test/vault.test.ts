import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadCaptures, parseCapture, search, withinDays } from "../src/vault.js";

// Exactly what ObsidianExporter.markdown(for:) writes.
const NOTE = `---
wrist-id: 0E979C95-5AE0-4211-9B78-407996E610C7
created: 2026-09-21T14:13:20Z
source: watch
duration: 48
transcribed-by: Whisper Small
summarized-by: Claude · claude-opus-5
tags: [wrist, launch, pricing]
---

# Launch coffee with Priya

Priya wants the beta moved to November.

## To-dos
- [ ] Send Priya the pricing deck
- [x] Book the photographer

## Transcript

Okay, quick recap from the coffee with Priya about the launch. I need to send her the pricing deck by Thursday.
`;

test("parses a Wrist note", () => {
  const c = parseCapture(NOTE, "2026-09-21 1413 Launch coffee with Priya.md")!;
  assert.equal(c.id, "0E979C95-5AE0-4211-9B78-407996E610C7");
  assert.equal(c.title, "Launch coffee with Priya");
  assert.equal(c.summary, "Priya wants the beta moved to November.");
  assert.deepEqual(c.tags, ["launch", "pricing"]);
  assert.deepEqual(c.todos, [
    { text: "Send Priya the pricing deck", done: false },
    { text: "Book the photographer", done: true },
  ]);
  assert.equal(c.transcribedBy, "Whisper Small");
  assert.equal(c.summarizedBy, "Claude · claude-opus-5");
  assert.equal(c.durationSeconds, 48);
  assert.match(c.transcript, /pricing deck by Thursday/);
});

test("ignores notes Wrist didn't write", () => {
  assert.equal(parseCapture("# Just a note\n\nhello", "x.md"), null);
  assert.equal(parseCapture("---\ntitle: other\n---\n# Other", "y.md"), null);
});

test("loads a folder, skips non-Wrist notes, searches and filters by date", async () => {
  const dir = await mkdtemp(join(tmpdir(), "wrist-"));
  await mkdir(join(dir, "sub"));
  await writeFile(join(dir, "a.md"), NOTE);
  await writeFile(join(dir, "sub", "b.md"), NOTE.replace("0E979C95", "11111111").replace("2026-09-21", "2026-01-02").replace("Priya", "Sam"));
  await writeFile(join(dir, "daily.md"), "# 2026-09-21\n- [[Wrist/a]]");
  const captures = await loadCaptures(dir);
  assert.equal(captures.length, 2);
  assert.equal(captures[0].created, "2026-09-21T14:13:20Z", "newest first");
  const hits = search(captures, "priya pricing");
  assert.equal(hits[0].capture.title, "Launch coffee with Priya");
  assert.ok(hits[0].snippet.toLowerCase().includes("priya"));
  assert.equal(search(captures, "zz").length, 0);
  const now = Date.parse("2026-09-25T00:00:00Z");
  assert.equal(captures.filter((c) => withinDays(c, 7, now)).length, 1);
});

test("explains a missing folder", async () => {
  await assert.rejects(loadCaptures("/nope/wrist"), /--vault/);
});
