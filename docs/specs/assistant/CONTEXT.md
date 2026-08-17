# Assistant

The personal AI system being specified to succeed the current OpenWebUI + OpenRouter
setup on sweetpaintedlady. These terms pin down what that system must be; they exist
to give a research agent an unambiguous vocabulary for evaluating candidates.

## Language

**Assistant**:
The system under specification — the user's general-purpose interface for chat,
research, brainstorming, and delegated Background Goals. Explicitly not a code
executor (implementation is OpenCode's job). Currently embodied by OpenWebUI +
OpenRouter; may end up a different product or an augmentation of the current one.
Whatever form it takes, its data must remain exportable.

**Orchestration**:
A lead agent decomposes a task into subtasks, delegates them to specialized
sub-agents, and synthesizes their results — within a single user request.
_Avoid_: multiple agents (ambiguous — may also mean Background Goals or concurrent chats)

**Background Goal**:
An objective the user assigns once and the Assistant pursues autonomously — without
further prompting, possibly over hours or on a schedule — reporting back when there
is something to report.
_Avoid_: multiple agents, agent running in the background

**Search-and-Summarize**:
A quick web lookup inside a chat, grounded in current results, answering a
point-in-time question.
_Avoid_: websearch, web search (overloaded — may also mean Deep Research)

**Deep Research**:
A long-running, multi-source web investigation that produces a cited report.
Distinct from Search-and-Summarize in duration, source count, and output shape.
_Avoid_: websearch, web search

**Zettelkasten**:
The user's personal knowledge repository — a private git repo of notes
(`aaronromeo/zettelkasten` on GitHub), backed by an Obsidian vault. Notes are flat
files named `YYYYMMDDHHMMSS_snake_case_title.md`; attachments live in `media/`,
note templates in `templates/`. The Assistant may commit research output directly
to `main`. The destination where the Assistant saves research output.

**Trigger**:
What initiates a run of a Background Goal — a recurring schedule ("every Saturday")
or an external event.

**Notification**:
A proactive message from the Assistant to the user, delivered outside the chat UI.
Carried by the existing `announcements` service (Discord webhook) on rocketman,
reachable over Tailscale.

**Calendar**:
The user's schedule of events, currently Google Calendar. Direct calendar writes
are optional — delivery of an ICS file (via Notification or Mailbox) is an
acceptable substitute.

**Mailbox**:
The user's email, hosted on Fastmail. A nice-to-have integration, not a v1
requirement. Read-only scope for now.

**Model Backend**:
An LLM endpoint the Assistant routes requests to. Must be swappable — OpenRouter,
OpenCode Go/Zen, or any OpenAI-compatible API — with a preference for near-zero
marginal cost at high capability (e.g. Kimi K3).

**Interface Host**:
The machine serving the Assistant's UI, fronted by Authelia — currently
sweetpaintedlady (Hetzner CPX21: 3 vCPU / 4 GB RAM).

**Worker Host**:
A local machine reachable over Tailscale, to which the Interface Host offloads
heavy work. Today: rocketman — a Lenovo home desktop (x86-64, 4 threads / 16 GB
RAM, Ubuntu 24.04).

**Skill**:
A reusable prompt/workflow package the Assistant can invoke by name, so repeated
tasks don't duplicate instructions (as in opencode/superpowers skills).
