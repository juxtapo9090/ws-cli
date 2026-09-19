---
name: ws
description: "Send, read, and list WhatsApp chats via the ws CLI — abang's WA Web on bravemag, no extension needed."
user_invocable: true
---

# ws — WhatsApp Web CLI

Drive abang's WhatsApp Web through `ws` — a CLI that talks to bravemag's CDP bridge (`bbx`).
No extension, no server, no daemon. One script, three commands.

## Prerequisites

- WhatsApp Web must be **open in a tab** on brave-abang (bravemag's Brave)
- bravemag access must be **enabled** (check: `bbx status`)
- Script lives at `/usr/local/bin/ws` — works for root and juxtapo seats

## Commands

```bash
ws get                              # list chats (name, unread, time, last msg)
ws read <chat-name-or-number>       # read last ~20 messages from a chat
ws send <chat-name-or-number> <msg> # send a message to a chat
```

### By number

`ws get` prints numbered rows. Use that number in `read` and `send`:

```bash
ws get              # shows: 3. PERSONAL WORK (11:42 PM) — ...
ws read 3           # read messages from PERSONAL WORK
ws send 3 hello     # send "hello" to PERSONAL WORK
```

### By name

Use the exact chat name as shown in `ws get`:

```bash
ws send "PERSONAL WORK" "meeting at 3pm"
ws read "Lisa medianet"
```

## How it works under the hood

1. `tabs.list` via bbx → finds the WhatsApp Web tab
2. All calls pinned to that `tabId` → never disturbs abang's active tab
3. **get**: `page.evaluate` scrapes chat list rows from the sidebar DOM
4. **read**: clicks the chat → `page.evaluate` scrapes `[data-pre-plain-text]` message bubbles
5. **send**: clicks chat → `page.evaluate` with `execCommand('insertText')` → clicks send icon

Three bbx calls per send. ~3 seconds total.

## Key gotchas

- **`input.type` does NOT work** for WA Web's compose box — Lexical editor drops all but the
  first character. Always use `execCommand('insertText')` via `page.evaluate`.
- **Send button** takes a moment to appear after typing — the script retries once if not found.
- **Chat name must be exact** when using name mode. Number mode is safer.
- **`ws get` shows the visible chat list only** — chats scrolled off-screen aren't included.
  Scroll the sidebar in WA Web to load more, then re-run.

## Extending later

- `ws search <term>` — use WA's search box to find a chat not in the visible list
- `ws send <chat> --image <path>` — attach media via the file input dance
- `ws watch <chat>` — poll for new messages and notify a seat
- Webhook integration — incoming messages → seat notification

## Source

`/usr/local/bin/ws` — single python3 script, ~200 lines. Uses `bbx` CLI
(`/home/juxtapo/.local/bin/bbx`) under the hood. Root calls via `runuser -u juxtapo`,
juxtapo calls directly.

## Born

2026-09-19, Saturday night. Selene built, abang designed. 🌙
