"""Offline regression tests: synthetic metadata and mocked CLI/HTTP calls."""

import copy
import io
import json
import subprocess
import unittest
import warnings
from contextlib import redirect_stdout
from unittest.mock import Mock, patch

import requests

from shared.validationtools import (
    HTTPResult, ModelCatalog, RequestTransport, ValidationBlocked,
    ValidationContext, ValidationError, ValidationRun, merge_backends, redact,
    valid_chat, valid_embeddings, valid_response,
)


def backend(name="future-model", backend_id="east", backend_type="azure-openai", **metadata):
    return {
        "backendId": backend_id, "backendType": backend_type,
        "supportedModels": [{"name": name, **metadata}],
    }


def config(**values):
    return {
        "AZURE_RESOURCE_GROUP": "resource-group",
        "AZURE_LOCATION": "eastus",
        "AZURE_SUBSCRIPTION_ID": "subscription",
        "APIM_NAME": "gateway",
        "LLM_BACKEND_CONFIG": json.dumps([backend()]),
        "VALIDATION_MODEL_CAPABILITIES": json.dumps({"future-model": ["chat", "responses"]}),
        **values,
    }


def cli_json(value):
    return subprocess.CompletedProcess([], 0, stdout=json.dumps(value), stderr="")


@patch("shared.validationtools.shutil.which", return_value=None)
class ContextTests(unittest.TestCase):
    @patch("shared.validationtools.subprocess.run")
    def test_setup_azure_entra_aliases_and_explicit_overrides(self, run, _which):
        run.side_effect = [
            cli_json(config(AZURE_CLIENT_ID="setup-client", AZURE_TENANT_ID="tenant",
                            AZURE_AUDIENCE="api://setup-client")),
            cli_json({"id": "subscription", "tenantId": "tenant"}),
        ]
        context = ValidationContext.load({"entra_client_id": "override-client"})
        self.assertEqual(context.config["entra_client_id"], "override-client")
        self.assertEqual(context.config["entra_tenant_id"], "tenant")
        self.assertEqual(context.config["entra_audience"], "api://setup-client")

    @patch("shared.validationtools.subprocess.run")
    def test_reads_environment_and_account_once_with_argument_vectors(self, run, _which):
        run.side_effect = [cli_json(config()), cli_json({"id": "subscription", "tenantId": "tenant"})]
        context = ValidationContext.load(environment="environment with spaces")
        self.assertEqual(context.catalog.select("chat"), "future-model")
        self.assertTrue((context.root / "shared" / "validationtools.py").is_file())
        self.assertEqual(context.account["tenantId"], "tenant")
        self.assertEqual(context.catalog.operations("future-model"), ["chat", "responses"])
        self.assertEqual(run.call_count, 2)
        self.assertEqual(run.call_args_list[0].args[0], [
            "azd", "env", "get-values", "--output", "json",
            "--environment", "environment with spaces",
        ])
        self.assertEqual(run.call_args_list[1].args[0], ["az", "account", "show", "--output", "json"])
        self.assertFalse(run.call_args.kwargs["shell"])

    @patch("shared.validationtools.subprocess.run")
    def test_explicit_configuration_wins_and_false_is_preserved(self, run, _which):
        run.side_effect = [cli_json(config(enable_key_vault=True)), cli_json({"id": "other"})]
        context = ValidationContext.load({
            "resource_group": "explicit-group", "subscription_id": "other",
            "enable_key_vault": False, "capabilities": {"future-model": ["embeddings"]},
        })
        self.assertEqual(context.config["resource_group"], "explicit-group")
        self.assertFalse(context.config["enable_key_vault"])
        self.assertEqual(context.catalog.select("embeddings"), "future-model")
        self.assertEqual(context.catalog.models_for("chat"), [])
        self.assertEqual(context.provenance["subscription_id"], "explicit")

    @patch("shared.validationtools.subprocess.run")
    def test_manual_mode_only_checks_account(self, run, _which):
        run.return_value = cli_json({"id": "subscription"})
        context = ValidationContext.load(config(), from_azd=False)
        self.assertEqual(context.config["apim_name"], "gateway")
        run.assert_called_once()
        self.assertEqual(run.call_args.args[0][0], "az")

    @patch("shared.validationtools.subprocess.run")
    def test_manual_requires_coordinates_before_account_lookup(self, run, _which):
        with self.assertRaisesRegex(ValidationError, "resource_group"):
            ValidationContext.load(from_azd=False)
        run.assert_not_called()

    @patch("shared.validationtools.subprocess.run")
    def test_malformed_json_and_command_errors_are_not_silent(self, run, _which):
        for returned in (
            subprocess.CompletedProcess([], 1, "", "unauthenticated"),
            subprocess.CompletedProcess([], 0, "log output\n{}", ""),
            cli_json([]),
        ):
            run.return_value = returned
            with self.assertRaises(ValidationError):
                ValidationContext.load()
        for error in (FileNotFoundError("missing"), subprocess.TimeoutExpired("azd", 120)):
            run.side_effect = error
            with self.assertRaises(ValidationError):
                ValidationContext.load()

    @patch("shared.validationtools.subprocess.run")
    def test_nested_json_failure_and_placeholders_are_rejected(self, run, _which):
        for key, value in (("LLM_BACKEND_CONFIG", "{"), ("APIM_NAME", "<gateway>")):
            run.return_value = cli_json(config(**{key: value}))
            with self.assertRaises(ValidationError):
                ValidationContext.load()

    @patch("shared.validationtools.subprocess.run")
    def test_account_mismatch_is_not_changed_automatically(self, run, _which):
        run.side_effect = [cli_json(config()), cli_json({"id": "different"})]
        with self.assertRaisesRegex(ValidationError, "subscription"):
            ValidationContext.load()
        self.assertEqual(run.call_count, 2)

    @patch("shared.validationtools.subprocess.run")
    def test_missing_account_id_and_tenant_mismatch_fail(self, run, _which):
        for account in ({}, {"id": "subscription", "tenantId": "wrong"}):
            run.side_effect = [cli_json(config(ENTRA_TENANT_ID="tenant")), cli_json(account)]
            with self.assertRaises(ValidationError):
                ValidationContext.load()

    @patch("shared.validationtools.subprocess.run")
    def test_no_global_environment_cache(self, run, _which):
        run.side_effect = [
            cli_json(config(APIM_NAME="first")), cli_json({"id": "subscription"}),
            cli_json(config(APIM_NAME="second")), cli_json({"id": "subscription"}),
        ]
        first = ValidationContext.load(environment="first")
        second = ValidationContext.load(environment="second")
        self.assertEqual((first.config["apim_name"], second.config["apim_name"]), ("first", "second"))
        self.assertEqual(run.call_count, 4)

    @patch("shared.validationtools.subprocess.run")
    def test_wrong_selected_environment_is_rejected(self, run, _which):
        run.return_value = cli_json(config(AZURE_ENV_NAME="wrong"))
        with self.assertRaisesRegex(ValidationError, "different environment"):
            ValidationContext.load(environment="requested")

    @patch("shared.validationtools.subprocess.run")
    def test_missing_enabled_integrations_fail(self, run, _which):
        for value in (
            {"enable_key_vault": True},
            {"enable_entra_auth": True},
            {"enable_foundry_integration": True},
            {"enable_foundry_integration": True, "AI_FOUNDRY_SERVICES": '[{"name":"one"},{"name":"two"}]'},
            {"enable_key_vault": "not-a-boolean"},
        ):
            run.return_value = cli_json(config(**value))
            with self.assertRaises(ValidationError):
                ValidationContext.load()

    @patch("shared.validationtools.subprocess.run")
    def test_backend_overrides_preserve_azd_snapshot(self, run, _which):
        original = backend(protocol="openai")
        original["authConfig"] = {"secretValue": "top-secret", "namedValueKey": "provider-key"}
        original["circuitBreaker"] = {"enabled": True, "tripDuration": "PT1M"}
        snapshot = config(LLM_BACKEND_CONFIG=json.dumps([original]))
        run.side_effect = [cli_json(snapshot), cli_json({"id": "subscription"})]
        context = ValidationContext.load({
            "llm_backends": [{"backendId": "east", "supportedModels": [{"name": "future-model", "apiVersion": "next"}]}],
        })
        self.assertEqual(context.config["llm_backends"][0]["authConfig"], original["authConfig"])
        self.assertEqual(context.config["llm_backends"][0]["circuitBreaker"], original["circuitBreaker"])
        self.assertEqual(context.azd_snapshot, snapshot)
        self.assertNotIn("top-secret", json.dumps(context.report()))
        self.assertNotIn("top-secret", repr(context))
        self.assertNotIn("top-secret", repr(context.catalog.entries))

    @patch("shared.validationtools.Path.is_file", return_value=True)
    @patch("shared.validationtools.subprocess.run")
    def test_windows_azure_cli_wrapper_uses_native_python_vector(self, run, _is_file, which):
        which.return_value = r"C:\CLI2\wbin\az.cmd"
        run.return_value = cli_json({"id": "subscription"})
        ValidationContext.load(config(), from_azd=False)
        self.assertEqual(run.call_args.args[0], [
            r"C:\CLI2\python.exe", "-IB", "-X", "utf8", "-m", "azure.cli",
            "account", "show", "--output", "json",
        ])
        self.assertFalse(run.call_args.kwargs["shell"])


class CatalogTests(unittest.TestCase):
    def test_arbitrary_name_and_nonchat_operation(self):
        catalog = ModelCatalog([backend("whatever-2099")], {"whatever-2099": ["embeddings"]})
        self.assertEqual(catalog.select("embeddings"), "whatever-2099")
        with self.assertRaises(ValidationBlocked):
            catalog.select("chat")

    def test_name_inference_does_not_trust_blanket_chat_flag_for_embeddings(self):
        catalog = ModelCatalog([
            backend("gpt-example", chatCompletion="true"),
            backend("text-example", "west", chatCompletion="true"),
        ])
        self.assertEqual(catalog.models_for("chat"), ["gpt-example"])
        self.assertEqual(catalog.operations("gpt-example"), ["chat", "responses"])
        self.assertEqual(catalog.operations("text-example"), ["embeddings"])

    def test_explicit_metadata_overrides_operations(self):
        catalog = ModelCatalog([backend(operations=["chat"])], {"future-model": []})
        self.assertEqual(catalog.models_for("chat"), [])

    def test_trustworthy_explicit_operation_metadata(self):
        catalog = ModelCatalog([backend(operations=["chat", "embeddings"])])
        self.assertEqual(catalog.select("embeddings"), "future-model")

    def test_selection_is_deployment_order_not_name_sorting(self):
        catalog = ModelCatalog([backend("z"), backend("a", "west")], {"a": ["chat"], "z": ["chat"]})
        self.assertEqual(catalog.models_for("chat"), ["z", "a"])
        self.assertEqual(catalog.select("chat"), "z")
        self.assertEqual(catalog.select("chat", override="a"), "a")

    def test_overrides_validate_access_presence_type_and_capabilities(self):
        catalog = ModelCatalog(
            [backend("allowed"), backend("denied", "west")],
            {"allowed": ["chat"], "denied": ["chat"]}, allowed_models=["allowed"],
        )
        for name in ("denied", "missing"):
            with self.assertRaises(ValidationBlocked):
                catalog.select("chat", override=name)
        with self.assertRaises(ValidationBlocked):
            catalog.select("chat", override="allowed", backend_type="gemini")
        self.assertEqual(catalog.select("chat"), "allowed")

    def test_multi_backend_pool_requires_compatible_type_protocol_and_unique_ids(self):
        backends = [backend(), backend(backend_id="west")]
        catalog = ModelCatalog(backends, {"future-model": ["responses"]})
        self.assertEqual(catalog.select("responses", min_backends=2), "future-model")
        for other in (
            backend(backend_id="east"),
            backend(backend_id="west", backend_type="gemini"),
        ):
            with self.assertRaises(ValidationBlocked):
                ModelCatalog([backend(), other], {"future-model": ["responses"]}).select("responses", min_backends=2)
        first, second = backend(), backend(backend_id="west")
        first["protocol"], second["protocol"] = "openai", "native"
        with self.assertRaises(ValidationBlocked):
            ModelCatalog([first, second], {"future-model": ["responses"]}).select("responses", min_backends=2)

    def test_aliases_validate_distinct_members_protocol_and_access(self):
        catalog = ModelCatalog(
            [backend("one"), backend("two", "west"), backend("native", "native", "gemini")],
            {"one": ["chat"], "two": ["chat"], "native": ["chat"]},
        )
        self.assertEqual(catalog.alias_members(["one", "two"], "chat", min_members=2), ["one", "two"])
        for members in (["one", "one"], ["one"], ["one", "missing"], ["one", "native"]):
            with self.assertRaises(ValidationBlocked):
                catalog.alias_members(members, "chat", min_members=2)

    def test_cross_cloud_alias_accepts_explicit_common_wire_protocol(self):
        providers = ("ai-foundry", "aws-bedrock-mantle", "gemini-openai")
        backends = [
            backend(f"model-{index}", f"backend-{index}", provider, protocol="openai-compat")
            for index, provider in enumerate(providers)
        ]
        names = [item["supportedModels"][0]["name"] for item in backends]
        catalog = ModelCatalog(backends, {name: ["chat"] for name in names})
        self.assertEqual(catalog.alias_members(names, "chat", min_members=3), names)
        self.assertEqual(catalog.validate_alias(names, "chat", min_members=3), names)

    def test_cross_cloud_alias_blocks_unknown_or_conflicting_wire_protocol(self):
        for protocol in (None, "", "native-gemini"):
            first = backend("one", "east", "ai-foundry", protocol="openai-compat")
            second = backend("two", "west", "gemini-openai")
            if protocol is not None:
                second["supportedModels"][0]["protocol"] = protocol
            catalog = ModelCatalog([first, second], {"one": ["chat"], "two": ["chat"]})
            with self.assertRaises(ValidationBlocked):
                catalog.alias_members(["one", "two"], "chat")

    def test_cross_cloud_alias_respects_explicit_protocol_and_access_filters(self):
        first = backend("one", "east", "ai-foundry", protocol="openai-compat")
        second = backend("two", "west", "gemini-openai")
        first["protocol"], second["protocol"] = "native-a", "native-b"
        second["supportedModels"][0]["protocol"] = "openai-compat"
        catalog = ModelCatalog([first, second], {"one": ["chat"], "two": ["chat"]})
        self.assertEqual(catalog.validate_alias(["one", "two"], "chat"), ["one", "two"])
        with self.assertRaises(ValidationBlocked):
            catalog.validate_alias(["one", "two"], "chat", backend_type="ai-foundry")
        restricted = ModelCatalog(
            [first, second], {"one": ["chat"], "two": ["chat"]}, allowed_models=["one"],
        )
        with self.assertRaises(ValidationBlocked):
            restricted.validate_alias(["one", "two"], "chat")
        unsupported = ModelCatalog([first, second], {"one": ["chat"], "two": ["embeddings"]})
        with self.assertRaises(ValidationBlocked):
            unsupported.validate_alias(["one", "two"], "chat")
        with self.assertRaisesRegex(ValidationError, "protocol"):
            ModelCatalog([backend(protocol=["openai-compat"])])

    def test_cross_cloud_alias_does_not_create_cross_type_pools(self):
        backends = [
            backend("shared-model", "east", "ai-foundry", protocol="openai-compat"),
            backend("shared-model", "west", "aws-bedrock-mantle", protocol="openai-compat"),
        ]
        catalog = ModelCatalog(backends, {"shared-model": ["responses"]})
        with self.assertRaises(ValidationBlocked):
            catalog.select("responses", min_backends=2)

    def test_false_stateful_metadata_is_not_truthy(self):
        self.assertFalse(ModelCatalog([backend(sessionAwareModel="false")]).entries[0].session_aware)
        with self.assertRaises(ValidationError):
            ModelCatalog([backend(sessionAwareModel="unknown")])

    def test_retirement_warns_but_does_not_exclude(self):
        with warnings.catch_warnings(record=True) as captured:
            warnings.simplefilter("always")
            catalog = ModelCatalog([backend(retirementDate="2000-01-01")], {"future-model": ["chat"]})
        self.assertEqual(catalog.select("chat"), "future-model")
        self.assertIn("still eligible", str(captured[0].message))

    def test_preserves_deployment_distinction_and_provider_metadata(self):
        item = backend(
            deploymentName="deployment", modelVersion="v", modelFormat="f",
            apiVersion="api", inferenceApiVersion="inference", sessionAwareModel=True,
        )
        item.update(protocol="native", sessionAffinity={"cookieName": "custom"}, aliases=["alias"], path="/custom")
        original = copy.deepcopy(item)
        entry = ModelCatalog([item], {"future-model": ["responses"]}).entries[0]
        self.assertEqual(entry.name, "future-model")
        self.assertEqual(entry.deployment_name, "deployment")
        self.assertEqual(entry.api_version, "api")
        self.assertTrue(entry.session_aware)
        self.assertEqual(entry.session_affinity, {"cookieName": "custom"})
        self.assertEqual(entry.backend_metadata, original)
        self.assertEqual(item, original)

    def test_merge_preserves_fields_and_adds_models_without_mutation(self):
        original = [backend()]
        extra = [{"backendId": "east", "supportedModels": [{"name": "future-model", "capacity": 2}, {"name": "new"}]}]
        merged = merge_backends(original, extra)
        self.assertEqual(len(merged[0]["supportedModels"]), 2)
        self.assertEqual(merged[0]["backendType"], "azure-openai")
        self.assertEqual(original, [backend()])

    def test_reconciliation_reports_stale_and_unconfigured_models(self):
        catalog = ModelCatalog([backend("one"), backend("two", "west")])
        self.assertEqual(catalog.reconcile([{"id": "two"}, {"id": "three"}]), {
            "configured_only": ["one"], "discovered_only": ["three"], "common": ["two"],
        })

    def test_invalid_shapes_are_rejected(self):
        for backends, capabilities in (
            ({}, {}), ([{}], {}), ([backend()], {"future-model": "chat"}),
            ([backend()], {"future-model": [None]}), ([backend()], {"future-model": {"wrong": []}}),
        ):
            with self.assertRaises(ValidationError):
                ModelCatalog(backends, capabilities)
        catalog = ModelCatalog([backend()], {"future-model": ["chat"]})
        for value in (0, -1, True, 1.5):
            with self.assertRaises(ValidationError):
                catalog.select("chat", min_backends=value)


class ResultTests(unittest.TestCase):
    def finish(self, run):
        with redirect_stdout(io.StringIO()):
            return run.finish()

    def test_pass_and_optional_skip_have_visible_coverage(self):
        run = ValidationRun("feature")
        run.check("body", True, expected="content", actual="content", model="future-model")
        run.skip("optional", "disabled")
        self.assertEqual(self.finish(run), {
            "name": "feature", "planned": 2, "executed": 1,
            "PASS": 1, "FAIL": 0, "SKIP": 1, "BLOCKED": 0,
        })

    def test_early_failures_and_required_blocks_raise(self):
        for status in ("FAIL", "BLOCKED"):
            run = ValidationRun("feature")
            run.check("good", True)
            if status == "FAIL":
                run.check("bad", False)
            else:
                run.blocked("missing", "no token fixture")
            run.check("later", True)
            with self.assertRaises(ValidationError):
                self.finish(run)
            self.assertEqual(len(run.results), 3)

    def test_optional_failure_still_fails_and_optional_block_does_not(self):
        run = ValidationRun("feature")
        run.check("good", True)
        run.blocked("optional", "unavailable", required=False)
        self.finish(run)
        run.check("optional-fail", False, required=False)
        with self.assertRaises(ValidationError):
            self.finish(run)

    def test_empty_and_all_skipped_runs_never_pass(self):
        for mode in ("empty", "skip", "blocked"):
            run = ValidationRun("feature")
            if mode == "skip":
                run.skip("optional", "disabled")
            elif mode == "blocked":
                run.blocked("optional", "unavailable", required=False)
            with self.assertRaisesRegex(ValidationError, "No validation checks"):
                self.finish(run)

    def test_skip_and_block_require_reasons(self):
        run = ValidationRun("feature")
        with self.assertRaises(ValidationError):
            run.skip("case", "")
        with self.assertRaises(ValidationError):
            run.blocked("case", " ")

    def test_reports_redact_secrets_from_evidence_and_output(self):
        run = ValidationRun("feature")
        run.check("request", True, actual={"Authorization": "Bearer secret"}, headers={"api-key": "provider-secret"})
        self.assertNotIn("provider-secret", str(run.results[0]))
        output = io.StringIO()
        with redirect_stdout(output):
            run.finish()
        self.assertNotIn("Bearer secret", output.getvalue())

    def test_duplicate_case_names_retain_each_model_result(self):
        run = ValidationRun("all models")
        run.check("chat:one", False, model="one")
        run.check("chat:two", True, model="two")
        run.check("same-case", True, model="one")
        run.check("same-case", True, model="two")
        self.assertEqual(len(run.results), 4)
        with self.assertRaises(ValidationError):
            self.finish(run)


class TransportTests(unittest.TestCase):
    def response(self, status=200, body=None):
        response = Mock()
        response.status_code = status
        response.json.return_value = body
        response.text = json.dumps(body)
        response.headers = {"UAIG-backend-id": "east", "Set-Cookie": "secret-cookie"}
        response.content = response.text.encode()
        return response

    def test_body_check_and_expected_negative_status(self):
        session = Mock()
        session.request.return_value = self.response(403, {"error": {"code": "ModelNotAllowed"}})
        result = RequestTransport(session).request("POST", "https://gateway/models", json={"model": "future-model"})
        self.assertTrue(result.check(403, lambda body: body["error"]["code"] == "ModelNotAllowed"))
        self.assertFalse(result.check(403))
        self.assertFalse(result.check(403, lambda body: body["error"]["code"] == "WrongError"))
        session.request.assert_called_once()
        self.assertFalse(session.request.call_args.kwargs["allow_redirects"])
        self.assertEqual(session.request.call_args.kwargs["timeout"], 60)
        self.assertEqual(result.gateway_headers, {"UAIG-backend-id": "east"})
        self.assertNotIn("secret-cookie", json.dumps(result.report()))
        self.assertNotIn("secret-cookie", repr(result))

    def test_response_header_lookups_are_case_insensitive(self):
        session = Mock()
        response = self.response()
        response.headers = {"uaig-backend-id": "east", "retry-after": "1"}
        session.request.return_value = response
        result = RequestTransport(session).request("GET", "https://gateway")
        self.assertEqual(result.headers.get("UAIG-Backend-Id"), "east")
        self.assertEqual(result.headers.get("Retry-After"), "1")

    def test_malformed_successful_json_cannot_pass(self):
        session = Mock()
        response = self.response(200, {})
        response.json.side_effect = ValueError("bad JSON")
        session.request.return_value = response
        result = RequestTransport(session).request("GET", "https://gateway")
        self.assertFalse(result.check())
        self.assertIsNotNone(result.json_error)
        self.assertFalse(HTTPResult(200, {}, "", {}, b"", 1).check(body_check=valid_chat))

    def test_transport_errors_are_explicit_without_fake_status_or_retries(self):
        session = Mock()
        session.request.side_effect = requests.Timeout("https://gateway?api-key=credential")
        result = RequestTransport(session).request("GET", "https://gateway")
        self.assertIsNone(result.status_code)
        self.assertIn("Timeout", type(session.request.side_effect).__name__)
        self.assertNotIn("credential", result.error)
        self.assertFalse(result.check())
        session.request.assert_called_once()

    def test_multipart_binary_payload_is_not_rewritten(self):
        session = Mock()
        response = self.response()
        response.content = b"\x89PNGbinary"
        session.request.return_value = response
        files = {"image": ("image.png", b"input", "image/png")}
        result = RequestTransport(session).request("POST", "https://gateway/images", files=files, data={"model": "image"})
        self.assertIs(session.request.call_args.kwargs["files"], files)
        self.assertEqual(result.content, b"\x89PNGbinary")
        self.assertTrue(result.check(require_json=False, body_check=lambda content: content.startswith(b"\x89PNG")))

    def test_sessions_have_independent_cookie_jars_and_no_retry_adapters(self):
        first, second = RequestTransport(), RequestTransport()
        first.session.cookies.set("affinity", "east")
        self.assertEqual(list(second.session.cookies), [])
        self.assertEqual(first.session.get_adapter("https://").max_retries.total, 0)
        first.close()
        second.close()

    def test_streaming_is_explicit_and_timeouts_bounded(self):
        for timeout in (0, -1, float("inf"), float("nan")):
            with self.assertRaises(ValidationError):
                RequestTransport(timeout=timeout)
        transport = RequestTransport(Mock())
        with self.assertRaisesRegex(ValidationError, "streaming"):
            transport.request("GET", "https://gateway", stream=True)
        for value in (None, (1, None), 0, float("inf")):
            with self.assertRaises(ValidationError):
                transport.request("GET", "https://gateway", timeout=value)

    def test_injected_session_must_not_hide_retries(self):
        session = requests.Session()
        session.mount("https://", requests.adapters.HTTPAdapter(max_retries=3))
        with self.assertRaisesRegex(ValidationError, "implicit retries"):
            RequestTransport(session)
        session.close()

    def test_response_shape_helpers(self):
        self.assertTrue(valid_chat({"choices": [{"message": {"content": "ok"}}]}))
        self.assertFalse(valid_chat({"choices": []}))
        self.assertTrue(valid_embeddings({"data": [{"embedding": [0, 0.5]}, {"embedding": [1, 2]}]}))
        for body in (
            {"data": []}, {"data": [{"embedding": []}]},
            {"data": [{"embedding": [float("nan")]}]},
            {"data": [{"embedding": [True]}]},
            {"data": [{"embedding": [1]}, {"embedding": [1, 2]}]},
        ):
            self.assertFalse(valid_embeddings(body))
        body = {"id": "response-id", "status": "completed", "output": [{"content": [{"text": "hello"}]}]}
        self.assertTrue(valid_response(body))
        self.assertFalse(valid_response({**body, "status": "incomplete"}))
        self.assertFalse(valid_response({"id": "response-id", "status": "completed", "output": []}))
        self.assertFalse(valid_response({"id": "response-id", "status": "completed", "output": [{"content": None}]}))


class RedactionTests(unittest.TestCase):
    def test_headers_nested_secrets_and_url_credentials(self):
        value = {
            "headers": {"Authorization": "Bearer token", "Ocp-Apim-Subscription-Key": "key"},
            "provider": [{"secretValue": "secret", "api_key": "other"}],
            "url": "https://user:password@gateway/path?sig=signature&api-key=key&model=visible",
        }
        safe = json.dumps(redact(value))
        for secret in ("Bearer token", '"key"', '"secret"', '"other"', "user:password", "sig=signature"):
            self.assertNotIn(secret, safe)
        self.assertIn("model=visible", safe)

    def test_free_text_json_and_bearer_are_redacted(self):
        for value in (
            '{"api_key": "credential"}', "Authorization: Bearer credential",
            "api-key=credential", "secretValue=credential",
            "access_token=credential",
        ):
            self.assertNotIn("credential", redact(value))


if __name__ == "__main__":
    unittest.main()
