// agents.test.js — node unit tests for Agents.js (agent launch argv, shell
// quoting, web-search templates) plus a sync guard against detect-env.sh.
// Run: node tests/agents.test.js

const fs = require("fs")
const path = require("path")

// QML JS with top-level declarations and no exports — eval into scope like
// model.test.js / providers.test.js do.
// eslint-disable-next-line no-eval
eval(fs.readFileSync(path.join(__dirname, "..", "Agents.js"), "utf8"))

let passed = 0
let failed = 0

function check(name, actual, expected) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a === e) {
    passed++
  } else {
    failed++
    console.error(`FAIL ${name}\n  expected: ${e}\n  actual:   ${a}`)
  }
}

// ------------------------------------------------------------ names
check("name: claude", displayName("claude"), "Claude Code")
check("name: default-ish opencode", displayName("opencode"), "OpenCode")
check("name: cursor-agent", displayName("cursor-agent"), "Cursor CLI")
check("name: unknown id title-cased", displayName("newthing"), "Newthing")
check("name: empty", displayName(""), "Agent")

// every declared id has a friendly name (keeps the tables in sync)
for (const id of AGENT_IDS) {
  check(`id has name: ${id}`, !!AGENT_NAMES[id], true)
}
check("id count matches omarchy (13)", AGENT_IDS.length, 13)

// ------------------------------------------------------------ argv tables
check("argv: claude with prompt (mirrors omarchy-agent)",
  agentArgv("claude", "fix bug"),
  ["claude", "--permission-mode", "auto", "--", "fix bug"])
check("argv: claude bare (no prompt flags at all)",
  agentArgv("claude", ""),
  ["claude", "--permission-mode", "auto"])
check("argv: codex", agentArgv("codex", "hi"),
  ["codex", "--approve-for-me", "--", "hi"])
check("argv: gemini", agentArgv("gemini", "hi"),
  ["gemini", "--yolo", "--prompt-interactive", "hi"])
check("argv: crush run vs --yolo", agentArgv("crush", "q"), ["crush", "run", "q"])
check("argv: crush bare", agentArgv("crush", ""), ["crush", "--yolo"])
check("argv: hermes unsets source + --query=",
  agentArgv("hermes", "q"),
  ["env", "-u", "HERMES_SESSION_SOURCE", "hermes", "chat",
    "--yolo", "--tui", "--query=q"])
check("argv: cursor-agent names the subcommand",
  agentArgv("cursor-agent", "q"),
  ["cursor-agent", "--yolo", "--trust", "agent", "--", "q"])
check("argv: opencode", agentArgv("opencode", "q"), ["opencode", "--auto", "--prompt", "q"])
check("argv: pi positional", agentArgv("pi", "q"), ["pi", "q"])
check("argv: unknown id → null (row is skipped, never guessed)",
  agentArgv("not-an-agent", "q"), null)

// ------------------------------------------------------------ shell safety
check("quote: plain", shellQuote("hello"), "'hello'")
check("quote: single quote escaped", shellQuote("it's"), "'it'\\''s'")
// input:  '; rm -rf /; echo '   →   ''\''; rm -rf /; echo '\'''
// every quote inside the value becomes '\'' so it can never terminate
// the surrounding quotes and escape its argument position.
check("quote: injection string",
  shellQuote("'; rm -rf /; echo '"),
  "''\\''; rm -rf /; echo '\\'''")
check("quote: dollar and backticks are literal",
  shellQuote("`id` $USER"), "'`id` $USER'")

const cmd = agentCommand("claude", "it's a $test")
check("cmd: launcher prefix",
  cmd.startsWith("omarchy-launch-tui --app-id=org.omarchy.agent claude "), true)
check("cmd: query stays quoted even with quote+dollar",
  cmd.includes("'it'\\''s a $test'"), true)
check("cmd: -- separates the prompt", cmd.includes("'--'"), true)
check("cmd: unknown agent → null", agentCommand("wat", "q"), null)

// ------------------------------------------------------------ default agent
check("default ask", defaultAgentCommand("review this"),
  "omarchy agent prompt 'review this'")
check("default ask quotes injection",
  defaultAgentCommand("a'b"),
  "omarchy agent prompt 'a'\\''b'")
check("pick command", pickDefaultAgentCommand(), "omarchy agent --pick")

// ------------------------------------------------------------ web templates
check("web: ddg template", webSearchUrl("https://duckduckgo.com/?q=%s", "a b"),
  "https://duckduckgo.com/?q=a%20b")
check("web: google template encodes", webSearchUrl("https://www.google.com/search?q=%s", "a&b"),
  "https://www.google.com/search?q=a%26b")
check("web: no template → empty (caller falls back)",
  webSearchUrl("https://example.com/", "x"), "")
check("web: empty query still substitutes",
  webSearchUrl("https://x/?q=%s", ""), "https://x/?q=")
check("web: injection text is encoded, not passed through",
  // encodeURIComponent deliberately leaves ' ( ) ! ~ * unreserved — safe
  // here because the result feeds a browser URL, never a shell.
  webSearchUrl("https://x/?q=%s", "'; rm -rf /"),
  "https://x/?q='%3B%20rm%20-rf%20%2F")

// ------------------------------------------------------------ detect sync
const detect = fs.readFileSync(
  path.join(__dirname, "..", "detect-env.sh"), "utf8")
const block = detect.match(/for id in ([^;]+); do/)
check("detect-env.sh has the agent loop", !!block, true)
const shellIds = block[1].replace(/\\/g, "").split(/\s+/).filter(Boolean)
check("detect-env.sh ids == Agents.js AGENT_IDS",
  shellIds, AGENT_IDS)

console.log(`${passed} passed, ${failed} failed`)
process.exit(failed ? 1 : 0)
