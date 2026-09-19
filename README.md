# ws — WhatsApp Web CLI

Send, read, and list WhatsApp chats from your terminal. No server, no daemon, no WhatsApp API — just a Python script that talks to WhatsApp Web through your browser's CDP bridge.

## Prerequisites

1. **Brave / Chrome** with [Browser Bridge extension](https://github.com/juxtapo/browser-bridge) installed (our fork with the mouse click mod — upstream won't work)
2. **bbx** CLI installed (`npm i -g @anthropic/browserbridge-cli`, or build from the extension repo)
3. **WhatsApp Web** open and logged in in a browser tab
4. **Python 3.8+**

## Install

```bash
# Copy the script
sudo cp ws /usr/local/bin/ws
sudo chmod +x /usr/local/bin/ws

# Verify
ws get
```

## Usage

```bash
ws get                              # list chats (name, unread count, time, last msg)
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

## Gotchas

- **`input.type` does NOT work** for WA Web's compose box — it uses a Lexical editor that drops all but the first character. The script uses `execCommand('insertText')` via `page.evaluate` instead.
- **Send button** takes a moment to appear after typing — the script retries once if the button isn't found immediately.
- **Chat name must be exact** when using name mode. Number mode (from `ws get` output) is safer.
- **`ws get` shows the visible chat list only** — chats scrolled off-screen aren't included. Scroll the sidebar in WA Web to load more, then re-run.

## How it works

1. `tabs.list` via bbx → finds the WhatsApp Web tab
2. All calls pinned to that `tabId` → never disturbs your active browser tab
3. **get**: `page.evaluate` scrapes chat list rows from the sidebar DOM
4. **read**: clicks the chat → `page.evaluate` scrapes message bubbles
5. **send**: clicks chat → `page.evaluate` with `execCommand('insertText')` → clicks send icon

Three bbx calls per send. ~3 seconds total.

## Browser Bridge

This requires our [forked Browser Bridge](https://github.com/juxtapo/browser-bridge) — we added `cdp.dispatch_mouse_event` support which the upstream `koltyakov/browser-bridge` doesn't have. Without it, `ws` can't click on chats.

## License

MIT

---

*Born 2026-09-19, Saturday night.* 🔫
