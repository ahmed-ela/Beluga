#!/usr/bin/env node
// Exercise the production counter functions without rerunning unrelated identity surfaces.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const source = fs.readFileSync(path.join(root, "scripts/check-product-identity.sh"), "utf8");
const libraryBoundary = "\nfor required_tool in ";
const verdictBoundary = "# Resolve every deferred assertion before admission.";
assert.equal(source.split(libraryBoundary).length, 2, "ambiguous production function boundary");
assert.equal(source.split(verdictBoundary).length, 2, "ambiguous production verdict boundary");
const library = source.slice(0, source.indexOf(libraryBoundary));
const verdict = source.slice(source.indexOf(verdictBoundary));
const scratchParent = "/Volumes/t7";
assert.ok(fs.lstatSync(scratchParent).isDirectory(), "literal-test scratch parent is not a directory");
assert.ok(!fs.lstatSync(scratchParent).isSymbolicLink(), "literal-test scratch parent is a symlink");
const scratch = fs.mkdtempSync(path.join(scratchParent, "opensteamer-identity-literals."));
fs.chmodSync(scratch, 0o700);
const scratchIdentity = fs.statSync(scratch);
let passed = 0;

function quote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

function assertion(file, literal, expected, description) {
  return `assert_literal_count ${quote(file)} ${quote(literal)} ${quote(expected)} ${quote(description)}`;
}

function originalCount(bytes, literal) {
  const contents = Buffer.from(bytes).toString("utf8");
  let count = 0;
  let offset = 0;
  while ((offset = contents.indexOf(literal, offset)) >= 0) {
    count += 1;
    offset += literal.length;
  }
  return count;
}

function scenario(name, { files = {}, commands, expected = [], nodeOverride, inspect, setup }) {
  const directory = path.join(scratch, name);
  fs.mkdirSync(directory, { mode: 0o700 });
  for (const [relative, bytes] of Object.entries(files)) {
    const file = path.join(directory, relative);
    fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
    fs.writeFileSync(file, bytes);
  }
  setup?.(directory);
  const nodeBody = nodeOverride ?? `${quote(process.execPath)} "$@"`;
  const program = `${library}
node() {
  print -r -- invoked >> "$ROOT/node-calls"
  ${nodeBody}
}
${commands}
${verdict}`;
  const result = spawnSync("/bin/zsh", ["-c", program, "identity-literal-test", directory], {
    encoding: "utf8",
    timeout: 15_000,
    maxBuffer: 2 * 1024 * 1024,
  });
  assert.ifError(result.error);
  assert.equal(result.signal, null, `${name}: unexpected signal`);
  assert.equal(result.status, expected.length === 0 ? 0 : 1, `${name}: ${result.stderr}`);
  const diagnostics = result.stderr.split("\n")
    .filter((line) => line.startsWith("product identity check failed: "));
  assert.deepEqual(diagnostics, expected.map((item) => `product identity check failed: ${item}`), name);
  if (expected.length > 0) {
    assert.ok(!result.stdout.includes("product identity check passed"), `${name}: printed false success`);
    assert.ok(result.stderr.includes(`rejected ${expected.length} mismatch(es)`), `${name}: wrong failure count`);
  }
  const calls = fs.existsSync(path.join(directory, "node-calls"))
    ? fs.readFileSync(path.join(directory, "node-calls"), "utf8").trim().split("\n").length : 0;
  inspect?.({ result, calls, directory });
  passed += 1;
  return { result, calls, directory };
}

try {
  const first = "🙂\n🙂\n🙂\n'quoted'\\path\n終\n'quoted'\\path\n終\n";
  const oddPath = "space ' and\nUnicode-終.txt";
  const invalidUTF8 = Buffer.from([0xc3, 0x28, 0x0a, 0x78]);
  const requests = [
    ["first.txt", "🙂\n🙂", 1],
    ["first.txt", "'quoted'\\path\n終", 2],
    ["first.txt", "absent\nvalue", 0],
    ["overlap.txt", "a\na", 1],
    [oddPath, "e\u0301\né", 2],
    ["invalid-utf8.txt", "�(\nx", 1],
  ];
  const bytes = {
    "first.txt": first,
    "overlap.txt": "a\na\na",
    [oddPath]: "e\u0301\né e\u0301\né",
    "invalid-utf8.txt": invalidUTF8,
  };
  for (const [file, literal, expected] of requests) {
    assert.equal(originalCount(bytes[file], literal), expected, "independent legacy algorithm expectation");
  }
  scenario("unicode-and-nonoverlap", {
    files: bytes,
    commands: requests.map(([file, literal, expected], index) =>
      assertion(file, literal, expected, `request ${index}`)).join("\n"),
    inspect: ({ calls }) => assert.equal(calls, 1, "multiline requests launched more than one Node"),
  });

  scenario("single-line-grep-unchanged", {
    files: { "one.txt": "aaa\n--flag --flag\n" },
    commands: [
      assertion("one.txt", "aa", 1, "single-line nonoverlap"),
      assertion("one.txt", "--flag", 2, "leading dash"),
      assertion("one.txt", "not present", 0, "single-line absence"),
    ].join("\n"),
    inspect: ({ calls }) => assert.equal(calls, 0, "single-line branch unexpectedly launched Node"),
  });

  scenario("ordered-mixed-diagnostics", {
    files: { "one.txt": "a\nb\n--flag\n" },
    commands: [
      "fail 'before literals'",
      assertion("one.txt", "a\nb", 2, "first multiline"),
      assertion("one.txt", "--flag", 0, "ordinary single-line"),
      assertion("missing.txt", "a\nb", 0, "missing multiline"),
      assertion("one.txt", "", 0, "empty literal"),
      assertion("one.txt", "a\nb", 3, "second same-file multiline"),
      "fail 'after literals'",
    ].join("\n"),
    expected: [
      "before literals",
      "first multiline: expected [2], found [1]",
      "ordinary single-line: expected [0], found [1]",
      "required file is missing: missing.txt",
      "empty literal: cannot count an empty required literal in one.txt",
      "second same-file multiline: expected [3], found [1]",
      "after literals",
    ],
    inspect: ({ calls }) => assert.equal(calls, 1),
  });

  scenario("only-empty-and-missing", {
    files: { "one.txt": "value" },
    commands: [
      assertion("one.txt", "", 0, "empty literal"),
      assertion("gone.txt", "a\nb", 0, "missing file"),
    ].join("\n"),
    expected: [
      "empty literal: cannot count an empty required literal in one.txt",
      "required file is missing: gone.txt",
    ],
    inspect: ({ calls }) => assert.equal(calls, 0),
  });

  scenario("source-removed-before-read", {
    files: { "gone.txt": "a\nb", "healthy.txt": "a\nb" },
    commands: [
      assertion("gone.txt", "absent\nvalue", 0, "read failure is not zero"),
      '/bin/rm -- "$ROOT/gone.txt"',
      assertion("healthy.txt", "a\nb", 1, "healthy request after failure"),
    ].join("\n"),
    expected: ["read failure is not zero: could not count the required literal in gone.txt"],
    inspect: ({ result, calls }) => {
      assert.equal(calls, 1);
      assert.ok(result.stderr.includes("ENOENT"), "filesystem error diagnostic was discarded");
    },
  });

  scenario("unreadable-source", {
    files: { "denied.txt": "a\nb" },
    commands: assertion("denied.txt", "not\npresent", 0, "denied read is not zero"),
    setup: (directory) => fs.writeFileSync(path.join(directory, "deny-read.cjs"), `
const fs = require("node:fs");
const original = fs.readFileSync;
fs.readFileSync = function(file, ...args) {
  if (file === ${JSON.stringify(path.join(directory, "denied.txt"))}) {
    const error = new Error("EACCES: permission denied, read");
    error.code = "EACCES";
    throw error;
  }
  return original.call(this, file, ...args);
};
`),
    nodeOverride: `${quote(process.execPath)} --require "$ROOT/deny-read.cjs" "$@"`,
    expected: ["denied read is not zero: could not count the required literal in denied.txt"],
    inspect: ({ result }) => assert.ok(result.stderr.includes("EACCES")),
  });

  scenario("empty-worker-literal-is-not-zero", {
    files: { "one.txt": "a\nb" },
    commands: `${assertion("one.txt", "a\nb", 0, "empty worker literal")}
IDENTITY_MULTILINE_FIELDS[2]=''`,
    expected: ["empty worker literal: could not count the required literal in one.txt"],
    inspect: ({ result }) => assert.ok(result.stderr.includes("empty required literal")),
  });

  const pending = [
    assertion("one.txt", "a\nb", 0, "first pending"),
    assertion("two.txt", "x\ny", 0, "second pending"),
  ].join("\n");
  const rejectedPending = [
    "first pending: could not count the required literal in one.txt",
    "second pending: could not count the required literal in two.txt",
  ];
  const validRecords = ["1", "ok", "0", "", "2", "ok", "0", "", "2", "complete"];
  const malformed = [
    ["no-output", ""],
    ["partial-output", validRecords.slice(0, 4).join("\0")],
    ["extra-output", [...validRecords, "extra"].join("\0")],
    ["wrong-index", ["2", ...validRecords.slice(1)].join("\0")],
    ["wrong-last-index", [...validRecords.slice(0, 4), "1", ...validRecords.slice(5)].join("\0")],
    ["wrong-marker", [...validRecords.slice(0, -1), "incomplete"].join("\0")],
    ["negative-count", ["1", "ok", "-1", ...validRecords.slice(3)].join("\0")],
    ["noncanonical-count", ["1", "ok", "00", ...validRecords.slice(3)].join("\0")],
    ["nonnumeric-count", ["1", "ok", "NaN", ...validRecords.slice(3)].join("\0")],
    ["ok-with-error", ["1", "ok", "0", "unexpected error", ...validRecords.slice(4)].join("\0")],
    ["error-with-zero-count", ["1", "error", "0", "EACCES", ...validRecords.slice(4)].join("\0")],
    ["empty-error", ["1", "error", "", "", ...validRecords.slice(4)].join("\0")],
  ];
  for (const [name, output] of malformed) {
    scenario(name, {
      files: { "one.txt": "a\nb", "two.txt": "x\ny", "worker-output": output },
      commands: pending,
      nodeOverride: '/bin/cat -- "$ROOT/worker-output"',
      expected: rejectedPending,
    });
  }
  scenario("worker-exit-failure", {
    files: { "one.txt": "a\nb", "two.txt": "x\ny", "worker-output": validRecords.join("\0") },
    commands: pending,
    nodeOverride: '/bin/cat -- "$ROOT/worker-output"\nreturn 9',
    expected: rejectedPending,
  });
  scenario("invalid-request-framing", {
    files: { "one.txt": "a\nb", "two.txt": "x\ny" },
    commands: `${pending}\nIDENTITY_MULTILINE_FIELDS+=(extra)`,
    expected: rejectedPending,
  });

  scenario("unflushed-is-not-success", {
    files: { "one.txt": "a\nb" },
    commands: `${assertion("one.txt", "a\nb", 1, "pending assertion")}
flush_literal_count_batch() { return 0; }`,
    expected: ["multiline literal-count assertions remain unflushed"],
    inspect: ({ calls }) => assert.equal(calls, 0),
  });

  // The prerequisite branch precedes source assertions and must still emit recorded failures.
  const prerequisiteEnd = source.indexOf("\n# Root package and public project name.");
  assert.ok(prerequisiteEnd > source.indexOf(libraryBoundary));
  const prerequisite = source.slice(source.indexOf(libraryBoundary), prerequisiteEnd);
  const prerequisiteResult = spawnSync("/bin/zsh", ["-c", `${library}
command() { return 1; }
${prerequisite}`, "identity-literal-prerequisite", scratch], { encoding: "utf8", timeout: 15_000 });
  assert.ifError(prerequisiteResult.error);
  assert.equal(prerequisiteResult.status, 1);
  for (const tool of ["awk", "find", "grep", "node", "plutil", "sed", "sort", "xmllint"]) {
    assert.ok(prerequisiteResult.stderr.includes(`required validation tool is unavailable: ${tool}`));
  }
  passed += 1;

  const fresh = scenario("fresh-invocation", {
    files: { "one.txt": "a\nb" },
    commands: assertion("one.txt", "a\nb", 1, "fresh source"),
  });
  fs.writeFileSync(path.join(fresh.directory, "one.txt"), "a\nb\na\nb");
  const freshResult = spawnSync("/bin/zsh", ["-c",
    `${library}\n${assertion("one.txt", "a\nb", 2, "changed source")}\n${verdict}`,
    "identity-literal-fresh", fresh.directory], { encoding: "utf8", timeout: 15_000 });
  assert.ifError(freshResult.error);
  assert.equal(freshResult.status, 0, freshResult.stderr);
  passed += 1;
  console.log(`PASS: ${passed} focused product-identity literal-counter scenarios`);
} finally {
  const current = fs.lstatSync(scratch);
  assert.ok(current.isDirectory() && !current.isSymbolicLink());
  assert.equal(fs.realpathSync(scratch), scratch);
  assert.equal(current.dev, scratchIdentity.dev);
  assert.equal(current.ino, scratchIdentity.ino);
  assert.equal(current.uid, scratchIdentity.uid);
  assert.ok(scratch.startsWith(`${scratchParent}/opensteamer-identity-literals.`));
  fs.rmSync(scratch, { recursive: true, force: true });
}
