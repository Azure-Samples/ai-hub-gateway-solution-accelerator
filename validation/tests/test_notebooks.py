import ast
import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
VALIDATION = ROOT / "validation"
SCENARIOS = sorted(p for p in VALIDATION.glob("*.ipynb") if "environment-setup" not in p.name)
BASELINE_SCENARIOS = [p for p in SCENARIOS if p.name != "citadel-foundry-hr-web-search-tests.ipynb"]


class NotebookStructureTests(unittest.TestCase):
    def test_original_thirteen_plus_hr_web_search_are_present(self):
        self.assertEqual(len(BASELINE_SCENARIOS), 13)
        self.assertEqual(len(SCENARIOS), 14)

    def test_simplification_meets_recorded_baseline_target(self):
        code_lines = sum(
            len("".join(cell["source"]).splitlines())
            for path in BASELINE_SCENARIOS
            for cell in json.loads(path.read_text(encoding="utf-8"))["cells"]
            if cell["cell_type"] == "code"
        )
        self.assertLessEqual(code_lines, 8019, f"{code_lines} code lines exceeds the 35% reduction target")

    def test_cells_compile_without_executing_cloud_operations(self):
        for path in VALIDATION.glob("*.ipynb"):
            notebook = json.loads(path.read_text(encoding="utf-8"))
            for index, cell in enumerate(notebook["cells"]):
                if cell["cell_type"] != "code":
                    continue
                with self.subTest(notebook=path.name, cell=index):
                    source = "".join(cell["source"])
                    compile(source, f"{path.name}:{index}", "exec",
                            flags=ast.PyCF_ALLOW_TOP_LEVEL_AWAIT)

    def test_scenarios_use_shared_context_and_strict_summary(self):
        for path in SCENARIOS:
            notebook = json.loads(path.read_text(encoding="utf-8"))
            source = "\n".join("".join(c["source"]) for c in notebook["cells"]
                               if c["cell_type"] == "code")
            with self.subTest(notebook=path.name):
                self.assertIn("ValidationContext", source)
                self.assertIn("ValidationRun", source)
                self.assertIn(".finish(", source)
                self.assertNotIn('utils.run("az account show"', source)
                self.assertNotIn("sys.path.insert(1, '../shared')", source)

    def test_cleanup_never_defaults_to_enabled(self):
        for path in SCENARIOS:
            notebook = json.loads(path.read_text(encoding="utf-8"))
            for cell in notebook["cells"]:
                if cell["cell_type"] != "code":
                    continue
                tree = ast.parse("".join(cell["source"]))
                for node in ast.walk(tree):
                    if not isinstance(node, ast.Assign):
                        continue
                    for target in node.targets:
                        if isinstance(target, ast.Name) and target.id in (
                            "cleanup_enabled", "do_cleanup", "cleanup_delete_contract",
                            "delete_access_contract", "delete_published_assets",
                        ):
                            with self.subTest(notebook=path.name, variable=target.id):
                                self.assertIsInstance(node.value, ast.Constant)
                                self.assertIs(node.value.value, False)

    def test_model_configuration_has_no_copied_release_defaults(self):
        release_name = re.compile(
            r"\b(?:gpt-\d|gpt-image-\d|text-embedding-\d|Mistral-Large-\d|"
            r"FLUX\.\d|MAI-Image-\d|claude-(?:sonnet|haiku)-\d|gemini-\d)", re.I
        )
        for path in SCENARIOS:
            notebook = json.loads(path.read_text(encoding="utf-8"))
            for index, cell in enumerate(notebook["cells"]):
                if cell["cell_type"] != "code":
                    continue
                tree = ast.parse("".join(cell["source"]))
                for node in ast.walk(tree):
                    if isinstance(node, ast.Assign):
                        for value in ast.walk(node.value):
                            if isinstance(value, ast.Constant) and isinstance(value.value, str):
                                with self.subTest(notebook=path.name, cell=index):
                                    self.assertIsNone(release_name.search(value.value),
                                                      "Model inputs must resolve from deployment configuration")


if __name__ == "__main__":
    unittest.main()
