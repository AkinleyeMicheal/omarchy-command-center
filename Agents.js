// Agents.js — AI-agent launch metadata for the universal launcher's
// "ask an agent" rows. Pure data + pure functions: node-testable, no I/O.
//
// Two mirrors of Omarchy's own machinery (re-check when omarchy updates —
// paths recorded in ROADMAP.md):
//   AGENT_NAMES  mirrors the case table in
//                /usr/share/omarchy/bin/omarchy-default-agent
//   agentArgv    mirrors the command table in
//                /usr/share/omarchy/bin/omarchy-agent (the per-agent flags
//                that make keybinding launches run unattended)
//
// The DEFAULT agent never uses this table — it goes through
// `omarchy agent prompt "<query>"`, which owns the full canonical behavior.

var AGENT_NAMES = {
  pi: "Pi",
  omp: "Oh My Pi",
  opencode: "OpenCode",
  claude: "Claude Code",
  codex: "Codex",
  grok: "Grok",
  gemini: "Gemini",
  openclaw: "OpenClaw",
  hermes: "Hermes",
  copilot: "GitHub Copilot",
  crush: "Crush",
  "cursor-agent": "Cursor CLI",
  muse: "Muse Code"
}

// Ids checked for installation by detect-env.sh (order = detection order).
var AGENT_IDS = ["pi", "omp", "opencode", "claude", "codex", "grok", "gemini",
  "openclaw", "hermes", "copilot", "crush", "cursor-agent", "muse"]

function displayName(id) {
  id = String(id || "")
  if (AGENT_NAMES[id]) return AGENT_NAMES[id]
  return id ? id.charAt(0).toUpperCase() + id.slice(1) : "Agent"
}

// argv for launching a NON-default agent with a prefilled prompt — an exact
// mirror of omarchy-agent's case table. Returns null for unknown ids so the
// caller can skip the row instead of guessing flags.
//   crush has no --yolo on `crush run`; hermes unsets HERMES_SESSION_SOURCE;
//   cursor-agent must name the `agent` subcommand; openclaw goes through its
//   own launcher (all straight from omarchy-agent).
function agentArgv(id, prompt) {
  id = String(id || "")
  var q = String(prompt || "")
  switch (id) {
    case "opencode": return ["opencode", "--auto"].concat(q ? ["--prompt", q] : [])
    case "gemini": return ["gemini", "--yolo"].concat(q ? ["--prompt-interactive", q] : [])
    case "copilot": return ["copilot", "--allow-all"].concat(q ? ["--interactive", q] : [])
    case "crush": return q ? ["crush", "run", q] : ["crush", "--yolo"]
    case "claude": return ["claude", "--permission-mode", "auto"].concat(q ? ["--", q] : [])
    case "grok": return ["grok", "--permission-mode", "bypassPermissions"].concat(q ? ["--", q] : [])
    case "codex": return ["codex", "--approve-for-me"].concat(q ? ["--", q] : [])
    case "cursor-agent":
      return ["cursor-agent", "--yolo", "--trust", "agent"].concat(q ? ["--", q] : [])
    case "openclaw":
      return ["omarchy-launch-openclaw", "--tui"].concat(q ? ["--message", q] : [])
    case "hermes":
      return ["env", "-u", "HERMES_SESSION_SOURCE", "hermes", "chat",
        "--yolo", "--tui"].concat(q ? ["--query=" + q] : [])
    case "muse": return ["muse", "--approval-mode", "never"].concat(q ? ["--", q] : [])
    case "omp": return ["omp", "--auto-approve"].concat(q ? ["--", q] : [])
    case "pi": return ["pi"].concat(q ? [q] : [])
    default: return null
  }
}

// Single-quote one argv element for a POSIX shell. Every element the plugin
// ever puts on a command line passes through here — user query text can then
// never break out of its argument position.
function shellQuote(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'"
}

// Full shell command to launch a non-default agent with a prompt through
// Omarchy's TUI launcher (same app-id as omarchy-agent, so all agent windows
// share one class for window rules). The program name comes from the fixed
// table (never user input); every following element — including the query —
// is single-quoted. null for unknown agents.
function agentCommand(id, prompt) {
  var argv = agentArgv(id, prompt)
  if (!argv) return null
  var quoted = [argv[0]].concat(argv.slice(1).map(shellQuote))
  return ["omarchy-launch-tui", "--app-id=org.omarchy.agent"].concat(quoted).join(" ")
}

// The canonical ask for the DEFAULT agent: omarchy-agent-prompt → omarchy-agent
// handles the cd-to-Work, per-agent flags, and terminal launch itself.
function defaultAgentCommand(prompt) {
  return "omarchy agent prompt " + shellQuote(String(prompt || ""))
}

// When no default is set, this row offers the picker instead of an error.
function pickDefaultAgentCommand() {
  return "omarchy agent --pick"
}

// ------------------------------------------------------------ web search
// Substitute a browser search-engine template ({searchTerm}/{searchTerm}
// Chromium-style templates are normalized to %s upstream in detect-env.sh).
// %s is replaced URL-encoded; an unknown template shape returns "" so the
// caller falls back rather than opening a broken URL.
function webSearchUrl(template, query) {
  var t = String(template || "")
  if (t.indexOf("%s") < 0) return ""
  return t.replace("%s", encodeURIComponent(String(query || "")))
}
