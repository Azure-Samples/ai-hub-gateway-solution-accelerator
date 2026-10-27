import io
import sys
import subprocess
import unittest
import warnings
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "shared"))
import utils
from validationtools import ModelCatalog, ValidationContext, ValidationError, ValidationRun, redact, _run_json


class OutputTests(unittest.TestCase):
    def setUp(self):
        token = utils._VERBOSE_OUTPUT.set(False)
        self.addCleanup(utils._VERBOSE_OUTPUT.reset, token)
        display = patch.object(utils, "_notebook_display", return_value=False)
        display.start()
        self.addCleanup(display.stop)

    def test_empty_task_has_info_then_green_success_result(self):
        output = io.StringIO()
        with redirect_stdout(output), utils.notebook_step("Define fixtures"):
            pass
        text = output.getvalue()
        self.assertLess(text.index("INFO | INFO"), text.index("RESULT | SUCCESS"))
        self.assertIn(utils.BOLD_GREEN, text)
        self.assertIn("elapsed seconds", text)
        self.assertEqual(len(text.splitlines()), 2)

    def test_error_is_red_and_propagates_without_success(self):
        output = io.StringIO()
        with redirect_stdout(output), self.assertRaisesRegex(ValueError, "missing configuration"):
            with utils.notebook_step("Initialize"):
                raise ValueError("missing configuration")
        text = output.getvalue()
        self.assertIn("RESULT | ERROR", text)
        self.assertIn(utils.BOLD_RED, text)
        self.assertNotIn("SUCCESS", text)
        self.assertEqual(utils._OUTPUT_STEPS.get(), ())

    def test_warning_is_amber_and_not_green_completion(self):
        output = io.StringIO()
        with redirect_stdout(output), utils.notebook_step("Inspect model"):
            warnings.warn("Declared retirement requires review")
        self.assertIn("RESULT | WARNING", output.getvalue())
        self.assertIn(utils.BOLD_YELLOW, output.getvalue())
        self.assertNotIn("RESULT | SUCCESS", output.getvalue())

    def test_legacy_error_and_warning_formatters_affect_task_verdict(self):
        for callback, status in ((utils.print_error, "ERROR"), (utils.print_warning, "WARNING")):
            with self.subTest(status=status):
                output = io.StringIO()
                with redirect_stdout(output), utils.notebook_step("Check"):
                    callback("Details require attention")
                self.assertIn("RESULT | " + status, output.getvalue())
                self.assertNotIn("Task executed successfully", output.getvalue())

    def test_new_collector_and_failed_checks_cannot_produce_green_completion(self):
        namespace = {}
        output = io.StringIO()
        with redirect_stdout(output), utils.notebook_step("Test", namespace=namespace):
            namespace["run"] = ValidationRun("feature")
            namespace["run"].check("body", False, expected="content", actual="empty")
        text = output.getvalue()
        self.assertIn("RESULT | FAIL", text)
        self.assertIn("RESULT | ERROR | Test", text)
        self.assertIn("fail: 1", text)
        self.assertNotIn("Task executed successfully", text)

    def test_previous_failures_do_not_hide_current_step_success(self):
        run = ValidationRun("feature")
        with redirect_stdout(io.StringIO()):
            run.check("previous", False)
        output = io.StringIO()
        with redirect_stdout(output), utils.notebook_step("Next independent check", namespace={"run": run}):
            run.check("current", True)
        self.assertIn("RESULT | SUCCESS", output.getvalue())
        self.assertEqual(len(run.results), 2)

    def test_skips_are_visible_warnings(self):
        run = ValidationRun("feature")
        output = io.StringIO()
        with redirect_stdout(output), utils.notebook_step("Optional check", namespace={"run": run}):
            run.skip("optional", "disabled")
        self.assertIn("RESULT | SKIP", output.getvalue())
        self.assertIn("RESULT | WARNING", output.getvalue())

    def test_expected_http_denial_is_pass_not_a_failed_step(self):
        run = ValidationRun("feature")
        response = Mock(status_code=403, headers={}, text="")
        response.json.return_value = {"error": {"code": "unauthorized_model_access"}}
        output = io.StringIO()
        with redirect_stdout(output), utils.notebook_step("RBAC", namespace={"run": run}):
            utils.http_call(lambda url: response, "https://gateway/models/chat/completions")
            run.check("denied-model", response.status_code == 403)
        self.assertEqual(run.results[0].status, "PASS")
        self.assertIn("checks: 1/1 passed", output.getvalue())
        self.assertIn("RESULT | SUCCESS | RBAC", output.getvalue())

    def test_unvalidated_http_error_cannot_make_the_step_green(self):
        response = Mock(status_code=500, headers={}, text="")
        response.json.return_value = {"error": {"message": "failed"}}
        output = io.StringIO()
        with redirect_stdout(output), utils.notebook_step("Request"):
            utils.http_call(lambda url: response, "https://gateway/models/chat/completions")
        self.assertNotIn("Task executed successfully", output.getvalue())
        self.assertIn("RESULT | ERROR | Request", output.getvalue())

    def test_optional_block_is_a_warning_not_an_execution_error(self):
        run = ValidationRun("feature")
        output = io.StringIO()
        with redirect_stdout(output), utils.notebook_step("Optional check", namespace={"run": run}):
            run.blocked("optional", "not available", required=False)
        self.assertIn("RESULT | WARNING", output.getvalue())
        self.assertNotIn("RESULT | ERROR", output.getvalue())

    def test_nested_steps_do_not_report_parent_success_after_child_warning(self):
        output = io.StringIO()
        with redirect_stdout(output), utils.notebook_step("parent"):
            with utils.notebook_step("child"):
                utils.print_warning("review")
        self.assertNotIn("RESULT | SUCCESS", output.getvalue())
        self.assertEqual(utils._OUTPUT_STEPS.get(), ())

    def test_structured_secret_values_are_redacted_but_usage_remains_visible(self):
        output = io.StringIO()
        with redirect_stdout(output):
            utils.format_result("Request result", headers={"api-key": "private-key-value"},
                                usage={"total_tokens": 42}, tokens_per_minute=5000)
        text = output.getvalue()
        self.assertNotIn("private-key-value", text)
        self.assertIn("42", text)
        self.assertIn("5000", text)
        self.assertEqual(redact({"token": "secret"})["token"], "[REDACTED]")

    def test_secret_reference_metadata_is_visible_without_exposing_values(self):
        safe = redact({
            "apiKeySecretName": "contract-key-secret",
            "token_source": "environment",
            "secretUri": "https://vault.vault.azure.net/secrets/contract-key",
            "api-key": "actual-secret",
        })
        self.assertEqual(safe["apiKeySecretName"], "contract-key-secret")
        self.assertEqual(safe["token_source"], "environment")
        self.assertEqual(safe["api-key"], "[REDACTED]")

    def test_command_secrets_are_masked_and_input_vector_is_not_changed(self):
        arguments = ["az", "rest", "--client-secret", "credential-value", "--name", "visible-name"]
        original = arguments.copy()
        output = io.StringIO()
        with redirect_stdout(output):
            utils.format_command(arguments)
            utils.format_command("az rest --password 'private value'")
        self.assertNotIn("credential-value", output.getvalue())
        self.assertNotIn("private value", output.getvalue())
        self.assertIn("visible-name", output.getvalue())
        self.assertEqual(arguments, original)

    def test_embedded_url_credentials_are_redacted_in_commands(self):
        output = io.StringIO()
        with redirect_stdout(output):
            utils.format_command("az rest --url https://user:private-password@gateway/path")
        self.assertNotIn("private-password", output.getvalue())
        self.assertIn("gateway/path", output.getvalue())

    def test_rich_html_is_escaped_and_uses_status_color(self):
        with patch.object(utils, "_notebook_display", return_value=True), \
                patch("IPython.display.display") as display:
            utils.format_output("<script>unsafe</script>", {"value": "<img src=x>"}, status="ERROR")
        markup = display.call_args.args[0].data
        self.assertNotIn("<script>", markup)
        self.assertIn("&lt;script&gt;", markup)
        self.assertIn("&lt;img", markup)
        self.assertIn("#b91c1c", markup)

    def test_rich_table_colors_rows_and_redacts_secrets(self):
        with patch.object(utils, "_notebook_display", return_value=True), \
                patch("IPython.display.display") as display:
            utils.format_table("Cases", [
                {"case": "one", "status": "PASS", "api-key": "hidden"},
                {"case": "two", "status": "FAIL"},
            ])
        markup = display.call_args.args[0].data
        self.assertIn("#15803d", markup)
        self.assertIn("#b91c1c", markup)
        self.assertNotIn("hidden", markup)
        self.assertIn("<table", markup)

    def test_chat_messages_escape_content_redact_secrets_and_only_link_public_web_urls(self):
        with patch.object(utils, "_notebook_display", return_value=True), \
                patch("IPython.display.display") as display:
            utils.format_chat_message("assistant", "Advice <script>unsafe</script>", turn=2, citations=[
                {"title": "<b>Official source</b>", "url": "https://example.com/careers"},
                {"title": "unsafe", "url": "javascript:alert(1)"},
                {"title": "credential URL", "url": "https://user:password@example.com/private"},
            ], details={"api-key": "do-not-display", "total_tokens": 99})
        markup = display.call_args.args[0].data
        self.assertIn("Turn 2", markup)
        self.assertIn("&lt;script&gt;", markup)
        self.assertNotIn("<script>", markup)
        self.assertIn('href="https://example.com/careers"', markup)
        self.assertNotIn("javascript:", markup)
        self.assertNotIn("do-not-display", markup)
        self.assertNotIn("/private", markup)
        self.assertIn("99", markup)

    def test_chat_role_and_status_are_validated(self):
        with self.assertRaises(ValueError):
            utils.format_chat_message("invalid-role", "message")
        with self.assertRaises(ValueError):
            utils.format_chat_message("user", "message", status="unknown")

    def test_large_binary_response_preview_is_bounded_without_mutation(self):
        body = {"b64_json": "x" * 12000}
        output = io.StringIO()
        with redirect_stdout(output):
            utils.format_output("Image", body)
        self.assertLess(len(output.getvalue()), 5000)
        self.assertIn("12000", output.getvalue())
        self.assertEqual(len(body["b64_json"]), 12000)

    def test_terminal_unicode_does_not_fail_on_windows_legacy_encoding(self):
        buffer = io.BytesIO()
        stream = io.TextIOWrapper(buffer, encoding="ascii")
        with redirect_stdout(stream):
            utils.format_result("Non-ASCII response", body="\u4f60\u597d")
        stream.flush()
        self.assertIn(b"RESULT | SUCCESS", buffer.getvalue())
        self.assertIn(b"\\u4f60", buffer.getvalue())
        stream.detach()

    def test_http_call_logs_before_callback_and_preserves_native_response(self):
        output = io.StringIO()
        response = Mock(status_code=200, headers={"api-key": "private"}, text="text")
        response.json.return_value = {"choices": [{"message": {"content": "Hello"}}]}

        def post(url, **kwargs):
            self.assertIn("INFO | INFO", output.getvalue())
            self.assertIn("https://gateway/models/chat/completions", output.getvalue())
            self.assertIn("deployed-model", output.getvalue())
            self.assertNotIn("private", output.getvalue())
            return response

        with redirect_stdout(output):
            actual = utils.http_call(post, "https://gateway/models/chat/completions",
                                     json={"model": "deployed-model"}, timeout=30)
        self.assertIs(actual, response)
        self.assertIn("HTTP status", output.getvalue())
        self.assertIn("Hello", output.getvalue())
        self.assertNotIn("private", output.getvalue())

    def test_http_transport_exception_propagates(self):
        output = io.StringIO()
        with redirect_stdout(output), self.assertRaisesRegex(RuntimeError, "timeout"):
            utils.http_call(Mock(side_effect=RuntimeError("timeout")), "https://gateway")
        self.assertIn("RESULT | ERROR", output.getvalue())

    def test_streaming_call_does_not_read_or_parse_the_body(self):
        response = Mock(status_code=200, headers={"Content-Type": "text/event-stream"})
        response.json.side_effect = AssertionError("Streaming body must not be consumed by the formatter")
        with redirect_stdout(io.StringIO()):
            actual = utils.http_call(lambda url, **kwargs: response, "https://gateway/responses", stream=True)
        self.assertIs(actual, response)
        response.json.assert_not_called()

    def test_invalid_output_options_fail_explicitly(self):
        with self.assertRaises(ValueError):
            utils.format_output("bad", status="unknown")

    def test_routine_successful_subcommands_are_hidden_and_step_is_two_lines(self):
        output = io.StringIO()
        completed = subprocess.CompletedProcess([], 0, "{}", "")
        with redirect_stdout(output), patch("validationtools.subprocess.run", return_value=completed), \
                patch("validationtools.shutil.which", return_value=None), utils.notebook_step("Initialize"):
            _run_json(["azd", "env", "get-values", "--output", "json"])
            _run_json(["az", "account", "show", "--output", "json"])
        self.assertEqual(len(output.getvalue().splitlines()), 2)
        self.assertNotIn("azd env", output.getvalue())
        self.assertNotIn("az account", output.getvalue())

    def test_verbose_mode_explicitly_restores_command_diagnostics(self):
        utils.set_output_verbose(True)
        output = io.StringIO()
        with redirect_stdout(output), patch("validationtools.subprocess.run", return_value=
                subprocess.CompletedProcess([], 0, "{}", "")), \
                patch("validationtools.shutil.which", return_value=None):
            _run_json(["azd", "env", "get-values"])
        self.assertIn("azd env get-values", output.getvalue())
        self.assertIn("Command executed successfully", output.getvalue())
        with self.assertRaises(ValueError):
            utils.set_output_verbose("yes")

    def test_successful_child_checks_are_counted_without_individual_logs(self):
        run = ValidationRun("feature")
        output = io.StringIO()
        with redirect_stdout(output), utils.notebook_step("Validate fragments", namespace={"run": run}):
            for index in range(25):
                run.check(f"fragment-{index}", True)
        self.assertEqual(len(output.getvalue().splitlines()), 2)
        self.assertIn("25/25 passed", output.getvalue())
        self.assertEqual(len(run.results), 25)

    def test_diagnostic_failures_still_surface(self):
        output = io.StringIO()
        with redirect_stdout(output), patch("validationtools.subprocess.run", return_value=
                subprocess.CompletedProcess([], 1, "", "Environment not selected")), \
                patch("validationtools.shutil.which", return_value=None), self.assertRaises(ValidationError):
            _run_json(["azd", "env", "get-values"])
        self.assertIn("RESULT | ERROR", output.getvalue())
        self.assertIn("Environment not selected", output.getvalue())

    def test_compact_html_keeps_large_payloads_closed_by_default(self):
        with patch.object(utils, "_notebook_display", return_value=True), \
                patch("IPython.display.display") as display:
            utils.format_output("Preview", {"parameters": {"models": ["deployed-model"],
                                "long field": "x" * 1000}})
        markup = display.call_args.args[0].data
        self.assertIn("deployed-model", markup)
        self.assertIn("<details", markup)
        self.assertNotIn("<details open", markup)
        self.assertNotIn("INFO | INFO", markup)

    def test_warning_messages_are_deduplicated_within_a_step(self):
        output = io.StringIO()
        with redirect_stdout(output), utils.notebook_step("Inspect retirement"):
            warnings.warn("Retirement metadata needs review")
            warnings.warn("Retirement metadata needs review")
        self.assertEqual(output.getvalue().count("Retirement metadata needs review"), 1)

    def test_future_retirement_is_not_a_warning_and_duplicate_past_dates_warn_once(self):
        backends = [
            {"backendId": name, "backendType": "ai-foundry", "supportedModels": [
                {"name": "future-model", "retirementDate": "2099-12-31"},
                {"name": "past-model", "retirementDate": "2000-01-01"},
            ]} for name in ("east", "west")
        ]
        with warnings.catch_warnings(record=True) as captured:
            warnings.simplefilter("always")
            catalog = ModelCatalog(backends, {"future-model": ["chat"], "past-model": ["chat"]})
        self.assertEqual(len(captured), 1)
        self.assertIn("past-model", str(captured[0].message))
        self.assertEqual(catalog.select("chat", override="past-model"), "past-model")

    def test_http_output_summarizes_embeddings_instead_of_dumping_vectors(self):
        response = Mock(status_code=200, headers={})
        response.json.return_value = {"data": [{"embedding": [0.123456] * 3072}]}
        output = io.StringIO()
        with redirect_stdout(output):
            utils.format_http_response(response, elapsed=0.1)
        self.assertEqual(len(output.getvalue().splitlines()), 1)
        self.assertIn("3072 dimensions", output.getvalue())
        self.assertNotIn("0.123456", output.getvalue())

    def test_zero_and_false_results_are_not_silently_hidden(self):
        output = io.StringIO()
        with redirect_stdout(output):
            utils.format_output("Count", 0)
            utils.format_output("Condition", False)
        self.assertIn(" | 0\n", output.getvalue())
        self.assertIn(" | False\n", output.getvalue())


class RequiredInputTests(unittest.TestCase):
    def test_shared_package_imports_work_without_inserting_shared_on_sys_path(self):
        root = str(Path(__file__).resolve().parents[2])
        source = (
            f"import sys; sys.path.insert(0, {root!r}); "
            "from shared import utils, validationtools, contracttools, consumerhelpers; "
            "assert validationtools.utils is utils; assert contracttools.utils is utils; "
            "assert consumerhelpers.utils is utils; "
            "utils.format_result('Package imports work')"
        )
        result = subprocess.run(
            [sys.executable, "-S", "-c", source], capture_output=True, text=True,
            encoding="utf-8", check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Package imports work", result.stdout)

    def test_all_missing_gateway_parameters_are_reported_before_account_lookup(self):
        with patch("validationtools._run_json") as command, self.assertRaises(ValidationError) as error:
            ValidationContext.load(
                from_azd=False,
                overrides={"resource_group": "REPLACE", "location": "", "subscription_id": "REPLACE"},
            )
        for label in ("resource_group", "location", "subscription_id", "apim_name"):
            self.assertIn(label, str(error.exception))
        command.assert_not_called()

    def test_setup_formatters_work_without_site_packages(self):
        shared = str(Path(__file__).resolve().parents[2] / "shared")
        result = subprocess.run(
            [sys.executable, "-S", "-c",
             f"import sys; sys.path.insert(0, {shared!r}); import utils; "
             "utils.format_result('Setup helpers imported')"],
            capture_output=True, text=True, encoding="utf-8", check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("RESULT | SUCCESS", result.stdout)

    def test_nested_placeholder_inputs_are_aggregated_without_secret_values(self):
        with self.assertRaises(ValueError) as error:
            utils.require_inputs({
                "foundry": {"accountName": "REPLACE-account", "projectName": "", "subscriptionId": "valid"},
                "vault": {"name": "https://REPLACE.vault.azure.net"},
                "token": "REPLACE-super-private-token",
            })
        text = str(error.exception)
        for label in ("foundry.accountName", "foundry.projectName", "vault.name", "token"):
            self.assertIn(label, text)
        self.assertNotIn("super-private", text)
        self.assertNotIn("valid", text)

    def test_supplied_inputs_pass_and_disabled_scenarios_do_not_need_unused_fields(self):
        utils.require_inputs({"active.target": {"name": "actual-name"}})
        utils.require_inputs({})

    def test_required_approval_false_and_paths_with_placeholders_fail(self):
        with self.assertRaises(ValueError) as error:
            utils.require_inputs({"approval": False, "manifest": Path("REPLACE.json")})
        self.assertIn("approval", str(error.exception))
        self.assertIn("manifest", str(error.exception))

    def test_strict_missing_capabilities_stop_before_test_execution(self):
        backend = {"backendId": "one", "backendType": "ai-foundry",
                   "supportedModels": [{"name": "deployed-model"}]}
        with self.assertRaisesRegex(ValueError, "VALIDATION_MODEL_CAPABILITIES"):
            utils.require_capabilities(ModelCatalog([backend], infer_operations=False))
        utils.require_capabilities(ModelCatalog([backend], {"deployed-model": ["chat"]}))


if __name__ == "__main__":
    unittest.main()
