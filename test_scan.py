#!/usr/bin/env python3
"""File-reading tests for scan.py. Model.js has its own suite."""

import json
import os
import tempfile
import unittest
from pathlib import Path

import scan


class DashedPath(unittest.TestCase):
    def test_claude_project_folder_decodes_the_same_way(self):
        tree = {
            "/": ["home"],
            "/home": ["kimm"],
            "/home/kimm": ["Projects"],
            "/home/kimm/Projects": ["omarchy-notes"],
        }
        self.assertEqual(
            scan.claude_project_cwd("-home-kimm-Projects-omarchy-notes", lambda path: tree.get(path, [])),
            "/home/kimm/Projects/omarchy-notes",
        )

    def test_hyphenated_directory_stays_whole(self):
        tree = {
            "/": ["home"],
            "/home": ["kimm"],
            "/home/kimm": ["Projects"],
            "/home/kimm/Projects": ["omarchy", "omarchy-notes"],
        }

        def list_dir(path):
            return tree.get(path, [])

        self.assertEqual(
            scan.resolve_dashed_path("home-kimm-Projects-omarchy-notes", list_dir),
            "/home/kimm/Projects/omarchy-notes",
        )

    def test_unknown_tail_returns_nothing(self):
        self.assertEqual(scan.resolve_dashed_path("home-missing", lambda path: ["home"] if path == "/" else []), "")


class Claude(unittest.TestCase):
    def test_title_fields_and_the_first_real_user_line(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl"
            records = [
                {"type": "system", "cwd": "/home/kimm/Projects/omarchy-notes", "content": "boot"},
                {"type": "user", "message": {"role": "user", "content": "<local-command>cwd</local-command>"}},
                {"type": "user", "message": {"role": "user", "content": [{"type": "text", "text": "Fix the overlap"}]}},
                {"type": "custom-title", "customTitle": "Overlap"},
            ]
            path.write_text("\n".join(json.dumps(record) for record in records), encoding="utf-8")
            raw = scan.claude_raw(path)
        self.assertEqual(raw["id"], "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        self.assertEqual(raw["cwd"], "/home/kimm/Projects/omarchy-notes")
        self.assertEqual(raw["firstUser"], "Fix the overlap")
        self.assertEqual(raw["customTitle"], "Overlap")

    def test_a_file_with_nothing_said_is_skipped(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "abc.jsonl"
            path.write_text(json.dumps({"type": "system", "cwd": "/tmp"}) + "\n", encoding="utf-8")
            self.assertIsNone(scan.claude_raw(path))


class Grok(unittest.TestCase):
    def test_summary_title_and_encoded_directory_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            session = Path(tmp) / "%2Fhome%2Fkimm%2FProjects%2Fcasino" / "01a0d96b-fa96-7e11-bfaa-53162f051fda"
            session.mkdir(parents=True)
            (session / "summary.json").write_text(json.dumps({
                "info": {"id": "01a0d96b-fa96-7e11-bfaa-53162f051fda"},
                "generated_title": "Reel timing",
                "last_active_at": "2026-09-25T11:50:00Z",
            }), encoding="utf-8")
            raw = scan.grok_raw(session / "summary.json")
        self.assertEqual(raw["cwd"], "/home/kimm/Projects/casino")
        self.assertEqual(raw["generatedTitle"], "Reel timing")
        self.assertEqual(raw["id"], "01a0d96b-fa96-7e11-bfaa-53162f051fda")

    def test_no_title_is_skipped(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "summary.json"
            path.write_text("{}", encoding="utf-8")
            self.assertIsNone(scan.grok_raw(path))


class Cursor(unittest.TestCase):
    def test_first_user_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            session = Path(tmp) / "agent-transcripts" / "2d779290-764d-462c-bc50-8212c3a093a7"
            session.mkdir(parents=True)
            transcript = session / (session.name + ".jsonl")
            transcript.write_text("\n".join([
                json.dumps({"role": "user", "message": {"content": [{"type": "text", "text": "<system>ignore"}]}}),
                json.dumps({"role": "user", "message": {"content": [{"type": "text", "text": "<timestamp>t</timestamp><user_query>where is the receipt</user_query>"}]}}),
            ]), encoding="utf-8")
            raw = scan.cursor_raw(transcript, "home-kimm-Projects-kvittering", "/home/kimm/Projects/kvittering")
        self.assertEqual(raw["firstUser"], "where is the receipt")
        self.assertEqual(raw["cwd"], "/home/kimm/Projects/kvittering")
        self.assertEqual(raw["id"], session.name)


class Walks(unittest.TestCase):
    def test_cursor_transcripts_are_found_newest_first(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for index, name in enumerate(["older", "newer"]):
                session = root / "home-kimm-Projects-kvittering" / "agent-transcripts" / name
                session.mkdir(parents=True)
                transcript = session / (name + ".jsonl")
                transcript.write_text(json.dumps({"role": "user", "message": {"content": name}}), encoding="utf-8")
                os.utime(transcript, (1000 + index, 1000 + index))
            (root / "no-transcripts").mkdir()
            found = scan.cursor_sessions(root, lambda path: [])
        self.assertEqual([row["id"] for row in found], ["newer", "older"])
        self.assertEqual(found[0]["fallback"], "kvittering")

    def test_grok_sessions_skip_folders_without_a_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "cwd" / "empty").mkdir(parents=True)
            titled = root / "cwd" / "titled"
            titled.mkdir()
            (titled / "summary.json").write_text(json.dumps({"generated_title": "Reel timing"}), encoding="utf-8")
            found = scan.grok_sessions(root)
        self.assertEqual([row["id"] for row in found], ["titled"])

    def test_a_missing_root_is_empty(self):
        self.assertEqual(scan.cursor_sessions("/nonexistent/cursor"), [])
        self.assertEqual(scan.grok_sessions("/nonexistent/grok"), [])
        self.assertEqual(scan.claude_sessions("/nonexistent/claude"), [])


class Codex(unittest.TestCase):
    def test_threads_without_a_rollout_file(self):
        import sqlite3

        with tempfile.TemporaryDirectory() as tmp:
            database = Path(tmp) / "state_5.sqlite"
            connection = sqlite3.connect(database)
            connection.execute(
                "CREATE TABLE threads (id TEXT, cwd TEXT, archived INT, updated_at_ms INT, title TEXT, first_user_message TEXT)"
            )
            connection.execute(
                "INSERT INTO threads VALUES (?, ?, 0, ?, ?, ?)",
                ("11111111-1111-1111-1111-111111111111", "/home/kimm/Projects/jobseekr", 100, "Cover letter", "a long first message"),
            )
            connection.execute(
                "INSERT INTO threads VALUES (?, ?, 1, ?, ?, ?)",
                ("22222222-2222-2222-2222-222222222222", "/tmp", 200, "Archived", ""),
            )
            connection.commit()
            connection.close()
            found = scan.codex_sessions(tmp)
        self.assertEqual([row["id"] for row in found], ["11111111-1111-1111-1111-111111111111"])
        self.assertEqual(found[0]["title"], "Cover letter")
        self.assertEqual(found[0]["firstUser"], "")


class Windows(unittest.TestCase):
    PARENTS = {100: 1, 101: 100, 102: 101, 200: 1, 201: 200, 300: 1, 301: 300, 302: 300}
    MARKS = {
        100: ["foot"], 101: ["bash"], 102: ["claude", "c-plain"],
        200: ["foot"], 201: ["bash"],
        300: ["foot --server"], 301: ["claude --resume a"], 302: ["claude --resume b"],
    }

    def describe(self, clients):
        return scan.describe_windows(clients, self.PARENTS, lambda pid: self.MARKS.get(pid, []))

    def test_a_session_inside_the_shell_belongs_to_its_window(self):
        found = self.describe([{"address": "0x1", "pid": 100}, {"address": "0x2", "pid": 200}])
        self.assertIn("c-plain", found[0]["text"])
        self.assertNotIn("c-plain", found[1]["text"])

    def test_windows_sharing_a_server_pid_claim_nothing_below_it(self):
        found = self.describe([{"address": "0x1", "pid": 300}, {"address": "0x2", "pid": 300}])
        self.assertEqual([row["text"] for row in found], ["foot --server", "foot --server"])

    def test_a_multiplexer_pane_carries_its_own_sessions(self):
        parents = {100: 1, 101: 100, 102: 101, 110: 102, 111: 110, 120: 102, 121: 120}
        marks = {111: ["claude", "c-one"], 121: ["claude", "c-two"]}
        panes = [
            {"pane": "w1:p1", "tab": "w1:t1", "workspace": "w1", "shell": 110},
            {"pane": "w2:p1", "tab": "w2:t1", "workspace": "w2", "shell": 120},
            {"pane": "w9:p1", "tab": "w9:t1", "workspace": "w9", "shell": 999},
        ]
        found = scan.describe_windows([{"address": "0x1", "pid": 100}], parents, lambda pid: marks.get(pid, []), panes)[0]
        self.assertEqual([(p["pane"], p["text"]) for p in found["panes"]], [("w1:p1", "claude\nc-one"), ("w2:p1", "claude\nc-two")])
        self.assertIn("c-two", found["text"])

    def test_focus_tries_the_lua_dispatcher_first(self):
        commands = scan.focus_commands("0x1f")
        self.assertEqual(commands[0][2], 'hl.dsp.focus({ window = "address:0x1f" })')
        self.assertEqual(commands[1][2:], ["focuswindow", "address:0x1f"])

    def test_focus_refuses_anything_but_an_address(self):
        self.assertFalse(scan.focus('0x1" }) os.exit() --')["ok"])

    def test_process_tree_includes_grandchildren(self):
        self.assertEqual(sorted(scan.process_tree(100, self.PARENTS)), [100, 101, 102])

    def test_running_records_map_pids_to_sessions(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / ".claude" / "sessions").mkdir(parents=True)
            (home / ".claude" / "sessions" / "42.json").write_text(json.dumps({"pid": 42, "sessionId": "c1"}), encoding="utf-8")
            (home / ".grok").mkdir()
            (home / ".grok" / "active_sessions.json").write_text(json.dumps([{"pid": 7, "session_id": "g1", "cwd": "/"}]), encoding="utf-8")
            self.assertEqual(scan.claude_running(home), {42: "c1"})
            self.assertEqual(scan.grok_running(home), {7: "g1"})

    def test_cursor_log_names_the_latest_conversation(self):
        with tempfile.TemporaryDirectory() as tmp:
            logs = Path(tmp) / "cursor-agent-logs-1000"
            logs.mkdir()
            log = logs / "session-1.log"
            log.write_text('{"conversationId":"old"}\n{"x":1,"conversationId":"new"}\n', encoding="utf-8")
            self.assertEqual(scan.cursor_log_conversation(log), "new")
            other = Path(tmp) / "other.log"
            other.write_text('{"conversationId":"nope"}', encoding="utf-8")
            self.assertEqual(scan.cursor_log_conversation(other), "")


class CursorAllowance(unittest.TestCase):
    def test_period_usage_matches_the_agent_screen(self):
        parsed = scan.parse_cursor_allowance({
            "billingCycleEnd": "1790801659000",
            "planUsage": {
                "totalPercentUsed": 7.490909090909091,
                "autoPercentUsed": 6.626666666666667,
                "apiPercentUsed": 16.133333333333333,
            },
            "spendLimitUsage": {"limitType": "user"},
        }, {"planInfo": {"planName": "Pro"}})
        self.assertAlmostEqual(parsed["percent"], 0.07490909090909091)
        self.assertEqual(parsed["plan"], "Pro")
        self.assertEqual(parsed["onDemand"], "off")
        self.assertEqual(parsed["resetsAt"], "2026-09-30T20:54:19Z")
        self.assertEqual([row["name"] for row in parsed["products"]], ["Auto", "API"])


class Allowance(unittest.TestCase):
    def test_billing_payload_is_a_fraction_of_the_week(self):
        parsed = scan.parse_grok_allowance({
            "creditUsagePercent": 69.0,
            "currentPeriod": {"end": "2026-09-28T08:30:00Z"},
            "productUsage": [
                {"product": "GrokBuild", "usagePercent": 67.0},
                {"product": "GrokChat", "usagePercent": 2.0},
            ],
        })
        self.assertEqual(parsed["percent"], 0.69)
        self.assertEqual(parsed["resetsAt"], "2026-09-28T08:30:00Z")
        self.assertEqual(parsed["products"], [
            {"name": "GrokBuild", "percent": 0.67},
            {"name": "GrokChat", "percent": 0.02},
        ])

    def test_the_newest_log_line_wins(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "unified.jsonl"
            path.write_text("\n".join([
                json.dumps({"msg": "billing: fetched credits config", "ctx": {"config": {"creditUsagePercent": 7.0}}}),
                "not json creditUsagePercent",
                json.dumps({"msg": "billing: fetched credits config", "ctx": {"config": {
                    "creditUsagePercent": 69.0,
                    "billingPeriodEnd": "2026-09-28T08:30:00Z",
                }}}),
            ]), encoding="utf-8")
            parsed = scan.allowance_from_log(path)
        self.assertEqual(parsed["percent"], 0.69)
        self.assertEqual(parsed["resetsAt"], "2026-09-28T08:30:00Z")


class Usage(unittest.TestCase):
    def test_subscription_record_and_grok_session_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            usage = home / ".local" / "state" / "omarchy" / "agents" / "usage"
            usage.mkdir(parents=True)
            (usage / "claude.json").write_text(json.dumps({
                "id": "claude",
                "name": "Claude",
                "tierLabel": "Max 5x",
                "todayTotalTokens": 1000,
                "limits": [{"label": "Weekly (7-day)", "percent": 0.29, "resetsAt": "2026-10-01T00:00:00Z"}],
                "modelUsage": {"claude-opus-5": {
                    "inputTokens": 10, "outputTokens": 20,
                    "cacheReadInputTokens": 30, "cacheCreationInputTokens": 40,
                }},
            }), encoding="utf-8")
            session = home / ".grok" / "sessions" / "cwd" / "abc"
            session.mkdir(parents=True)
            (session / "usage.json").write_text(json.dumps({
                "session": {"modelUsage": {"grok-4.7-build": {
                    "inputTokens": 5, "outputTokens": 6, "cachedReadTokens": 7, "costUsdTicks": 20000000000,
                }}}
            }), encoding="utf-8")
            found = scan.collect_usage(home)
        self.assertEqual([row["id"] for row in found["subscriptions"]], ["claude"])
        self.assertEqual(found["subscriptions"][0]["models"][0]["cacheRead"], 30)
        self.assertEqual(found["subscriptions"][0]["tier"], "Max 5x")
        self.assertEqual(found["grok"][0]["models"][0]["costTicks"], 20000000000)
        self.assertEqual(found["grok"][0]["models"][0]["cacheRead"], 7)


if __name__ == "__main__":
    unittest.main()
