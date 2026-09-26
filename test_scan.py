#!/usr/bin/env python3
"""File-reading tests for scan.py. Model.js has its own suite."""

import json
import os
import time
import tempfile
import unittest
import unittest.mock
from pathlib import Path

import scan

# Session days are local dates; pin the zone so the checks read the same anywhere.
os.environ["TZ"] = "UTC"
time.tzset()


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


class Delete(unittest.TestCase):
    ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

    def home_with_everything(self, tmp):
        home = Path(tmp)
        project = home / ".claude" / "projects" / "-home-kimm-p"
        project.mkdir(parents=True)
        (project / (self.ID + ".jsonl")).write_text("{}", encoding="utf-8")
        (project / self.ID / "subagents").mkdir(parents=True)
        (project / "other.jsonl").write_text("{}", encoding="utf-8")
        (home / ".claude" / "file-history" / self.ID).mkdir(parents=True)
        (home / ".claude" / "todos").mkdir(parents=True)
        (home / ".claude" / "todos" / (self.ID + "-agent-1.json")).write_text("[]", encoding="utf-8")
        (home / ".claude" / "todos" / "someone-else.json").write_text("[]", encoding="utf-8")
        (home / ".grok" / "sessions" / "%2Fhome" / self.ID).mkdir(parents=True)
        (home / ".cursor" / "projects" / "home-kimm-p" / "agent-transcripts" / self.ID).mkdir(parents=True)
        (home / ".config" / "cursor" / "chats" / "abc123" / self.ID).mkdir(parents=True)
        return home

    def delete(self, tool, home, session_id=None, running=False):
        gone = []
        result = scan.delete_session(tool, self.ID if session_id is None else session_id, home,
                                     running=lambda *_: running, discard=gone.append)
        return result, sorted(str(p.relative_to(home)) for p in gone)

    def test_claude_takes_its_transcript_and_what_belongs_to_it_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = self.home_with_everything(tmp)
            result, gone = self.delete("claude", home)
        self.assertEqual(result, {"ok": True, "removed": 4})
        self.assertEqual(gone, [
            ".claude/file-history/" + self.ID,
            ".claude/projects/-home-kimm-p/" + self.ID,
            ".claude/projects/-home-kimm-p/" + self.ID + ".jsonl",
            ".claude/todos/" + self.ID + "-agent-1.json",
        ])

    def test_grok_and_cursor_take_their_folders(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = self.home_with_everything(tmp)
            self.assertEqual(self.delete("grok", home)[1], [".grok/sessions/%2Fhome/" + self.ID])
            self.assertEqual(self.delete("cursor", home)[1], [
                ".config/cursor/chats/abc123/" + self.ID,
                ".cursor/projects/home-kimm-p/agent-transcripts/" + self.ID,
            ])

    def test_a_running_session_is_left_alone(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = self.home_with_everything(tmp)
            result, gone = self.delete("claude", home, running=True)
        self.assertFalse(result["ok"])
        self.assertEqual(gone, [])

    def test_anything_but_an_id_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = self.home_with_everything(tmp)
            for bad in ["../../etc", "a/b/c/d/e/f", "*", "", "short"]:
                result, gone = self.delete("claude", home, session_id=bad)
                self.assertFalse(result["ok"], bad)
                self.assertEqual(gone, [])

    def test_codex_goes_through_its_own_command(self):
        asked = []
        result = scan.delete_session("codex", self.ID, "/nonexistent", running=lambda *_: False,
                                     codex=lambda sid: asked.append(sid) or {"ok": True})
        self.assertEqual((result, asked), ({"ok": True}, [self.ID]))

    def test_a_session_this_process_does_not_know_is_not_running(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertFalse(scan.session_running("zzzzzzzz-not-a-real-session-0000", Path(tmp)))

    def test_this_very_session_counts_as_running(self):
        # The Claude conversation driving these tests has its id in its own
        # process record, so the real check has to see it as running.
        by_pid = scan.claude_running(Path.home())
        parents = scan.process_parents()
        pid, mine = os.getpid(), []
        while pid and pid > 1 and not mine:
            mine = [by_pid[pid]] if pid in by_pid else []
            pid = parents.get(pid)
        if not mine:
            self.skipTest("not run from inside a Claude session")
        self.assertTrue(scan.session_running(mine[0], Path.home()))


class Forks(unittest.TestCase):
    def test_a_fork_does_not_keep_the_session_it_started_from_running(self):
        old = "/home/u/.claude/projects/p/f94a28db-a70f-4eb4-aa34-a39cc40c4399.jsonl"
        argv = ["claude", "--session-id", "e1f5", "--fork-session", "--resume", old, "--reply-on-resume"]
        self.assertEqual(scan.without_fork_source(argv), ["claude", "--session-id", "e1f5", "--fork-session", "--reply-on-resume"])
        self.assertEqual(scan.without_fork_source(["claude", "--resume", old]), ["claude", "--resume", old])


class Opening(unittest.TestCase):
    ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

    def test_herdr_is_the_default_when_installed_and_a_choice_sticks(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "apps.json"
            everything = scan.apps_state(path, which=lambda name: "/usr/bin/" + name)
            self.assertEqual([everything["available"], everything["default"]], [["herdr", "tmux", "terminal"], "herdr"])
            self.assertEqual(everything["tools"], ["claude", "grok", "codex", "cursor"])
            bare = scan.apps_state(path, which=lambda name: None)
            self.assertEqual([bare["available"], bare["default"], bare["tools"]], [["terminal"], "terminal", []])
            scan.set_default_app("tmux", path)
            scan.remember_apps([self.ID + "=terminal", "../x=herdr", self.ID[:-1] + "f=nano"], path)
            state = scan.apps_state(path, which=lambda name: "/usr/bin/" + name)
            self.assertEqual([state["default"], state["sessions"]], ["tmux", {self.ID: "terminal"}])
            # A default that is no longer installed falls back.
            self.assertEqual(scan.apps_state(path, which=lambda name: None)["default"], "terminal")

    def test_a_new_workspace_is_made_before_opening_and_only_a_real_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "projects" / "fresh"
            seen = []
            opener = {"herdr": lambda command: seen.append(folder.is_dir()) or {"ok": True}}
            result = scan.open_session("herdr", str(folder), "Claude", "-", ["python3"], Path(tmp) / "apps.json",
                                       openers=opener, create=True)
            self.assertEqual([result["ok"], seen], [True, [True]])
            for bad in ("relative/dir", tmp + "/../escape"):
                result = scan.open_session("herdr", bad, "Claude", "-", ["python3"], Path(tmp) / "apps.json",
                                           openers=opener, create=True)
                self.assertFalse(result["ok"])
            self.assertEqual(seen, [True])

    def herdr(self, workspaces):
        calls = []

        def run(command):
            calls.append(command)
            if command[1:3] == ["workspace", "list"]:
                return {"result": {"workspaces": workspaces}}
            if command[1:3] in (["tab", "create"], ["workspace", "create"]):
                return {"result": {"root_pane": {"pane_id": "w9:p4"}}}
            return {"result": {}}

        result = scan.herdr_open("/home/kimm/Projects/omarchy-arcade", "Plugin improvements",
                                 ["grok", "--cwd", "/home/kimm/My Projects", "--resume", "g1"],
                                 run=run, window=lambda: "", spawn=lambda command: calls.append(command), wait=0,
                                 succeeds=lambda command: calls.append(command) or True)
        return result, calls

    def test_herdr_opens_a_tab_in_the_folders_workspace(self):
        result, calls = self.herdr([{"workspace_id": "w1", "label": "casino"}, {"workspace_id": "wD", "label": "omarchy-arcade"}])
        self.assertTrue(result["ok"])
        self.assertEqual(calls[-2][:5], ["herdr", "tab", "create", "--workspace", "wD"])
        self.assertIn("--focus", calls[-2])
        # One quoted line, since herdr types it into the pane's shell.
        self.assertEqual(calls[-1], ["herdr", "pane", "run", "w9:p4",
                                     "grok --cwd '/home/kimm/My Projects' --resume g1"])

    def test_herdr_makes_the_workspace_when_the_folder_has_none(self):
        result, calls = self.herdr([{"workspace_id": "w1", "label": "casino"}])
        create = next(c for c in calls if c[1:3] == ["workspace", "create"])
        self.assertEqual(create[create.index("--label") + 1], "omarchy-arcade")
        self.assertTrue(result["ok"])

    def test_with_no_herdr_window_a_terminal_running_herdr_starts(self):
        _, calls = self.herdr([])
        self.assertEqual(calls[0], ["uwsm-app", "--", "xdg-terminal-exec", "herdr"])

    def test_tmux_opens_a_window_where_a_client_is_attached(self):
        calls = []

        def run(command):
            calls.append(command)
            if command[1] == "list-clients":
                return 0, "4242\twork\n"
            return 0, ""

        result = scan.tmux_open("/tmp", "Fix it", ["claude", "--resume", self.ID], run=run, window=lambda: "")
        self.assertTrue(result["ok"])
        self.assertEqual(calls[-1], ["tmux", "new-window", "-t", "work:", "-c", "/tmp", "-n", "Fix it",
                                     "claude --resume " + self.ID])

    def test_tmux_without_a_client_opens_a_new_session_in_a_terminal(self):
        spawned = []
        result = scan.tmux_open("/tmp", "Fix it", ["codex", "resume", "x1"],
                                run=lambda command: (1, ""), spawn=spawned.append)
        self.assertTrue(result["ok"])
        self.assertEqual(spawned[0][-7:], ["tmux", "new-session", "-c", "/tmp", "-n", "Fix it", "codex resume x1"])

    def test_a_background_claude_session_is_attached_to_not_resumed(self):
        ran = []
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "apps.json"
            openers = {"herdr": lambda command: ran.append(command) or {"ok": True}}
            scan.open_session("herdr", "/tmp", "t", self.ID, ["claude", "--resume", self.ID], path,
                              openers=openers, background={self.ID: 42})
            scan.open_session("herdr", "/tmp", "t", self.ID, ["claude", "--resume", self.ID], path,
                              openers=openers, background={})
        self.assertEqual(ran, [["claude", "attach", "aaaaaaaa"], ["claude", "--resume", self.ID]])

    def test_opening_remembers_the_app_for_the_session(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "apps.json"
            result = scan.open_session("herdr", "/tmp", "t", self.ID, ["python3", "-c", "0"], path,
                                       openers={"herdr": lambda command: {"ok": True}})
            self.assertTrue(result["ok"])
            self.assertEqual(scan.read_apps(path)["sessions"], {self.ID: "herdr"})
            scan.open_session("herdr", "/tmp", "t", "-", ["python3"], path, openers={"herdr": lambda command: {"ok": True}})
            self.assertEqual(len(scan.read_apps(path)["sessions"]), 1)

    def test_a_tmux_pane_belongs_to_the_window_its_client_runs_in(self):
        parents = {100: 1, 101: 100, 500: 1, 501: 500, 502: 501}
        marks = {502: ["claude", "c-tmux"]}
        panes = [{"kind": "tmux", "pane": "%3", "tab": "work:2", "workspace": "work", "shell": 501, "clients": [101]}]
        found = scan.describe_windows([{"address": "0x1", "pid": 100}], parents, lambda pid: marks.get(pid, []), panes)[0]
        self.assertEqual([(p["kind"], p["pane"], p["text"]) for p in found["panes"]], [("tmux", "%3", "claude\nc-tmux")])
        self.assertIn("c-tmux", found["text"])

    def test_tmux_panes_read_from_tmux(self):
        answers = {
            "list-panes": (0, "501\t%3\twork:2\twork\n601\t%7\tother:0\tother\n"),
            "list-clients": (0, "101\twork\n"),
        }
        with unittest.mock.patch.object(scan.shutil, "which", return_value="/usr/bin/tmux"):
            panes = scan.tmux_panes(run=lambda command: answers[command[1]])
        self.assertEqual([(p["pane"], p["clients"]) for p in panes], [("%3", [101]), ("%7", [])])


class Titles(unittest.TestCase):
    ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

    def test_cursor_takes_its_own_title_and_folder_but_not_its_placeholder(self):
        with tempfile.TemporaryDirectory() as tmp:
            transcript = Path(tmp) / "t.jsonl"
            transcript.write_text("\n".join([
                json.dumps({"role": "user", "message": {"content": "<user_query>where is it</user_query>"}}),
                json.dumps({"role": "assistant", "message": {"content": [{"type": "text", "text": "Looking now."}]}}),
            ]), encoding="utf-8")
            named = scan.cursor_raw(transcript, "home-kimm-x", "/guess", {"title": "Project Guidance", "cwd": "/home/kimm/Work"})
            placeholder = scan.cursor_raw(transcript, "home-kimm-x", "/guess", {"title": "New Agent"})
        self.assertEqual([named["title"], named["cwd"], named["firstReply"]], ["Project Guidance", "/home/kimm/Work", "Looking now."])
        self.assertEqual([placeholder["title"], placeholder["cwd"]], ["", "/guess"])

    def test_renaming_claude_writes_what_its_own_rename_writes(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            project = home / ".claude" / "projects" / "-p"
            project.mkdir(parents=True)
            transcript = project / (self.ID + ".jsonl")
            transcript.write_text(json.dumps({"type": "user", "message": {"content": "pull"}}) + "\n", encoding="utf-8")
            self.assertTrue(scan.rename_session("claude", self.ID, "Pulled main", home)["ok"])
            self.assertEqual(scan.claude_raw(transcript)["customTitle"], "Pulled main")
            scan.rename_session("claude", self.ID, "", home)
            self.assertEqual(scan.claude_raw(transcript)["customTitle"], "")

    def test_other_tools_keep_their_names_with_the_plugin(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "titles.json"
            scan.rename_session("grok", self.ID, "  Reel   timing ", tmp, path)
            self.assertEqual(scan.read_titles(path)["names"], {self.ID: "Reel timing"})
            scan.rename_session("grok", self.ID, "", tmp, path)
            self.assertEqual(scan.read_titles(path)["names"], {})
            self.assertFalse(scan.rename_session("grok", "../x", "t", tmp, path)["ok"])

    def test_autotitle_asks_once_for_the_untitled_and_keeps_the_answers(self):
        sessions = [
            {"tool": "claude", "id": "s-untitled-1", "firstUser": "pull", "firstReply": "Nothing new."},
            {"tool": "claude", "id": "s-titled-01", "firstUser": "x", "aiTitle": "Named"},
            {"tool": "cursor", "id": "s-untitled-2", "firstUser": "where\tis it"},
        ]
        asked = []

        def ask(text):
            asked.append(text)
            return 's-untitled-1\tpull\t"Repository up to date."\ns-untitled-2\tFind the receipt\nstranger\tIgnored\n'

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "titles.json"
            result = scan.autotitle(tmp, path, ask, sessions)
            titles = scan.read_titles(path)["auto"]
        self.assertEqual(result, {"ok": True, "titled": 2})
        self.assertEqual(titles, {"s-untitled-1": "Repository up to date", "s-untitled-2": "Find the receipt"})
        self.assertEqual(asked[0].splitlines(), ["s-untitled-1\tpull => Nothing new.", "s-untitled-2\twhere is it"])

    def test_nothing_untitled_asks_nothing(self):
        result = scan.autotitle("/nonexistent", "/nonexistent/t.json", lambda text: self.fail("asked"),
                                [{"tool": "grok", "id": "g", "generatedTitle": "Named"}])
        self.assertEqual(result, {"ok": True, "titled": 0})


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


class UsageCache(unittest.TestCase):
    def test_a_fresh_cache_answers_and_a_stale_one_is_replaced(self):
        calls = []

        def collect():
            calls.append(1)
            return {"n": len(calls)}

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "usage.json"
            self.assertEqual(scan.cached_usage(300, path, collect), {"n": 1})
            self.assertEqual(scan.cached_usage(300, path, collect), {"n": 1})
            os.utime(path, (0, 0))
            self.assertEqual(scan.cached_usage(300, path, collect), {"n": 2})
            self.assertEqual(scan.cached_usage(None, path, collect), {"n": 3})
            self.assertEqual(json.loads(path.read_text()), {"n": 3})


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
                "todayPrompts": 12,
                "todaySessions": 2,
                "recentDays": [{"date": "2026-09-24", "messageCount": 400}, {"date": "2026-09-25", "messageCount": 1000}],
                "ready": False,
                "usageStatusText": "Limits unavailable",
                "authHelpText": "Run `claude auth login`.",
                "limits": [{"label": "Weekly (7-day)", "percent": 0.29, "resetsAt": "2026-10-01T00:00:00Z"}],
                "modelUsage": {"claude-opus-5": {
                    "inputTokens": 10, "outputTokens": 20,
                    "cacheReadInputTokens": 30, "cacheCreationInputTokens": 40,
                }},
            }), encoding="utf-8")
            session = home / ".grok" / "sessions" / "cwd" / "abc"
            session.mkdir(parents=True)
            (session / "summary.json").write_text(json.dumps({"last_active_at": "2026-09-25T11:50:00Z"}), encoding="utf-8")
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
        self.assertEqual(found["grok"][0]["day"], "2026-09-25")
        claude = found["subscriptions"][0]
        self.assertEqual(claude["days"], [{"date": "2026-09-24", "tokens": 400}, {"date": "2026-09-25", "tokens": 1000}])
        self.assertEqual([claude["todayPrompts"], claude["todaySessions"]], [12, 2])
        self.assertEqual([claude["status"], claude["help"]], ["Limits unavailable", "Run `claude auth login`."])


if __name__ == "__main__":
    unittest.main()
