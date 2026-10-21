"""Execute the HR chat notebook with actual SDK model serialization and mocked cloud IO."""
import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "shared"))
import validationtools
from test_agent_handoff import manifest_document, write_manifest
from test_external_defaults import snapshot

NOTEBOOK = ROOT / "validation" / "citadel-foundry-hr-web-search-tests.ipynb"


def notebook_cells():
    return ["".join(cell["source"]) for cell in json.loads(NOTEBOOK.read_text(encoding="utf-8"))["cells"]
            if cell["cell_type"] == "code"]


class HRWebSearchNotebookTests(unittest.TestCase):
    def setUp(self):
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.root = Path(self.stack.enter_context(tempfile.TemporaryDirectory()))
        self.values = snapshot()
        self.values.pop("VALIDATION_AGENT_CONTRACTS", None)
        self.account = {"id": "fixture-sub", "tenantId": "fixture-tenant"}

    def run_chat_notebook(self, contract_document=None, web_calls=True, create_error=None):
        path = write_manifest(self.root, "hr-predecessor", contract_document or manifest_document(), 1_000_000_000)
        namespace = {}
        code = notebook_cells()
        execute = lambda source: exec(compile(source, "hr-web-search", "exec"), namespace)
        execute(code[0])
        namespace["root"] = self.root
        apim = Mock()
        apim.apim_resource_name = "fixture-apim"
        apim.discover_api_exact.return_value = {"url": "https://gateway.example/models"}
        apim.client.product_api.list_by_product.return_value = [SimpleNamespace(name="universal-llm-api")]
        apim.client.product_policy.get.return_value = SimpleNamespace(value=(
            '<policies><inbound><set-variable name="allowedModels" value="gpt-active"/>'
            '<set-variable name="jwtRequired" value="true"/>'
            '<set-variable name="jwtAudience" value="https://cognitiveservices.azure.com"/>'
            '<llm-token-limit tokens-per-minute="5000" token-quota="500000" token-quota-period="Monthly"/>'
            '</inbound></policies>'
        ))
        namespace["APIMClientTool"] = Mock(return_value=apim)
        with patch.object(validationtools, "_run_json", side_effect=[self.values, self.account]):
            execute(code[1])
        self.assertEqual(namespace["manifest_path"], path)
        self.assertEqual(namespace["hr_contract"]["product_id"], "LLM-HR-ChatAgent-DEV")
        apim.get_subscription_key.assert_not_called()
        project = Mock()
        project.connections.get.return_value = SimpleNamespace(target="https://gateway.example/models")
        project.agents.create_version.return_value = SimpleNamespace(name="owned-agent", version="1")
        if create_error:
            project.agents.create_version.side_effect = create_error
        project.__enter__ = Mock(return_value=project)
        project.__exit__ = Mock(return_value=None)
        factory = Mock(return_value=project)
        namespace["AIProjectClient"] = factory
        namespace["DefaultAzureCredential"] = lambda: "credential"
        execute(code[2])
        definition = project.agents.create_version.call_args.kwargs["definition"].as_dict()
        self.assertEqual(definition["model"], "actual-hr-connection/gpt-active")
        self.assertEqual(definition["tools"][0]["type"], "web_search")
        self.assertIs(definition["tools"][0]["external_web_access"], True)
        self.assertEqual(definition["tool_choice"], "auto")
        self.assertEqual(namespace["owned_agent"], {
            "project_endpoint": namespace["hr_contract"]["project_endpoint"],
            "name": "owned-agent", "version": "1",
        })
        client = Mock()
        client.max_retries = 0
        client.conversations.create.return_value.id = "conversation-fixture"
        client.__enter__ = Mock(return_value=client)
        client.__exit__ = Mock(return_value=None)
        project.get_openai_client.return_value = client

        def response(**kwargs):
            text = "Maya: your 90-day plan uses four learning hours each week."
            return SimpleNamespace(
                id=f"response-{client.responses.create.call_count}", status="completed", output_text=text,
                error=None, usage=SimpleNamespace(model_dump=lambda: {"input_tokens": 100, "output_tokens": 50}),
                model_dump=lambda: {
                    "id": f"response-{client.responses.create.call_count}", "status": "completed",
                    "output": ([{"type": "web_search_call", "id": "search-call", "status": "completed"}]
                               if web_calls else []) + [{
                        "type": "message", "role": "assistant", "status": "completed",
                        "content": [{"type": "output_text", "text": text, "annotations": [{
                            "type": "url_citation", "title": "Career guidance",
                            "url": "https://example.com/career",
                        }] if web_calls else []}],
                    }], "usage": {"input_tokens": 100, "output_tokens": 50},
                },
            )
        client.responses.create.side_effect = response
        execute(code[3])
        self.assertEqual(client.conversations.items.create.call_count, 10)
        self.assertEqual(client.responses.create.call_count, 10)
        self.assertEqual(len(namespace["transcript"]), 10)
        project.get_openai_client.assert_called_with(max_retries=0, timeout=180)
        for call in client.responses.create.call_args_list:
            self.assertEqual(call.kwargs["extra_body"]["agent_reference"]["name"], "owned-agent")
            self.assertEqual(call.kwargs["extra_body"]["agent_reference"]["version"], "1")
            self.assertEqual(call.kwargs["conversation"], "conversation-fixture")
        return namespace, project, client, code

    def test_complete_ten_turn_web_grounded_experience_and_opt_in_cleanup(self):
        namespace, project, client, code = self.run_chat_notebook()
        exec(code[4], namespace)
        exec(code[5], namespace)
        project.agents.delete_version.assert_not_called()
        namespace["cleanup_enabled"] = True
        exec(code[5], namespace)
        project.agents.delete_version.assert_called_once_with(agent_name="owned-agent", agent_version="1")
        client.conversations.delete.assert_called_once_with("conversation-fixture")

    def test_enabling_search_without_actual_tool_or_citation_evidence_cannot_pass(self):
        namespace, _, _, code = self.run_chat_notebook(web_calls=False)
        with self.assertRaises(validationtools.ValidationError):
            exec(code[4], namespace)
        self.assertTrue(any(result.case == "web-search-observed" and result.status == "FAIL"
                            for result in namespace["run"].results))

    def test_agent_creation_failure_propagates_without_direct_model_fallback(self):
        with self.assertRaisesRegex(RuntimeError, "Tool unavailable"):
            self.run_chat_notebook(create_error=RuntimeError("Tool unavailable"))

    def test_tenth_prompt_requests_the_context_checked_by_the_final_validation(self):
        namespace = {}
        exec(notebook_cells()[0], namespace)
        self.assertEqual(len(namespace["prompts"]), 10)
        final_prompt = namespace["prompts"][-1].casefold()
        for topic in ("recall", "name", "target role", "time horizon", "weekly learning", "manager"):
            self.assertIn(topic, final_prompt)
        self.assertEqual(namespace["max_wait_seconds"], 300)
        self.assertEqual(namespace["fallback_wait_seconds"], 90)

    def test_final_recall_check_still_rejects_a_reply_missing_the_budget(self):
        namespace, _, _, code = self.run_chat_notebook()
        namespace["transcript"][-1]["assistant"] = "Maya: here is your 90-day plan."
        with self.assertRaises(validationtools.ValidationError):
            exec(code[4], namespace)
        result = next(result for result in namespace["run"].results if result.case == "conversation-context")
        self.assertEqual(result.status, "FAIL")

    def test_new_notebook_has_guided_output_scopes_and_no_saved_execution(self):
        notebook = json.loads(NOTEBOOK.read_text(encoding="utf-8"))
        for index, cell in enumerate(notebook["cells"]):
            if cell["cell_type"] != "code":
                continue
            guide = "".join(notebook["cells"][index - 1]["source"])
            self.assertIn("**Input:**", guide)
            self.assertIn("**Output:**", guide)
            self.assertIn("utils.notebook_step(", "".join(cell["source"]))
            self.assertEqual(cell["outputs"], [])
            self.assertIsNone(cell["execution_count"])
            compile("".join(cell["source"]), str(NOTEBOOK), "exec")


if __name__ == "__main__":
    unittest.main()
