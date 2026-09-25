#!/usr/bin/env python3
"""File-reading tests for scan.py. Model.js has its own suite."""

import json
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
