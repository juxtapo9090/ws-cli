#!/usr/bin/env python3
"""ws — WhatsApp Web CLI via bbx (bravemag's CDP bridge)."""

import json
import subprocess
import sys
import time

BBX = "/home/juxtapo/.local/bin/bbx"
BBX_USER = "juxtapo"

def bbx(method, args, tab_id=None):
    import os
    if os.getuid() == 0:
        cmd = ["runuser", "-u", BBX_USER, "--", BBX, "call"]
    else:
        cmd = [BBX, "call"]
    if tab_id:
        cmd += ["--tab", str(tab_id)]
    cmd += [method, json.dumps(args)]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    if r.returncode != 0:
        print(f"bbx error: {r.stderr.strip() or r.stdout.strip()}", file=sys.stderr)
        sys.exit(1)
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        print(f"bbx bad response: {r.stdout[:200]}", file=sys.stderr)
        sys.exit(1)

def find_wa_tab():
    data = bbx("tabs.list", {})
    tabs = data.get("tabs", [])
    for t in tabs:
        if "web.whatsapp.com" in t.get("url", ""):
            return t["tabId"]
    print("no WhatsApp Web tab open in brave-abang", file=sys.stderr)
    sys.exit(1)

SCRAPE_CHATS_JS = r"""(() => {
  const chats = [];
  const seen = new Set();
  // walk chat list rows, not loose span[title]s
  const list = document.querySelector('[aria-label="Chat list"], [data-testid="chat-list"]');
  const container = list || document.querySelector('#pane-side');
  if (!container) return JSON.stringify([]);
  const rows = container.querySelectorAll('[role="listitem"], [role="row"], div[tabindex="-1"]');
  rows.forEach(row => {
    const nameEl = row.querySelector('[data-testid="cell-frame-title"] span[title], span[title]');
    if (!nameEl || !nameEl.title) return;
    const name = nameEl.title;
    if (seen.has(name)) return;
    seen.add(name);
    let lastMsg = '';
    const msgArea = row.querySelector('[data-testid="cell-frame-secondary"]');
    if (msgArea) {
      lastMsg = (msgArea.textContent || '').replace(/(?:wds-)?ic-[a-z-]+/g, '').replace(/\d+$/g, '').trim().slice(0, 80);
    }
    const badge = row.querySelector('[data-testid="icon-unread-count"]');
    const unread = badge ? badge.textContent.trim() : '0';
    const timeArea = row.querySelector('[data-testid="cell-frame-primary-detail"]');
    const t = timeArea ? timeArea.textContent.replace(name, '').replace(/(?:wds-)?ic-[a-z-]+/g, '').trim() : '';
    chats.push({name, lastMsg, unread, time: t});
  });
  return JSON.stringify(chats.slice(0, 50));
})()"""

CLICK_CHAT_JS = r"""((chatName) => {
  const spans = document.querySelectorAll('span[title]');
  for (const s of spans) {
    if (s.title === chatName) {
      const row = s.closest('[role="row"], [role="listitem"], div[tabindex]');
      (row || s).click();
      return JSON.stringify({ok: true});
    }
  }
  return JSON.stringify({ok: false, error: 'chat not found: ' + chatName});
})"""

TYPE_MSG_JS = r"""((msg) => {
  const box = document.querySelector('[data-testid="conversation-compose-box-input"]')
    || document.querySelector('footer [contenteditable="true"]');
  if (!box) return JSON.stringify({ok: false, error: 'compose box not found'});
  box.focus();
  document.execCommand('insertText', false, msg);
  return JSON.stringify({ok: true});
})"""

CLICK_SEND_JS = r"""(() => {
  const icon = document.querySelector('[data-testid="wds-ic-send-filled"]');
  if (!icon) return JSON.stringify({ok: false, error: 'send button not found'});
  const btn = icon.closest('button') || icon.closest('[role="button"]') || icon;
  btn.click();
  return JSON.stringify({ok: true});
})()"""

def eval_js(tab, js):
    data = bbx("page.evaluate", {"expression": js}, tab_id=tab)
    val = data.get("value", "{}")
    try:
        return json.loads(val)
    except:
        return {"ok": False, "error": f"bad response: {val[:100]}"}

def cmd_get():
    tab = find_wa_tab()
    data = bbx("page.evaluate", {"expression": SCRAPE_CHATS_JS}, tab_id=tab)
    val = data.get("value", "[]")
    try:
        chats = json.loads(val)
    except:
        chats = []
    if not chats:
        print("no chats found (WA Web might not be fully loaded)")
        return
    for i, c in enumerate(chats, 1):
        unread = f" [{c.get('unread', '')}]" if c.get('unread', '0') != '0' else ''
        last = f" — {c.get('lastMsg', '')}" if c.get('lastMsg') else ''
        t = f" ({c.get('time', '')})" if c.get('time') else ''
        print(f"  {i:2}. {c['name']}{unread}{t}{last}")


READ_CHAT_JS = r"""((chatName) => {
  // click the chat first
  const spans = document.querySelectorAll('span[title]');
  let found = false;
  for (const s of spans) {
    if (s.title === chatName) {
      const row = s.closest('[role="row"], [role="listitem"], div[tabindex]');
      (row || s).click();
      found = true;
      break;
    }
  }
  if (!found) return JSON.stringify({ok: false, error: 'chat not found: ' + chatName});
  return JSON.stringify({ok: true, step: 'clicked'});
})"""

SCRAPE_MSGS_JS = r"""(() => {
  const msgs = [];
  const rows = document.querySelectorAll('[data-testid="msg-container"], div.message-in, div.message-out, [class*="message-"]');
  if (!rows.length) {
    // fallback: grab from conversation panel
    const panel = document.querySelector('#main [role="application"]') || document.querySelector('#main');
    if (!panel) return JSON.stringify([]);
    const bubbles = panel.querySelectorAll('[data-pre-plain-text], [class*="copyable-text"]');
    bubbles.forEach(b => {
      const pre = b.getAttribute('data-pre-plain-text') || '';
      const text = b.textContent.trim().slice(0, 200);
      msgs.push({meta: pre.trim(), text});
    });
    return JSON.stringify(msgs.slice(-20));
  }
  rows.forEach(row => {
    const copyable = row.querySelector('[class*="copyable-text"]');
    const pre = copyable ? (copyable.getAttribute('data-pre-plain-text') || '') : '';
    const textEl = row.querySelector('span[class*="selectable-text"]');
    const text = textEl ? textEl.textContent.trim().slice(0, 200) : '';
    if (text) msgs.push({meta: pre.trim(), text});
  });
  return JSON.stringify(msgs.slice(-20));
})()"""


def resolve_chat_name(name_or_index):
    """If it looks like a number, pull chat list and resolve by index."""
    try:
        idx = int(name_or_index)
    except ValueError:
        return name_or_index
    tab = find_wa_tab()
    data = bbx("page.evaluate", {"expression": SCRAPE_CHATS_JS}, tab_id=tab)
    try:
        chats = json.loads(data.get("value", "[]"))
    except:
        chats = []
    if idx < 1 or idx > len(chats):
        print(f"index {idx} out of range (1-{len(chats)})", file=sys.stderr)
        sys.exit(1)
    return chats[idx - 1]["name"]

def cmd_send(chat_name, msg):
    chat_name = resolve_chat_name(chat_name)
    tab = find_wa_tab()

    # step 1: click the chat
    click_js = f'{CLICK_CHAT_JS}({json.dumps(chat_name)})'
    r = eval_js(tab, click_js)
    if not r.get("ok"):
        print(f"error: {r.get('error')}", file=sys.stderr)
        sys.exit(1)

    time.sleep(1.2)

    # step 2: type the message
    type_js = f'{TYPE_MSG_JS}({json.dumps(msg)})'
    r = eval_js(tab, type_js)
    if not r.get("ok"):
        print(f"error: {r.get('error')}", file=sys.stderr)
        sys.exit(1)

    time.sleep(0.5)

    # step 3: click send
    r = eval_js(tab, CLICK_SEND_JS)
    if not r.get("ok"):
        # retry once
        time.sleep(1)
        r = eval_js(tab, CLICK_SEND_JS)
        if not r.get("ok"):
            print(f"error: {r.get('error')}", file=sys.stderr)
            sys.exit(1)

    print(f"✅ sent to {chat_name}")


def cmd_read(chat_name):
    chat_name = resolve_chat_name(chat_name)
    tab = find_wa_tab()

    # click the chat
    click_js = f'{READ_CHAT_JS}({json.dumps(chat_name)})'
    r = eval_js(tab, click_js)
    if not r.get("ok"):
        print(f"error: {r.get('error')}", file=sys.stderr)
        sys.exit(1)

    time.sleep(1.5)

    # scrape messages
    data = bbx("page.evaluate", {"expression": SCRAPE_MSGS_JS}, tab_id=tab)
    val = data.get("value", "[]")
    try:
        msgs = json.loads(val)
    except:
        msgs = []
    if not msgs:
        print("no messages found (chat might still be loading)")
        return
    print(f"--- {chat_name} (last {len(msgs)} messages) ---")
    for m in msgs:
        meta = m.get("meta", "")
        text = m.get("text", "")
        if meta:
            print(f"  {meta}")
            print(f"    {text}")
        else:
            print(f"  {text}")

def main():
    if len(sys.argv) < 2:
        print("ws — WhatsApp Web CLI")
        print("  ws get                     list chats")
        print("  ws send <chat> <message>   send a message")
        print("  ws read <chat>             read recent messages")
        sys.exit(0)
    cmd = sys.argv[1]
    if cmd == "get":
        cmd_get()
    elif cmd == "read":
        if len(sys.argv) < 3:
            print("usage: ws read <chat-name-or-number>")
            sys.exit(1)
        cmd_read(sys.argv[2])
    elif cmd == "send":
        if len(sys.argv) < 4:
            print("usage: ws send <chat-name> <message>")
            sys.exit(1)
        cmd_send(sys.argv[2], " ".join(sys.argv[3:]))
    else:
        print(f"unknown: {cmd}. use: get | send")
        sys.exit(1)

if __name__ == "__main__":
    main()
