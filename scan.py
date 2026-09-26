#!/usr/bin/env python3
"""Find recent Claude, Grok, Codex and Cursor sessions, and resume one.

The panel only needs a title, a directory and an id. Transcripts stay where
the tool left them. `list` prints those records as JSON. `clients` describes
open windows well enough to recognize a session that is already running in
one: every process inside the window, the files they have open, and the
session ids the tools record per process.
`launch` and `focus` do the two ways of going back to one.
"""

import fcntl
import json
import os
import re
import shlex
import shutil
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

CLAUDE_LIMIT = 40
GROK_LIMIT = 40
CODEX_LIMIT = 30
CURSOR_LIMIT = 30
HEAD_LINES = 400
TAIL_BYTES = 65536
MAX_LINE_BYTES = 256 * 1024
TITLE_CHARS = 160

META_PREFIXES = ("<",)
USER_QUERY_RE = re.compile(r"<user_query>\s*(.*?)\s*</user_query>", re.DOTALL)


def home_dir():
    return Path(os.environ.get("HOME") or str(Path.home()))


def one_line(value, limit=TITLE_CHARS):
    text = " ".join(str(value or "").split())
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, str):
                parts.append(block)
            elif isinstance(block, dict) and block.get("type") == "text" and isinstance(block.get("text"), str):
                parts.append(block["text"])
        return "\n".join(parts)
    return ""


def usable_text(value):
    text = text_of(value) if not isinstance(value, str) else value
    # Cursor wraps what was typed in <user_query>, after a timestamp tag.
    # The tag itself is not the title.
    match = USER_QUERY_RE.search(text or "")
    if match:
        text = match.group(1)
    text = one_line(text)
    if not text or text.startswith(META_PREFIXES):
        return ""
    return text


def load_line(line):
    if len(line) > MAX_LINE_BYTES:
        return None
    try:
        value = json.loads(line)
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) else None


def read_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeDecodeError):
        return None


def subdirs(path):
    """Real directories directly under `path`. Symlinks are not followed."""
    try:
        children = list(Path(path).iterdir())
    except OSError:
        return []
    return [child for child in children if child.is_dir() and not child.is_symlink()]


def newest(found, limit):
    """The `limit` most recently modified paths, from (mtime, ...) tuples."""
    found.sort(key=lambda item: item[0], reverse=True)
    return found[:limit]


def mtime_of(path):
    try:
        return path.stat().st_mtime
    except OSError:
        return None


def claude_raw(path):
    """cwd, the first real thing the user typed, and any title the file names."""
    path = Path(path)
    cwd = ""
    first_user = ""
    titles = {"customTitle": "", "aiTitle": "", "summary": ""}
    title_fields = {
        "custom-title": "customTitle",
        "ai-title": "aiTitle",
        "summary": "summary",
    }
    try:
        stat = path.stat()
    except OSError:
        return None
    size = stat.st_size
    mtime_ms = int(stat.st_mtime * 1000)

    def take(record):
        nonlocal cwd, first_user
        if not cwd and isinstance(record.get("cwd"), str):
            cwd = record["cwd"]
        field = title_fields.get(record.get("type"))
        if field and isinstance(record.get(field), str):
            titles[field] = one_line(record[field])
        if first_user or record.get("type") != "user":
            return
        message = record.get("message")
        content = message.get("content") if isinstance(message, dict) else record.get("content")
        first_user = usable_text(content) or first_user

    try:
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            for index, line in enumerate(handle):
                if index >= HEAD_LINES and first_user and cwd:
                    break
                if index >= HEAD_LINES * 4:
                    break
                record = load_line(line)
                if record:
                    take(record)
            if size > TAIL_BYTES:
                handle.seek(max(0, size - TAIL_BYTES))
                handle.readline()  # the seek lands mid-line
                for line in handle:
                    record = load_line(line)
                    if record:
                        take(record)
    except OSError:
        return None

    if not (first_user or any(titles.values())):
        return None
    return {
        "tool": "claude",
        "id": path.stem,
        "cwd": cwd,
        "updated": mtime_ms,
        "firstUser": first_user,
        "customTitle": titles["customTitle"],
        "aiTitle": titles["aiTitle"],
        "summary": titles["summary"],
    }


def newest_files(root, limit, match):
    found = []
    for project in subdirs(root):
        try:
            children = list(project.iterdir())
        except OSError:
            continue
        for child in children:
            if child.is_symlink() or not child.is_file() or not match(child):
                continue
            mtime = mtime_of(child)
            if mtime is not None:
                found.append((mtime, child))
    return [path for _, path in newest(found, limit)]


def claude_project_cwd(project_name, list_dir):
    """The directory encoded in `~/.claude/projects/-home-kimm-Projects-notes`."""
    encoded = str(project_name or "")
    if encoded.startswith("-"):
        encoded = encoded[1:]
    return resolve_dashed_path(encoded, list_dir)


def claude_sessions(root):
    sessions = []
    for path in newest_files(root, CLAUDE_LIMIT, lambda path: path.suffix == ".jsonl"):
        raw = claude_raw(path)
        if not raw:
            continue
        if not raw.get("cwd"):
            raw["cwd"] = claude_project_cwd(path.parent.name, fs_list_dir)
        sessions.append(raw)
    return sessions


def grok_raw(summary_path):
    summary_path = Path(summary_path)
    data = read_json(summary_path)
    mtime = mtime_of(summary_path)
    if not isinstance(data, dict) or mtime is None:
        return None
    mtime_ms = int(mtime * 1000)
    info = data.get("info") if isinstance(data.get("info"), dict) else {}
    cwd = info.get("cwd") if isinstance(info.get("cwd"), str) else ""
    if not cwd:
        cwd = urllib.parse.unquote(summary_path.parent.parent.name)
    title = one_line(data.get("generated_title") or data.get("session_summary") or "")
    if not title:
        return None
    updated = data.get("last_active_at") or data.get("updated_at") or mtime_ms
    session_id = info.get("id") if isinstance(info.get("id"), str) and info.get("id") else summary_path.parent.name
    return {
        "tool": "grok",
        "id": session_id,
        "cwd": cwd,
        "updated": updated,
        "generatedTitle": title,
    }


def grok_session_dirs(root):
    """Grok keeps one directory per session under one per cwd:
    sessions/<cwd>/<id>/."""
    for cwd_dir in subdirs(root):
        yield from subdirs(cwd_dir)


def grok_sessions(root):
    found = []
    for session_dir in grok_session_dirs(root):
        summary = session_dir / "summary.json"
        mtime = mtime_of(summary) if summary.is_file() else None
        if mtime is not None:
            found.append((mtime, summary))
    sessions = []
    for _, summary in newest(found, GROK_LIMIT):
        raw = grok_raw(summary)
        if raw:
            sessions.append(raw)
    return sessions


def resolve_dashed_path(encoded, list_dir):
    """Turn Cursor's `home-kimm-Projects-omarchy-notes` back into a real path.

    `list_dir(path)` returns the directory names in that path. The longest
    name that matches the remaining text wins, so `omarchy-notes` stays one
    directory rather than becoming `omarchy/notes`.
    """
    rest = str(encoded or "").strip().strip("-")
    if not rest:
        return ""
    current = "/"
    while rest:
        try:
            names = list(list_dir(current) or [])
        except OSError:
            return ""
        matches = [name for name in names if rest == name or rest.startswith(name + "-")]
        if not matches:
            return ""
        name = max(matches, key=len)
        current = "/" + name if current == "/" else current.rstrip("/") + "/" + name
        rest = rest[len(name):]
        if rest.startswith("-"):
            rest = rest[1:]
    return current


def fs_list_dir(path):
    return [child.name for child in subdirs(path)]


# What Cursor calls a chat before it has named it.
CURSOR_PLACEHOLDER_TITLES = {"New Agent", "New Chat"}


def cursor_raw(transcript, encoded, cwd, meta=None):
    """The first prompt and answer from a transcript, and the title and
    folder Cursor keeps for the chat in its meta.json."""
    transcript = Path(transcript)
    mtime = mtime_of(transcript)
    if mtime is None:
        return None
    mtime_ms = int(mtime * 1000)
    first_user = ""
    first_reply = ""
    try:
        with transcript.open("r", encoding="utf-8", errors="replace") as handle:
            for index, line in enumerate(handle):
                if index >= HEAD_LINES or first_reply:
                    break
                record = load_line(line)
                role = record.get("role") if record else None
                message = record.get("message") if record else None
                content = message.get("content") if isinstance(message, dict) else ""
                if role == "user" and not first_user:
                    first_user = usable_text(content)
                elif role == "assistant" and first_user:
                    first_reply = usable_text(content)
    except OSError:
        return None
    meta = meta if isinstance(meta, dict) else {}
    title = one_line(meta.get("title") if isinstance(meta.get("title"), str) else "")
    if title in CURSOR_PLACEHOLDER_TITLES:
        title = ""
    if isinstance(meta.get("cwd"), str) and meta["cwd"]:
        cwd = meta["cwd"]
    if not (first_user or title):
        return None
    fallback = encoded.split("-")[-1] if encoded else ""
    return {
        "tool": "cursor",
        "id": transcript.stem,
        "cwd": cwd,
        "fallback": "" if cwd else fallback,
        "updated": mtime_ms,
        "title": title,
        "firstUser": first_user,
        "firstReply": first_reply,
    }


def cursor_chat_meta(chats_root):
    """{chat id: meta.json} for every chat under ~/.config/cursor/chats/<hash>/<id>/."""
    metas = {}
    for workspace in subdirs(chats_root):
        for chat in subdirs(workspace):
            meta = read_json(chat / "meta.json")
            if isinstance(meta, dict):
                metas[chat.name] = meta
    return metas


def cursor_sessions(root, list_dir=fs_list_dir, chats_root=None):
    # Transcripts sit at projects/<project>/agent-transcripts/<id>/<id>.jsonl.
    found = []
    for project in subdirs(root):
        for session_dir in subdirs(project / "agent-transcripts"):
            transcript = session_dir / (session_dir.name + ".jsonl")
            if not transcript.is_file() or transcript.is_symlink():
                continue
            mtime = mtime_of(transcript)
            if mtime is not None:
                found.append((mtime, project.name, transcript))
    metas = cursor_chat_meta(chats_root) if chats_root else {}
    sessions = []
    for _, encoded, transcript in newest(found, CURSOR_LIMIT):
        cwd = resolve_dashed_path(encoded, list_dir)
        raw = cursor_raw(transcript, encoded, cwd, metas.get(transcript.stem))
        if raw:
            sessions.append(raw)
    return sessions


def codex_database(root):
    root = Path(root)
    best = None
    best_version = -1
    if not root.is_dir():
        return None
    try:
        children = list(root.iterdir())
    except OSError:
        return None
    for child in children:
        name = child.name
        if not name.startswith("state_") or not name.endswith(".sqlite"):
            continue
        if not child.is_file() or child.is_symlink():
            continue
        version = name[len("state_"): -len(".sqlite")]
        if version.isdigit() and int(version) > best_version:
            best_version = int(version)
            best = child
    return best


def codex_sessions(root):
    database = codex_database(root)
    if database is None:
        return []
    try:
        connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True, timeout=1)
    except sqlite3.Error:
        return []
    try:
        columns = {row[1] for row in connection.execute("PRAGMA table_info(threads)")}
        required = {"id", "cwd", "archived"}
        if not required.issubset(columns):
            return []
        updated = "updated_at_ms" if "updated_at_ms" in columns else "updated_at" if "updated_at" in columns else None
        if updated is None:
            return []
        title = "title" if "title" in columns else "''"
        first = "first_user_message" if "first_user_message" in columns else "''"
        rows = connection.execute(
            f"SELECT id, cwd, {updated}, {title}, {first} FROM threads "
            f"WHERE archived = 0 ORDER BY {updated} DESC LIMIT ?",
            (CODEX_LIMIT,),
        )
        sessions = []
        for session_id, cwd, updated_at, raw_title, first_user in rows:
            if not isinstance(session_id, str) or not session_id:
                continue
            title = one_line(raw_title if isinstance(raw_title, str) else "")
            first_text = "" if title else one_line(first_user if isinstance(first_user, str) else "")
            if not title and not first_text:
                continue
            sessions.append({
                "tool": "codex",
                "id": session_id,
                "cwd": cwd if isinstance(cwd, str) else "",
                "updated": updated_at,
                "title": title,
                "firstUser": first_text,
            })
        return sessions
    except sqlite3.Error:
        return []
    finally:
        connection.close()


def model_bucket(bucket):
    def num(key, *alts):
        for name in (key,) + alts:
            value = bucket.get(name)
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                continue
            if value < 0:
                return 0
            return int(value)
        return 0

    return {
        "input": num("inputTokens"),
        "output": num("outputTokens"),
        "cacheRead": num("cacheReadInputTokens", "cachedReadTokens"),
        "cacheWrite": num("cacheCreationInputTokens", "cacheCreationTokens"),
        "costTicks": num("costUsdTicks"),
    }


def models_from(model_usage):
    """`{"model-id": {tokens...}}` as a list of slim per-model buckets."""
    if not isinstance(model_usage, dict):
        return []
    return [
        {"id": str(model_id), **model_bucket(bucket)}
        for model_id, bucket in model_usage.items()
        if model_id and isinstance(bucket, dict)
    ]


def whole(value):
    try:
        return max(0, int(value or 0))
    except (TypeError, ValueError):
        return 0


def slim_subscription(record):
    models = models_from(record.get("modelUsage"))
    limits = []
    for item in record.get("limits") or []:
        if not isinstance(item, dict):
            continue
        try:
            percent = float(item.get("percent"))
        except (TypeError, ValueError):
            continue
        limits.append({
            "label": str(item.get("label") or ""),
            "percent": percent,
            "resetsAt": str(item.get("resetsAt") or ""),
        })
    days = []
    for item in record.get("recentDays") or []:
        if isinstance(item, dict) and isinstance(item.get("date"), str):
            # The record calls it messageCount, but it is the day's tokens.
            days.append({"date": item["date"], "tokens": whole(item.get("messageCount"))})
    return {
        "id": str(record.get("id") or ""),
        "name": str(record.get("name") or record.get("id") or ""),
        "tier": str(record.get("tierLabel") or ""),
        "todayTokens": whole(record.get("todayTotalTokens")),
        "todayPrompts": whole(record.get("todayPrompts")),
        "todaySessions": whole(record.get("todaySessions")),
        "days": days,
        # Why the numbers are missing or partial, and what to do about it.
        "status": str(record.get("usageStatusText") or ""),
        "help": "" if record.get("ready", True) else str(record.get("authHelpText") or ""),
        "limits": limits,
        "models": models,
    }


def state_dir(home):
    configured = os.environ.get("XDG_STATE_HOME")
    if configured:
        return Path(configured)
    return Path(home) / ".local" / "state"


def grok_machine_usage(root):
    """Per-session model usage from ~/.grok/sessions/*/*/usage.json."""
    found = []
    for session_dir in grok_session_dirs(root):
        usage = session_dir / "usage.json"
        if usage.is_symlink() or not usage.is_file():
            continue
        data = read_json(usage)
        session = data.get("session") if isinstance(data, dict) else None
        if not isinstance(session, dict):
            continue
        models = models_from(session.get("modelUsage"))
        if not models and session.get("primaryModelId"):
            models.append({"id": str(session["primaryModelId"]), **model_bucket(session)})
        if models:
            found.append({"models": models, "day": session_day(session_dir)})
    return found


def session_day(session_dir):
    """The local date a Grok session was last active, for the per-day chart."""
    summary = read_json(session_dir / "summary.json")
    stamp = summary.get("last_active_at") if isinstance(summary, dict) else None
    try:
        when = datetime.fromisoformat(str(stamp).replace("Z", "+00:00")).astimezone()
    except ValueError:
        mtime = mtime_of(session_dir / "usage.json")
        if mtime is None:
            return ""
        when = datetime.fromtimestamp(mtime)
    return when.strftime("%Y-%m-%d")


def refresh_omarchy_records():
    """Have Omarchy's own collectors rewrite the Claude, Codex and Fireworks
    records. The Agents bar widget used to run this; with Sessions in its
    place, the records would otherwise go stale."""
    if shutil.which("omarchy-agent-usage-update") is None:
        return
    try:
        subprocess.run(["omarchy-agent-usage-update"], check=False, capture_output=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        pass


def omarchy_subscriptions(usage_dir):
    """The records Omarchy writes for its agents panel, one file per subscription."""
    subscriptions = []
    if not usage_dir.is_dir():
        return subscriptions
    for path in sorted(usage_dir.glob("*.json")):
        if path.is_symlink() or not path.is_file():
            continue
        record = read_json(path)
        if isinstance(record, dict) and record.get("id"):
            subscriptions.append(slim_subscription(record))
    return subscriptions


def collect_usage(home=None):
    """Subscription limits Omarchy already collected, plus Grok's own session files.

    Grok has no quota file on disk. Its per-model numbers are the sum of the
    usage records under ~/.grok/sessions, which is this machine rather than
    the account. Grok's weekly allowance and Cursor's monthly plan are
    fetched, side by side so one slow request does not wait on the other.
    """
    if home is None:
        home = home_dir()
        usage_root = state_dir(home)
        refresh_omarchy_records()
    else:
        # An explicit home is a test fixture: ignore the real XDG_STATE_HOME.
        home = Path(home)
        usage_root = home / ".local" / "state"
    with ThreadPoolExecutor(max_workers=2) as pool:
        grok_fetch = pool.submit(grok_allowance, home)
        cursor_fetch = pool.submit(cursor_allowance, home)
        subscriptions = omarchy_subscriptions(usage_root / "omarchy" / "agents" / "usage")
        grok = grok_machine_usage(home / ".grok" / "sessions")
        return {
            "subscriptions": subscriptions,
            "grok": grok,
            "allowance": grok_fetch.result(),
            "cursor": cursor_fetch.result(),
        }


def usage_cache_path():
    root = os.environ.get("XDG_CACHE_HOME") or str(home_dir() / ".cache")
    return Path(root) / "omarchy" / "sessions" / "usage.json"


def cached_usage(max_age=None, path=None, collect=None):
    """Usage, from the shared cache while it is younger than `max_age`
    seconds, else collected afresh and written back.

    Every monitor's bar asks at once when the shell starts. A lock makes the
    later ones wait for the first, then find its fresh cache, so Grok and
    Cursor are asked once however many bars there are. Without `max_age` the
    numbers are always collected; the panel wants them current.
    """
    path = Path(path) if path else usage_cache_path()
    collect = collect or collect_usage
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path.with_suffix(".lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if max_age is not None:
            age = time.time() - (mtime_of(path) or 0)
            cached = read_json(path) if age < max_age else None
            if isinstance(cached, dict):
                return cached
        usage = collect()
        partial = path.with_suffix(".tmp")
        partial.write_text(json.dumps(usage), encoding="utf-8")
        partial.replace(path)
        return usage


def percent_fraction(value):
    """The billing API reports 69.0 for 69 percent. The panel stores a fraction."""
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if number < 0:
        return None
    return number / 100.0


def parse_grok_allowance(config):
    if not isinstance(config, dict) or "creditUsagePercent" not in config:
        return None
    percent = percent_fraction(config.get("creditUsagePercent"))
    if percent is None:
        return None
    period = config.get("currentPeriod") if isinstance(config.get("currentPeriod"), dict) else {}
    resets = period.get("end") or config.get("billingPeriodEnd") or ""
    products = []
    for item in config.get("productUsage") or []:
        if not isinstance(item, dict):
            continue
        share = percent_fraction(item.get("usagePercent"))
        name = item.get("product")
        if share is None or not name:
            continue
        products.append({"name": str(name), "percent": share})
    return {"percent": percent, "resetsAt": str(resets), "products": products}


def allowance_from_log(path):
    path = Path(path)
    if not path.is_file():
        return None
    try:
        data = path.read_bytes()
    except OSError:
        return None
    text = data[-400_000:].decode("utf-8", "replace")
    found = None
    for line in text.splitlines():
        if "creditUsagePercent" not in line:
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        ctx = record.get("ctx") if isinstance(record, dict) else None
        config = ctx.get("config") if isinstance(ctx, dict) else None
        parsed = parse_grok_allowance(config if isinstance(config, dict) else record)
        if parsed:
            found = parsed
    return found


def fetch_grok_allowance(auth_path):
    stored = read_json(auth_path)
    token = ""
    if isinstance(stored, dict):
        for value in stored.values():
            if isinstance(value, dict) and isinstance(value.get("key"), str):
                token = value["key"]
                break
    if not token:
        return None
    request = urllib.request.Request(
        "https://cli-chat-proxy.grok.com/v1/billing?format=credits",
        headers={"Authorization": "Bearer " + token, "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (OSError, urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return None
    config = payload.get("config") if isinstance(payload, dict) else None
    return parse_grok_allowance(config)


def epoch_to_iso(value):
    if value is None or value == "":
        return ""
    try:
        number = float(value)
    except (TypeError, ValueError):
        return str(value)
    if number > 10_000_000_000:
        number = number / 1000.0
    return datetime.fromtimestamp(number, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_cursor_allowance(usage, plan):
    """The same figures the `agent` /usage screen draws.

    Percents arrive as 7.49 for 7.49 percent. On-demand is off when the
    account has no personal spend limit.
    """
    if not isinstance(usage, dict):
        return None
    plan_usage = usage.get("planUsage")
    if not isinstance(plan_usage, dict) or "totalPercentUsed" not in plan_usage:
        return None
    included = percent_fraction(plan_usage.get("totalPercentUsed"))
    if included is None:
        return None
    products = []
    for key, name in (("autoPercentUsed", "Auto"), ("apiPercentUsed", "API")):
        share = percent_fraction(plan_usage.get(key))
        if share is None:
            continue
        products.append({"name": name, "percent": share})
    spend = usage.get("spendLimitUsage") if isinstance(usage.get("spendLimitUsage"), dict) else {}
    limit = spend.get("individualLimit")
    on_demand = "on" if isinstance(limit, (int, float)) and not isinstance(limit, bool) and limit > 0 else "off"
    info = {}
    if isinstance(plan, dict) and isinstance(plan.get("planInfo"), dict):
        info = plan["planInfo"]
    resets = usage.get("billingCycleEnd") or info.get("billingCycleEnd") or ""
    return {
        "percent": included,
        "resetsAt": epoch_to_iso(resets),
        "plan": str(info.get("planName") or ""),
        "products": products,
        "onDemand": on_demand,
    }


def cursor_rpc(token, method):
    request = urllib.request.Request(
        "https://api2.cursor.sh/aiserver.v1.DashboardService/" + method,
        data=b"{}",
        method="POST",
        headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json",
            "Connect-Protocol-Version": "1",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=8) as response:
        payload = json.loads(response.read().decode("utf-8"))
    return payload if isinstance(payload, dict) else None


def fetch_cursor_allowance(auth_path):
    stored = read_json(auth_path)
    token = stored.get("accessToken") if isinstance(stored, dict) else ""
    if not isinstance(token, str) or not token:
        return None
    try:
        usage = cursor_rpc(token, "GetCurrentPeriodUsage")
        plan = cursor_rpc(token, "GetPlanInfo")
    except (OSError, urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return None
    return parse_cursor_allowance(usage, plan)


def cursor_allowance(home):
    return fetch_cursor_allowance(Path(home) / ".config" / "cursor" / "auth.json")


def grok_allowance(home):
    home = Path(home)
    live = fetch_grok_allowance(home / ".grok" / "auth.json")
    if live:
        return live
    return allowance_from_log(home / ".grok" / "logs" / "unified.jsonl")


def collect(home=None):
    home = Path(home) if home else home_dir()
    sessions = []
    warnings = []
    readers = (
        ("claude", lambda: claude_sessions(home / ".claude" / "projects")),
        ("grok", lambda: grok_sessions(home / ".grok" / "sessions")),
        ("codex", lambda: codex_sessions(home / ".codex")),
        ("cursor", lambda: cursor_sessions(home / ".cursor" / "projects",
                                           chats_root=home / ".config" / "cursor" / "chats")),
    )
    for name, read in readers:
        try:
            sessions.extend(read())
        except Exception as exc:  # one tool being unreadable leaves the others
            warnings.append(f"{name}: {exc}")
    return {"sessions": sessions, "warnings": warnings}


CURSOR_CONVERSATION_RE = re.compile(r'"conversationId"\s*:\s*"([^"]+)"')
CURSOR_LOG_TAIL = 262144


def process_cmdline(pid):
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        return ""
    return raw.replace(b"\x00", b" ").decode("utf-8", "replace").strip()


def process_parents():
    """Every visible process's parent, as {pid: ppid}."""
    parents = {}
    try:
        entries = os.listdir("/proc")
    except OSError:
        return parents
    for entry in entries:
        if not entry.isdigit():
            continue
        try:
            stat = Path(f"/proc/{entry}/stat").read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        # The command name sits in parentheses and may itself hold spaces.
        fields = stat[stat.rfind(")") + 2:].split()
        if len(fields) > 1 and fields[1].isdigit():
            parents[int(entry)] = int(fields[1])
    return parents


def process_tree(pid, parents):
    """`pid` and everything started under it."""
    children = {}
    for child, parent in parents.items():
        children.setdefault(parent, []).append(child)
    tree = []
    pending = [pid]
    while pending:
        current = pending.pop()
        if current in tree:
            continue
        tree.append(current)
        pending.extend(children.get(current, []))
    return tree


def open_files(pid):
    """Paths of the regular files a process has open."""
    paths = []
    try:
        fds = os.listdir(f"/proc/{pid}/fd")
    except OSError:
        return paths
    for fd in fds:
        try:
            target = os.readlink(f"/proc/{pid}/fd/{fd}")
        except OSError:
            continue
        if target.startswith("/"):
            paths.append(target)
    return paths


def claude_running(home):
    """{pid: session id} from the file Claude keeps per live process."""
    running = {}
    for path in Path(home, ".claude", "sessions").glob("*.json"):
        record = read_json(path)
        if isinstance(record, dict) and isinstance(record.get("pid"), int) and record.get("sessionId"):
            running[record["pid"]] = str(record["sessionId"])
    return running


def grok_running(home):
    """{pid: session id} from Grok's list of open sessions."""
    running = {}
    records = read_json(Path(home, ".grok", "active_sessions.json"))
    for record in records if isinstance(records, list) else []:
        if isinstance(record, dict) and isinstance(record.get("pid"), int) and record.get("session_id"):
            running[record["pid"]] = str(record["session_id"])
    return running


def cursor_log_conversation(path):
    """The conversation an `agent` log was last writing about."""
    path = Path(path)
    if "cursor-agent-logs" not in str(path.parent) or path.suffix != ".log":
        return ""
    try:
        size = path.stat().st_size
        with path.open("rb") as handle:
            handle.seek(max(0, size - CURSOR_LOG_TAIL))
            text = handle.read().decode("utf-8", "replace")
    except OSError:
        return ""
    found = CURSOR_CONVERSATION_RE.findall(text)
    return found[-1] if found else ""


def process_marks(pid, running):
    """Everything about one process that can carry a session id: its command
    line, the files it has open, and what the tools record for that pid."""
    marks = [process_cmdline(pid)]
    if pid in running:
        marks.append(running[pid])
    for path in open_files(pid):
        marks.append(path)
        conversation = cursor_log_conversation(path)
        if conversation:
            marks.append(conversation)
    return [mark for mark in marks if mark]


def run_json(command, timeout=3):
    try:
        completed = subprocess.run(command, check=False, capture_output=True, text=True, timeout=timeout)
        return json.loads(completed.stdout or "null")
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return None


def herdr_panes():
    """Every herdr pane with the pid of the shell it runs, from herdr's own
    socket API. Empty when herdr is not installed or not running."""
    if shutil.which("herdr") is None:
        return []
    listing = run_json(["herdr", "pane", "list"])
    result = listing.get("result") if isinstance(listing, dict) else None
    panes = []
    for pane in (result or {}).get("panes") or []:
        if not isinstance(pane, dict) or not pane.get("pane_id"):
            continue
        info = run_json(["herdr", "pane", "process-info", "--pane", str(pane["pane_id"])])
        details = ((info or {}).get("result") or {}).get("process_info") or {}
        shell = details.get("shell_pid")
        if isinstance(shell, int) and shell > 0:
            panes.append({
                "kind": "herdr",
                "pane": str(pane["pane_id"]),
                "tab": str(pane.get("tab_id") or ""),
                "workspace": str(pane.get("workspace_id") or ""),
                "shell": shell,
                "clients": [],
            })
    return panes


def tmux_panes(run=None):
    """Every tmux pane with its shell pid and the pids of the clients attached
    to its session. tmux's server is a daemon outside every window, so a pane
    is found in a window through the client attached to it."""
    if shutil.which("tmux") is None:
        return []
    run = run or run_text
    code, listing = run(["tmux", "list-panes", "-a", "-F",
                         "#{pane_pid}\t#{pane_id}\t#{session_name}:#{window_index}\t#{session_name}"])
    if code != 0:
        return []
    code, attached = run(["tmux", "list-clients", "-F", "#{client_pid}\t#{client_session}"])
    clients = {}
    for line in attached.splitlines() if code == 0 else []:
        pid, _, session = line.partition("\t")
        if pid.isdigit():
            clients.setdefault(session, []).append(int(pid))
    panes = []
    for line in listing.splitlines():
        parts = line.split("\t")
        if len(parts) != 4 or not parts[0].isdigit():
            continue
        panes.append({
            "kind": "tmux",
            "pane": parts[1],
            "tab": parts[2],
            "workspace": parts[3],
            "shell": int(parts[0]),
            "clients": clients.get(parts[3], []),
        })
    return panes


def run_text(command, timeout=5):
    """(exit code, stdout) of a command, or (-1, "") when it cannot run."""
    try:
        completed = subprocess.run(command, check=False, capture_output=True, text=True,
                                   timeout=timeout, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return -1, ""
    return completed.returncode, completed.stdout


def describe_windows(clients, parents, marks_of, panes=()):
    """Each window with the marks of every process running inside it.

    A terminal running as a server owns several windows under one pid. Its
    children cannot be told apart by window, so such a pid only contributes
    its own command line.

    A multiplexer's panes that run inside the window are listed on it with
    their own marks, so a session can be brought forward in its pane and not
    only its window: a herdr pane by its shell, a tmux pane by the client
    attached to its session.
    """
    pids = [client.get("pid") for client in clients if isinstance(client, dict)]
    described = []
    for client in clients:
        if not isinstance(client, dict):
            continue
        address = client.get("address")
        pid = client.get("pid")
        if not isinstance(address, str) or not address:
            continue
        marks = []
        inside = []
        if isinstance(pid, int) and pid > 0:
            tree = process_tree(pid, parents) if pids.count(pid) == 1 else [pid]
            for member in tree:
                marks.extend(marks_of(member))
            for pane in panes:
                attached = [pid for pid in pane.get("clients") or [] if pid in tree]
                if pane["shell"] not in tree and not attached:
                    continue
                pane_marks = []
                for member in process_tree(pane["shell"], parents):
                    pane_marks.extend(marks_of(member))
                    # A tmux pane runs outside the window, so its marks count for the window too.
                    if attached:
                        marks.extend(marks_of(member))
                inside.append({
                    "kind": pane.get("kind", "herdr"),
                    "pane": pane["pane"],
                    "tab": pane["tab"],
                    "workspace": pane["workspace"],
                    "text": "\n".join(pane_marks),
                })
        described.append({"address": address, "text": "\n".join(marks), "panes": inside})
    return described


def window_clients(home=None):
    home = Path(home) if home else home_dir()
    clients = run_json(["hyprctl", "clients", "-j"])
    if not isinstance(clients, list):
        return []
    running = {**claude_running(home), **grok_running(home)}
    return describe_windows(clients, process_parents(), lambda pid: process_marks(pid, running),
                            herdr_panes() + tmux_panes())


def launch(cwd, argv, spawn=None):
    """A new window of the desktop's terminal, in `cwd`, running `argv`."""
    if not argv:
        return {"ok": False, "error": "nothing to run"}
    binary = argv[0]
    if shutil.which(binary) is None and not Path(binary).is_file():
        return {"ok": False, "error": binary + " is not installed"}
    command = ["uwsm-app", "--", "xdg-terminal-exec"]
    if cwd:
        command.append("--dir=" + cwd)
    command.extend(argv)
    try:
        if spawn:
            spawn(command)
        else:
            subprocess.Popen(command, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError as exc:
        return {"ok": False, "error": str(exc)}
    return {"ok": True}


def focus_commands(address):
    """Hyprland with a Lua config takes `hl.dsp.focus`; older ones only
    know `focuswindow`. Both are tried, in that order, as Omarchy does."""
    target = "address:" + address
    return [
        ["hyprctl", "dispatch", 'hl.dsp.focus({ window = "%s" })' % target],
        ["hyprctl", "dispatch", "focuswindow", target],
    ]


def focus_pane(kind, pane, tab, workspace):
    """Bring a multiplexer's pane forward inside its window. A herdr pane
    directly when herdr sees an agent in it, otherwise by workspace and tab;
    a tmux pane by its window and then the pane."""
    if not pane:
        return False
    if kind == "tmux":
        if shutil.which("tmux") is None:
            return False
        ok = run_text(["tmux", "select-window", "-t", tab])[0] == 0 if tab else True
        return run_text(["tmux", "select-pane", "-t", pane])[0] == 0 and ok
    if shutil.which("herdr") is None:
        return False
    agent = run_json(["herdr", "agent", "focus", pane])
    if isinstance(agent, dict) and agent.get("result"):
        return True
    ok = True
    if workspace:
        ok = isinstance(run_json(["herdr", "workspace", "focus", workspace]), dict) and ok
    if tab:
        ok = isinstance(run_json(["herdr", "tab", "focus", tab]), dict) and ok
    return ok and bool(workspace or tab)


def focus(address, kind="", pane="", tab="", workspace=""):
    if not address or not re.fullmatch(r"0x[0-9a-fA-F]+", str(address)):
        return {"ok": False, "error": "not a window"}
    error = "could not focus that window"
    for command in focus_commands(address):
        try:
            completed = subprocess.run(command, check=False, capture_output=True, text=True, timeout=3)
        except (OSError, subprocess.TimeoutExpired) as exc:
            error = str(exc)
            continue
        if completed.returncode == 0 and completed.stdout.strip() == "ok":
            # The window is forward either way; a pane that will not come
            # forward still leaves you in the right terminal.
            if pane:
                focus_pane(kind, pane, tab, workspace)
            return {"ok": True}
    return {"ok": False, "error": error}


# ---------------------------------------------------------------- opening

# Where a session can open, in the order the chooser offers them. A plain
# terminal is always there; the others when installed.
APPS = ("herdr", "tmux", "terminal")


def apps_path():
    return state_dir(home_dir()) / "omarchy" / "sessions" / "apps.json"


def available_apps(which=shutil.which):
    return [app for app in APPS if app == "terminal" or which(app) is not None]


def read_apps(path=None):
    data = read_json(path or apps_path())
    data = data if isinstance(data, dict) else {}
    sessions = data.get("sessions") if isinstance(data.get("sessions"), dict) else {}
    return {
        "default": str(data.get("default") or ""),
        "sessions": {str(k): str(v) for k, v in sessions.items() if v in APPS},
    }


def write_apps(data, path=None):
    path = Path(path or apps_path())
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_suffix(".tmp")
    partial.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")
    partial.replace(path)


def apps_state(path=None, which=shutil.which):
    """What the panel needs to pick an app: the installed ones, the default
    (herdr when installed unless set otherwise) and each session's own."""
    available = available_apps(which)
    stored = read_apps(path)
    default = stored["default"] if stored["default"] in available else available[0]
    return {"available": available, "default": default, "sessions": stored["sessions"]}


def remember_apps(pairs, path=None):
    """Record `id=app` pairs: where each session was opened or found running."""
    stored = read_apps(path)
    changed = 0
    for pair in pairs:
        session_id, _, app = str(pair).partition("=")
        if app in APPS and SESSION_ID_RE.fullmatch(session_id) and stored["sessions"].get(session_id) != app:
            stored["sessions"][session_id] = app
            changed += 1
    if changed:
        write_apps(stored, path)
    return {"ok": True, "changed": changed}


def set_default_app(app, path=None):
    if app not in APPS:
        return {"ok": False, "error": "unknown app"}
    stored = read_apps(path)
    stored["default"] = app
    write_apps(stored, path)
    return {"ok": True}


def window_hosting(wanted, parents=None, clients=None):
    """The address of the first window with a process inside it for which
    `wanted(pid)` holds, or ""."""
    parents = parents if parents is not None else process_parents()
    clients = clients if clients is not None else run_json(["hyprctl", "clients", "-j"])
    for client in clients if isinstance(clients, list) else []:
        pid = client.get("pid") if isinstance(client, dict) else None
        if not isinstance(pid, int) or pid <= 0:
            continue
        if any(wanted(member) for member in process_tree(pid, parents)):
            return str(client.get("address") or "")
    return ""


def is_herdr_client(pid):
    """A herdr client process: `herdr` itself, not its server."""
    argv = process_cmdline(pid).split()
    return bool(argv) and os.path.basename(argv[0]) == "herdr" and "server" not in argv[1:2]


def herdr_open(cwd, title, argv, run=None, window=None, spawn=None, wait=5.0, succeeds=None):
    """Open a session in herdr: a new tab in the workspace named after its
    folder (herdr names workspaces after folders), or a new workspace when
    there is none, then the window holding herdr comes forward. With no herdr
    window open, a terminal running herdr is started first."""
    run = run or run_json
    # `pane run` answers with nothing but its exit status.
    succeeds = succeeds or (lambda command: run_text(command)[0] == 0)
    window = window or (lambda: window_hosting(is_herdr_client))
    spawn = spawn or (lambda command: subprocess.Popen(command, start_new_session=True,
                                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    address = window()
    if not address:
        spawn(["uwsm-app", "--", "xdg-terminal-exec", "herdr"])
        deadline = time.time() + wait
        while not address and time.time() < deadline:
            time.sleep(0.2)
            address = window()
    label = Path(cwd).name if cwd else "home"
    workspaces = ((run(["herdr", "workspace", "list"]) or {}).get("result") or {}).get("workspaces") or []
    match = next((w for w in workspaces if isinstance(w, dict) and w.get("label") == label), None)
    if match:
        created = run(["herdr", "tab", "create", "--workspace", str(match.get("workspace_id")),
                       "--cwd", cwd or str(home_dir()), "--label", one_line(title, 30) or label, "--focus"])
    else:
        created = run(["herdr", "workspace", "create", "--cwd", cwd or str(home_dir()),
                       "--label", label, "--focus"])
    pane = (((created or {}).get("result") or {}).get("root_pane") or {}).get("pane_id")
    if not pane:
        return {"ok": False, "error": "herdr did not open a pane"}
    # herdr types the command into the pane's shell, so it goes as one quoted line.
    if not succeeds(["herdr", "pane", "run", str(pane), shlex.join(argv)]):
        return {"ok": False, "error": "herdr could not run it"}
    if address:
        focus(address)
    return {"ok": True}


def tmux_open(cwd, title, argv, run=None, window=None, spawn=None):
    """Open a session in tmux: a new window in the session a terminal is
    attached to, which then comes forward, or else a new tmux session in a new
    terminal."""
    run = run or run_text
    name = one_line(title, 30) or "session"
    command = shlex.join(argv)
    code, attached = run(["tmux", "list-clients", "-F", "#{client_pid}\t#{client_session}"])
    first = attached.splitlines()[0].split("\t") if code == 0 and attached.strip() else []
    if len(first) == 2 and first[0].isdigit():
        code, _ = run(["tmux", "new-window", "-t", first[1] + ":", "-c", cwd or str(home_dir()), "-n", name, command])
        if code != 0:
            return {"ok": False, "error": "tmux could not open a window"}
        client = int(first[0])
        address = (window or (lambda: window_hosting(lambda pid: pid == client)))()
        if address:
            focus(address)
        return {"ok": True}
    return launch(cwd, ["tmux", "new-session", "-c", cwd or str(home_dir()), "-n", name, command], spawn=spawn)


def open_session(app, cwd, title, session_id, argv, path=None, openers=None):
    """Open a session in `app` and remember that for it."""
    if not argv:
        return {"ok": False, "error": "nothing to run"}
    if shutil.which(argv[0]) is None and not Path(argv[0]).is_file():
        return {"ok": False, "error": argv[0] + " is not installed"}
    if openers is None:
        if app not in available_apps():
            return {"ok": False, "error": app + " is not installed"}
        openers = {
            "terminal": lambda: launch(cwd, argv),
            "herdr": lambda: herdr_open(cwd, title, argv),
            "tmux": lambda: tmux_open(cwd, title, argv),
        }
    if app not in openers:
        return {"ok": False, "error": "unknown app"}
    result = openers[app]()
    if result.get("ok") and session_id and session_id != "-":
        remember_apps([session_id + "=" + app], path)
    return result


# A session id as the tools write them: a UUID or something like it. Anything
# else, a path above all, is refused before a file is looked for.
SESSION_ID_RE = re.compile(r"[0-9A-Za-z][0-9A-Za-z_-]{7,127}")


def session_running(session_id, home):
    """Whether any process on the machine is running this session: on its
    command line, in a file it has open, or in what Claude and Grok record per
    process. Every process is looked at, not only those in a window, so a
    session in a background pane or job counts too."""
    running = {**claude_running(home), **grok_running(home)}
    if session_id in running.values():
        return True
    for pid in process_parents():
        if pid == os.getpid():
            continue
        for mark in process_marks(pid, running):
            if session_id in mark:
                return True
    return False


def session_files(tool, session_id, home):
    """Everything a tool keeps for one session, found under that tool's own
    folders by its exact id, and nothing a glob could reach beyond them."""
    home = Path(home)
    if tool == "claude":
        claude = home / ".claude"
        found = [p for project in subdirs(claude / "projects")
                 for p in (project / (session_id + ".jsonl"), project / session_id)]
        found += [claude / "file-history" / session_id, claude / "session-env" / session_id]
        found += list((claude / "todos").glob(glob_escape(session_id) + "-*.json"))
    elif tool == "grok":
        found = [cwd_dir / session_id for cwd_dir in subdirs(home / ".grok" / "sessions")]
    elif tool == "cursor":
        found = [project / "agent-transcripts" / session_id for project in subdirs(home / ".cursor" / "projects")]
        found += [chat / session_id for chat in subdirs(home / ".config" / "cursor" / "chats")]
    else:
        return []
    return [path for path in found if path.exists() and not path.is_symlink()]


def glob_escape(text):
    return re.sub(r"([*?\[])", r"[\1]", text)


def trash(path):
    """Into the desktop's trash, so a slip can be undone from there."""
    completed = subprocess.run(["gio", "trash", "--", str(path)], check=False, capture_output=True, text=True, timeout=10)
    if completed.returncode != 0:
        raise OSError(completed.stderr.strip() or "could not move it to the trash")


def delete_session(tool, session_id, home=None, running=session_running, discard=trash, codex=None):
    """Delete one session, never one that is still running.

    Claude, Grok and Cursor keep plain files, which go to the trash. Codex
    keeps its sessions in a database, so its own `codex delete` does it.
    """
    home = Path(home) if home else home_dir()
    if tool not in ("claude", "grok", "codex", "cursor"):
        return {"ok": False, "error": "unknown tool"}
    if not SESSION_ID_RE.fullmatch(str(session_id or "")):
        return {"ok": False, "error": "not a session id"}
    if running(session_id, home):
        return {"ok": False, "error": "still running; close it first"}
    if tool == "codex":
        return (codex or codex_delete)(session_id)
    paths = session_files(tool, session_id, home)
    if not paths:
        return {"ok": False, "error": "nothing found for that session"}
    try:
        for path in paths:
            discard(path)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"ok": False, "error": str(exc)}
    return {"ok": True, "removed": len(paths)}


def codex_delete(session_id):
    if shutil.which("codex") is None:
        return {"ok": False, "error": "codex is not installed"}
    try:
        completed = subprocess.run(["codex", "delete", session_id], check=False, capture_output=True,
                                   text=True, timeout=30, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"ok": False, "error": str(exc)}
    if completed.returncode != 0:
        said = (completed.stderr or completed.stdout).strip().splitlines()
        return {"ok": False, "error": said[-1] if said else "codex delete failed"}
    return {"ok": True}


def main(argv):
    command = argv[1] if len(argv) > 1 else "list"
    args = argv[2:]
    if command == "open" and len(args) < 5:
        # open <app> <cwd> <title> <session-id|-> <argv...>  -- an empty cwd is "".
        return reply({"ok": False, "error": "usage: open <app> <cwd> <title> <session-id|-> <argv...>"}, 1)
    commands = {
        "list": collect,
        # usage [--max-age <seconds>]
        "usage": lambda: cached_usage(float(args[1]) if args[:1] == ["--max-age"] and len(args) > 1 else None),
        "clients": window_clients,
        "apps": apps_state,
        "open": lambda: open_session(args[0], args[1], args[2], args[3], args[4:]),
        # remember <id>=<app> ...
        "remember": lambda: remember_apps(args),
        "set-default": lambda: set_default_app(args[0] if args else ""),
        # focus <address> [<kind> <pane> <tab> <workspace>]
        "focus": lambda: focus(*(args[:5] or [""])),
        # delete <tool> <id>
        "delete": lambda: delete_session(*(args[:2] + ["", ""])[:2]),
    }
    if command not in commands:
        return reply({"ok": False, "error": "unknown command"}, 1)
    return reply(commands[command]())


def reply(value, status=0):
    json.dump(value, sys.stdout)
    sys.stdout.write("\n")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv))
