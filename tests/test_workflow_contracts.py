"""Offline contracts for fixed-target update and validation workflows."""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
ACTIONLINT_CONFIG = ROOT / ".github" / "actionlint.yaml"
sys.path.insert(0, str(ROOT / "scripts"))

import validate_update  # noqa: E402


CALLERS = {
    "update-codex.yml": ("Update Codex", "codex"),
    "update-codex-desktop.yml": ("Update Codex Desktop", "codex-desktop"),
    "update-oh-my-codex.yml": ("Update oh-my-codex", "oh-my-codex"),
    "update-foundations.yml": ("Update Foundations", "foundations"),
}

ALL_PACKAGES = (
    "codex",
    "codex-computer-use-linux",
    "codex-desktop",
    "codex-desktop-computer-use-ui",
    "codex-desktop-remote-mobile-control",
    "codex-desktop-computer-use-ui-remote-mobile-control",
    "oh-my-codex",
)

STEP_IDS = (
    "checkout",
    "validate_program",
    "prepare_branch",
    "install_nix",
    "configure_cache",
    "python_contracts",
    "run_updater",
    "validate_changes",
    "detect_changes",
    "evaluate_flake",
    "build_contract_checks",
    "build_desktop_contracts",
    "build_and_smoke",
    "publish_pr",
    "enable_auto_merge",
    "wait_for_merge",
    "quarantine_pr",
    "enforce_result",
)

REUSABLE_STEPS = (
    ("Checkout repository", "checkout"),
    ("Validate fixed program", "validate_program"),
    ("Prepare isolated update branch", "prepare_branch"),
    ("Install Nix", "install_nix"),
    ("Configure NixSlop binary cache", "configure_cache"),
    ("Run Python contract tests", "python_contracts"),
    ("Run fixed updater", "run_updater"),
    ("Validate exact update boundary", "validate_changes"),
    ("Detect validated changes", "detect_changes"),
    ("Evaluate flake without building", "evaluate_flake"),
    ("Build x86 contract checks", "build_contract_checks"),
    ("Build desktop contract checks", "build_desktop_contracts"),
    ("Build and smoke test fixed targets", "build_and_smoke"),
    ("Commit and publish update branch", "publish_pr"),
    ("Enable pull request auto-merge", "enable_auto_merge"),
    ("Wait for pull request merge", "wait_for_merge"),
    ("Quarantine every non-merged pull request", "quarantine_pr"),
    ("Enforce terminal update result", "enforce_result"),
)


def workflow_text(filename: str) -> str:
    return (WORKFLOWS / filename).read_text()


def top_level_name(text: str) -> str:
    match = re.search(r"^name: (.+)$", text, flags=re.MULTILINE)
    if match is None:
        raise AssertionError("workflow has no top-level name")
    return match.group(1)


class CallerWorkflowTests(unittest.TestCase):
    def test_caller_inventory_is_exact(self) -> None:
        actual = {
            path.name
            for path in WORKFLOWS.glob("update-*.yml")
            if path.name not in {"update-reusable.yml", "update-health.yml"}
        }
        self.assertEqual(actual, set(CALLERS))
        self.assertFalse((WORKFLOWS / "update-packages.yml").exists())

    def test_names_manual_trigger_programs_permissions_and_mutex(self) -> None:
        job_names = {
            "update-codex.yml": "Run Codex update",
            "update-codex-desktop.yml": "Run Codex Desktop update",
            "update-oh-my-codex.yml": "Run oh-my-codex update",
            "update-foundations.yml": "Run foundation inputs update",
        }
        for filename, (name, program) in CALLERS.items():
            with self.subTest(filename=filename):
                text = workflow_text(filename)
                self.assertEqual(top_level_name(text), name)
                self.assertIn("  workflow_dispatch:", text)
                self.assertNotIn("schedule:", text)
                self.assertNotIn("cron:", text)
                self.assertRegex(text, rf"(?m)^      program: {re.escape(program)}$")
                self.assertIn("uses: ./.github/workflows/update-reusable.yml", text)
                self.assertRegex(text, r"(?m)^  update:$")
                self.assertIn(f"    name: {job_names[filename]}", text)
                self.assertIn(
                    "permissions:\n  contents: write\n  pull-requests: write",
                    text,
                )
                self.assertIn("group: nixslop-update-global", text)
                self.assertEqual(text.count("queue: max"), 1)
                self.assertIn("cancel-in-progress: false", text)
                self.assertIn(
                    "CACHIX_AUTH_TOKEN: ${{ secrets.CACHIX_AUTH_TOKEN }}",
                    text,
                )
                self.assertNotIn("secrets: inherit", text)

    def test_queue_schema_exception_is_exact_and_caller_scoped(self) -> None:
        config = ACTIONLINT_CONFIG.read_text()
        self.assertIn(
            ".github/workflows/update-{codex,codex-desktop,oh-my-codex,foundations}.yml:",
            config,
        )
        self.assertEqual(config.count("ignore:"), 1)
        self.assertIn(
            "unexpected key \"queue\" for \"concurrency\" section",
            config,
        )
        self.assertNotIn(".github/workflows/**/*.yml", config)

    def test_callers_are_manual_only(self) -> None:
        for filename in CALLERS:
            with self.subTest(filename=filename):
                text = workflow_text(filename)
                self.assertIn("on:\n  workflow_dispatch:", text)
                self.assertNotIn("schedule:", text)


class ReusableWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = workflow_text("update-reusable.yml")

    def test_reusable_has_only_fixed_program_input(self) -> None:
        inputs = re.search(
            r"(?ms)^  workflow_call:\n    inputs:\n(?P<body>.*?)^    secrets:",
            self.text,
        )
        self.assertIsNotNone(inputs)
        assert inputs is not None
        names = re.findall(r"^      ([a-zA-Z0-9_-]+):$", inputs.group("body"), re.M)
        self.assertEqual(names, ["program"])
        self.assertIn("required: true", inputs.group("body"))
        self.assertIn("type: string", inputs.group("body"))
        self.assertNotIn("workflow_dispatch:", self.text)

    def test_reusable_permissions_and_explicit_optional_cache_secret(self) -> None:
        self.assertIn(
            "permissions:\n  contents: write\n  pull-requests: write",
            self.text,
        )
        self.assertRegex(
            self.text,
            r"(?ms)^    secrets:\n      CACHIX_AUTH_TOKEN:.*?required: false",
        )
        self.assertIn(
            "authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}",
            self.text,
        )
        self.assertNotIn("secrets: inherit", self.text)
        self.assertNotIn("concurrency:", self.text)

    def test_program_enum_and_step_ids_are_stable(self) -> None:
        self.assertEqual(top_level_name(self.text), "Reusable Program Update")
        self.assertIn("  update:\n    name: Update ${{ inputs.program }}", self.text)
        self.assertIn(
            "codex|codex-desktop|oh-my-codex|foundations)",
            self.text,
        )
        actual_ids = re.findall(r"(?m)^        id: ([a-z0-9_]+)$", self.text)
        self.assertEqual(tuple(actual_ids), STEP_IDS)
        actual_steps = tuple(
            re.findall(
                r"(?m)^      - name: (.+)\n        id: ([a-z0-9_]+)$",
                self.text,
            )
        )
        self.assertEqual(actual_steps, REUSABLE_STEPS)

    def test_update_commands_are_literal_fixed_mappings(self) -> None:
        commands = {
            "nix develop -c packages/codex/update.py",
            "nix flake update codex-desktop-linux",
            "nix develop -c packages/oh-my-codex/update.py",
            "nix flake update nixpkgs systems home-manager",
        }
        for command in commands:
            self.assertIn(command, self.text)

        forbidden = (
            "inputs.command",
            "inputs.path",
            "packages/$PROGRAM",
            "packages/${PROGRAM}",
            '".#$PROGRAM"',
            "eval ",
        )
        for fragment in forbidden:
            self.assertNotIn(fragment, self.text)

    def test_change_allowlists_and_lock_inputs_are_exact(self) -> None:
        actual = {
            name: (contract.paths, contract.lock_inputs)
            for name, contract in validate_update.TARGETS.items()
        }
        expected = {
            "codex": (frozenset({"packages/codex/hashes.json"}), frozenset()),
            "codex-desktop": (
                frozenset({"flake.lock"}),
                frozenset({"codex-desktop-linux"}),
            ),
            "oh-my-codex": (
                frozenset(
                    {
                        "packages/oh-my-codex/Cargo.lock",
                        "packages/oh-my-codex/hashes.json",
                    }
                ),
                frozenset(),
            ),
            "foundations": (
                frozenset({"flake.lock"}),
                frozenset({"home-manager", "nixpkgs", "systems"}),
            ),
        }
        self.assertEqual(actual, expected)
        self.assertIn(
            'python3 scripts/validate_update.py "$PROGRAM" --base-ref origin/main',
            self.text,
        )

    def test_validation_and_fixed_build_contracts_are_explicit(self) -> None:
        self.assertIn("python3 -m unittest discover -s tests -v", self.text)
        self.assertIn(
            "nix flake check --all-systems --no-build --print-build-logs",
            self.text,
        )
        for check in (
            "module-contracts",
            "output-contracts",
            "home-manager-contracts",
            "formatting",
            "actionlint",
            "workflow-contracts",
            "codex-desktop-patch-source",
            "codex-desktop-computer-use",
        ):
            self.assertIn(f".#checks.x86_64-linux.{check}", self.text)
        self.assertRegex(
            self.text,
            r"(?ms)id: build_desktop_contracts.*?"
            r"inputs\.program == 'codex-desktop'.*?"
            r"inputs\.program == 'foundations'",
        )
        foundations = re.search(
            r"(?ms)^            foundations\)\n              packages=\((.*?)^              \)\n",
            self.text,
        )
        self.assertIsNotNone(foundations)
        assert foundations is not None
        actual = tuple(re.findall(r"(?m)^                ([a-z0-9-]+)$", foundations.group(1)))
        self.assertEqual(actual, ALL_PACKAGES)
        self.assertIn("packages=(codex oh-my-codex)", self.text)

    def test_main_base_sha_is_persisted_and_rechecked_fail_closed(self) -> None:
        self.assertIn('base_file="$RUNNER_TEMP/nixslop-update-base-sha"', self.text)
        self.assertIn('base_sha="$(git rev-parse origin/main)"', self.text)
        self.assertIn('echo "UPDATE_BASE_SHA=$base_sha"', self.text)
        self.assertGreaterEqual(
            self.text.count("git fetch --no-tags origin main"),
            4,
        )
        self.assertLess(
            self.text.index("verify_base_unchanged\n\n          if [ -n \"$UPDATE_REMOTE_SHA\" ]"),
            self.text.index('origin "HEAD:refs/heads/$UPDATE_BRANCH"'),
        )
        self.assertLess(
            self.text.index("verify_base_unchanged\n          verify_pr_identity"),
            self.text.index('gh pr merge "$pr_number"'),
        )
        self.assertIn('result="BASE_DRIFT"', self.text)

    def test_validated_head_sha_is_bound_through_merge(self) -> None:
        self.assertIn('validated_head="$(git rev-parse HEAD)"', self.text)
        self.assertIn(
            'head_file="$RUNNER_TEMP/nixslop-update-head-sha"',
            self.text,
        )
        self.assertIn('echo "UPDATE_HEAD_SHA=$validated_head"', self.text)
        self.assertIn('published_head="$(git ls-remote', self.text)
        self.assertGreaterEqual(
            self.text.count(".headRefOid == $expected_head"),
            3,
        )
        self.assertIn('--match-head-commit "$expected_head"', self.text)
        self.assertIn('result="HEAD_DRIFT"', self.text)

        wait_step = re.search(
            r"(?ms)^      - name: Wait for pull request merge\n"
            r".*?^      - name: Quarantine every non-merged pull request",
            self.text,
        )
        self.assertIsNotNone(wait_step)
        assert wait_step is not None
        self.assertIn("headRefOid", wait_step.group(0))
        self.assertLess(
            wait_step.group(0).index('result="HEAD_DRIFT"'),
            wait_step.group(0).index('if [ "$state" = "MERGED" ]'),
        )
        self.assertLess(
            wait_step.group(0).index('result="BASE_DRIFT"'),
            wait_step.group(0).index('if [ "$state" = "MERGED" ]'),
        )

        cleanup_step = self.text.split(
            "- name: Quarantine every non-merged pull request",
            maxsplit=1,
        )[1]
        self.assertIn("headRefOid", cleanup_step)
        cleanup_identity = cleanup_step.split(
            "accept_validated_merge()",
            maxsplit=1,
        )[0]
        self.assertNotIn(".headRefOid == $expected_head", cleanup_identity)
        self.assertEqual(cleanup_step.count('accept_validated_merge "$details"'), 7)
        self.assertEqual(cleanup_step.count(': > "$merged_file"'), 1)
        self.assertIn(".baseRefOid == $expected_base and", cleanup_step)
        self.assertIn(".headRefOid == $expected_head", cleanup_step)
        self.assertIn("Merged PR failed validated commit proof", cleanup_step)

    def test_every_pr_resolution_and_mutation_is_identity_bounded(self) -> None:
        for field in (
            "isCrossRepository",
            "baseRefName",
            "baseRefOid",
            "headRefName",
            "headRefOid",
        ):
            self.assertIn(field, self.text)
        self.assertGreaterEqual(self.text.count(".isCrossRepository == false"), 6)
        self.assertGreaterEqual(self.text.count('.baseRefName == "main"'), 6)
        self.assertGreaterEqual(self.text.count(".baseRefOid == $expected_base"), 2)
        self.assertGreaterEqual(self.text.count(".headRefName == $branch"), 6)
        self.assertEqual(self.text.count("gh pr list"), 3)
        for marker in (
            "existing_pr_json",
            "created_pr_json",
            "recovered_pr_json",
        ):
            self.assertIn(marker, self.text)
        self.assertIn('details="$(verify_pr_identity "$pr_number")"', self.text)
        self.assertIn('verify_pr_identity "$pr_number" >/dev/null', self.text)
        self.assertIn("IDENTITY_MISMATCH", self.text)

    def test_pr_boundary_polling_and_fail_closed_cleanup(self) -> None:
        required_fragments = (
            'branch="update/$PROGRAM"',
            "--state all",
            'CLOSED)\n                gh pr reopen',
            "--force-with-lease=",
            "gh pr create",
            "gh pr edit",
            "--auto",
            "--squash",
            "for attempt in $(seq 1 240)",
            "sleep 30",
            'result="MERGED"',
            'result="CLOSED"',
            'result="DIRTY"',
            'result="TIMEOUT"',
            "--disable-auto",
            "--add-label update-quarantined",
            "gh pr close",
            'if [ ! -s "$pr_file" ] && [ -n "${UPDATE_BRANCH:-}" ]',
            "was not proven closed",
            'if: always()',
            'TERMINAL_RESULT" = "MERGED',
        )
        for fragment in required_fragments:
            self.assertIn(fragment, self.text)
        self.assertLess(
            self.text.index("id: wait_for_merge"),
            self.text.index("id: quarantine_pr"),
        )
        self.assertLess(
            self.text.index("id: quarantine_pr"),
            self.text.index("id: enforce_result"),
        )


class UpdateValidatorTests(unittest.TestCase):
    def test_status_parser_accepts_modifications_only(self) -> None:
        with mock.patch(
            "validate_update.run_git",
            return_value=b" M packages/codex/hashes.json\0",
        ):
            self.assertEqual(
                validate_update.changed_paths(),
                {"packages/codex/hashes.json"},
            )

    def test_status_parser_rejects_add_delete_and_rename(self) -> None:
        statuses = (
            b"?? unexpected.txt\0",
            b" D packages/codex/hashes.json\0",
            b"R  renamed.json\0old.json\0",
        )
        for status in statuses:
            with (
                self.subTest(status=status),
                mock.patch("validate_update.run_git", return_value=status),
                self.assertRaises(validate_update.ValidationError),
            ):
                validate_update.changed_paths()

    @staticmethod
    def lock(*, a_revision: str = "a1", b_revision: str = "b1") -> dict:
        def node(revision: str) -> dict:
            return {
                "locked": {"rev": revision, "narHash": f"sha256-{revision}"},
                "original": {"type": "github", "repo": revision[0]},
            }

        return {
            "version": 7,
            "root": "root",
            "nodes": {
                "root": {"inputs": {"allowed": "allowed", "protected": "protected"}},
                "allowed": node(a_revision),
                "protected": node(b_revision),
            },
        }

    def test_lock_validator_allows_only_selected_root_closure(self) -> None:
        before = self.lock()
        after = self.lock(a_revision="a2")
        validate_update.validate_lock_change(
            before,
            after,
            frozenset({"allowed"}),
        )

    def test_lock_validator_rejects_protected_root_change(self) -> None:
        before = self.lock()
        after = self.lock(a_revision="a2", b_revision="b2")
        with self.assertRaisesRegex(
            validate_update.ValidationError,
            "protected root input",
        ):
            validate_update.validate_lock_change(
                before,
                after,
                frozenset({"allowed"}),
            )

    def test_lock_validator_rejects_noise_without_target_change(self) -> None:
        before = self.lock()
        after = self.lock(b_revision="b2")
        with self.assertRaises(validate_update.ValidationError):
            validate_update.validate_lock_change(
                before,
                after,
                frozenset({"allowed"}),
            )

    def test_lock_validator_rejects_unreachable_nodes(self) -> None:
        before = self.lock()
        after = self.lock(a_revision="a2")
        after["nodes"]["hidden"] = {
            "locked": {"rev": "surprise"},
            "original": {"type": "github", "repo": "surprise"},
        }
        with self.assertRaisesRegex(
            validate_update.ValidationError,
            "unreachable",
        ):
            validate_update.validate_lock_change(
                before,
                after,
                frozenset({"allowed"}),
            )


class HealthWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = workflow_text("update-health.yml")

    def test_health_name_permissions_manual_trigger_and_window_are_stable(self) -> None:
        self.assertEqual(top_level_name(self.text), "Update Health")
        self.assertIn("actions: read", self.text)
        self.assertIn("contents: read", self.text)
        self.assertIn("on:\n  workflow_dispatch:", self.text)
        self.assertNotIn("schedule:", self.text)
        self.assertIn("max_age_hours=36", self.text)
        self.assertIn("  update-health:\n    name: Verify manual update health", self.text)
        self.assertIn("- name: Verify named update workflows", self.text)
        self.assertIn("id: verify_update_health", self.text)

    def test_health_checks_every_exact_caller_name(self) -> None:
        mappings = set(
            re.findall(
                r'(?m)^            "([^"]+)\|(update-[^"]+\.yml)"$',
                self.text,
            )
        )
        expected = {
            (name, filename)
            for filename, (name, _program) in CALLERS.items()
        }
        self.assertEqual(mappings, expected)
        self.assertIn('status" != "completed"', self.text)
        self.assertIn('conclusion" != "success"', self.text)
        self.assertIn('created_at="$(jq -r .created_at', self.text)
        self.assertIn("created_epoch", self.text)
        self.assertNotIn("updated_epoch", self.text)
        self.assertNotIn(".updated_at", self.text)
        self.assertIn("runs?event=workflow_dispatch&per_page=1", self.text)


class CheckWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = workflow_text("check.yml")

    def test_matrix_builds_all_public_outputs(self) -> None:
        self.assertEqual(top_level_name(self.text), "Check")
        self.assertIn("  validate:\n    name: Validate repository contracts", self.text)
        self.assertIn(
            "  build:\n    name: Build and smoke test ${{ matrix.package }}",
            self.text,
        )
        matrix = re.search(
            r"(?ms)^      matrix:\n        package:\n(?P<body>.*?)^    steps:",
            self.text,
        )
        self.assertIsNotNone(matrix)
        assert matrix is not None
        actual = tuple(re.findall(r"(?m)^          - ([a-z0-9-]+)$", matrix.group("body")))
        self.assertEqual(actual, ALL_PACKAGES)

    def test_each_package_family_has_a_smoke_assertion(self) -> None:
        fragments = (
            '"$package_path/bin/codex" --version',
            '"$package_path/bin/codex-computer-use-linux"',
            '"$package_path/bin/codex-computer-use-linux" --help',
            '"$package_path/bin/codex-computer-use-cosmic" --help',
            '"$package_path/bin/codex-chrome-extension-host" </dev/null',
            '"$package_path/bin/codex-desktop"',
            '"$package_path/bin/omx" --version',
        )
        for fragment in fragments:
            self.assertIn(fragment, self.text)
        for package in ALL_PACKAGES:
            self.assertIn(package, self.text)

    def test_validation_builds_cheap_contract_checks(self) -> None:
        for check in (
            "module-contracts",
            "output-contracts",
            "home-manager-contracts",
            "formatting",
            "actionlint",
            "workflow-contracts",
            "codex-desktop-patch-source",
            "codex-desktop-computer-use",
        ):
            self.assertIn(f".#checks.x86_64-linux.{check}", self.text)


if __name__ == "__main__":
    unittest.main()
