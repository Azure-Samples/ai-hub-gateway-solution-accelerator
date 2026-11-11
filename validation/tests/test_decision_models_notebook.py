import copy
import contextlib
import io
import json
import re
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "shared"))

import decisiontools
import contracttools
import validationtools
from validationtools import HTTPResult, ModelCatalog
from test_notebook_experience import cells, configured, context_fixture, initialized_apim


NOTEBOOK = "citadel-decision-models-tests.ipynb"
APIM_RESOURCE_ID = (
    "/subscriptions/fixture-subscription/resourceGroups/fixture-rg/providers/"
    "Microsoft.ApiManagement/service/fixture-apim"
)


def backends():
    return [
        {"backendId": "foundry", "backendType": "ai-foundry",
         "endpoint": "https://fixture.services.ai.azure.com/",
         "supportedModels": [{"name": "custom-openai",
                              "operations": ["decisions", "chat", "responses"]}]},
        {"backendId": "native", "backendType": "azure-decision",
         "endpoint": "https://fixture.services.ai.azure.com/",
         "supportedModels": [{"name": "custom-microsoft"}]},
    ]


def live_contract():
    return {
        "apim": {"subscriptionId": "fixture-subscription", "resourceGroupName": "fixture-rg",
                 "name": "fixture-apim"},
        "backends": backends(), "modelAliases": [],
        "circuitBreaker": {"enabled": False, "defaults": {}},
        "sessionAffinity": {"enabled": False, "defaults": {}},
        "pools": [
            {"poolName": "foundry", "poolType": "ai-foundry", "supportedModels": ["custom-openai"]},
            {"poolName": "native", "poolType": "azure-decision", "supportedModels": ["custom-microsoft"]},
        ],
    }


def response(payload, operation):
    questions = (payload["questions"].items() if operation == "systemone"
                 else ((q["name"], q) for q in payload["questions"]))
    answers = {}
    for name, question in questions:
        kind = question["type"]
        answer = {"name": name, "type": kind}
        if kind in ("noul", "predicate"):
            answer["noul" if kind == "noul" else "probability"] = 0.9
        else:
            answer.update(confidence=0.8)
            if kind == "choice":
                answer.update(choice="engineering", probabilities={
                    "engineering": 0.9, "billing": 0.1,
                })
            else:
                answer.update(score=1.5, probabilities={"0": 0.1, "1": 0.3, "2": 0.6})
            if operation == "decisions":
                answer["probabilities"] = [
                    {"value": value if kind == "choice" else int(value), "probability": probability}
                    for value, probability in answer["probabilities"].items()
                ]
        answers[name] = answer
    usage = {"input_tokens": 20, "output_tokens": 0}
    if operation == "decisions":
        usage["total_tokens"] = 20
    return {"model": "underlying-model-not-deployment", "usage": usage,
            "answers": answers if operation == "systemone" else list(answers.values())}


class DecisionEvidenceTests(unittest.TestCase):
    def test_payload_generation_rejects_missing_or_invalid_deployment_names(self):
        for operation in ("decisions", "systemone"):
            for model in (None, "", " ", 42, False):
                with self.subTest(operation=operation, model=model), self.assertRaisesRegex(ValueError, "model"):
                    decisiontools.decision_payload(operation, model)

    def test_http_failure_reports_backend_error_not_missing_response_model(self):
        payload = decisiontools.decision_payload("decisions", "gpt-6-luna")
        for body in (
            {"message": "The requested operation is unsupported."},
            {"error": {"message": "The requested operation is unsupported."}},
        ):
            result = HTTPResult(400, body, "", {"x-ms-region": "East US 2"}, b"", 0)
            errors = decisiontools.decision_inference_errors(result, payload, "decisions")
            self.assertEqual(len(errors), 1)
            for evidence in ("HTTP 400", "East US 2", "unsupported", "gpt-6-luna"):
                self.assertIn(evidence, errors[0])
            self.assertNotIn("Response has no model identity", errors[0])
            self.assertNotIn("Response has no actual token usage", errors[0])

    def test_inference_errors_keep_transport_and_json_failures_explicit(self):
        payload = decisiontools.decision_payload("systemone", "Decision-1")
        transport_error = HTTPResult(None, None, "", {}, b"", 0, error="Timed out")
        self.assertIn("Timed out", decisiontools.decision_inference_errors(
            transport_error, payload, "systemone",
        )[0])
        invalid_json = HTTPResult(200, None, "not json", {}, b"", 0, json_error="Invalid JSON")
        self.assertEqual(decisiontools.decision_inference_errors(
            invalid_json, payload, "systemone",
        ), ["Invalid JSON"])

    def test_local_additions_are_target_bound_and_idempotent(self):
        source = {"apim": live_contract()["apim"], "llmBackendConfig": backends()[:1]}
        config = {"apim": source["apim"], "backends": backends()[1:]}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "additions.json"
            path.write_text(json.dumps(config), encoding="utf-8")
            pending = decisiontools.load_local_backend_additions(path, source)
            self.assertEqual(pending, backends()[1:])
            self.assertEqual(source["llmBackendConfig"], backends()[:1])
            self.assertEqual(decisiontools.load_local_backend_additions(
                path, {**source, "llmBackendConfig": backends()},
            ), [])
            uppercase_target = {**config, "apim": {key: value.upper() for key, value in config["apim"].items()}}
            path.write_text(json.dumps(uppercase_target), encoding="utf-8")
            self.assertEqual(decisiontools.load_local_backend_additions(path, source), backends()[1:])
            for alteration in ("target", "duplicate", "changed", "malformed"):
                changed = copy.deepcopy(config)
                if alteration == "target":
                    changed["apim"]["name"] = "different"
                elif alteration == "duplicate":
                    changed["backends"].append(changed["backends"][0])
                elif alteration == "changed":
                    changed["backends"][0]["endpoint"] = "https://different.services.ai.azure.com/"
                else:
                    changed["backends"] = [None]
                path.write_text(json.dumps(changed), encoding="utf-8")
                with self.subTest(alteration=alteration), self.assertRaises(ValueError):
                    decisiontools.load_local_backend_additions(
                        path, {**source, "llmBackendConfig": backends()},
                    )

    def test_native_payloads_and_real_typed_answers(self):
        for operation in ("decisions", "systemone"):
            payload = decisiontools.decision_payload(operation, "deployment")
            with self.subTest(operation=operation):
                self.assertEqual(payload["model"], "deployment")
                self.assertEqual(decisiontools.decision_response_errors(
                    response(payload, operation), payload, operation), [])
                self.assertEqual("state" in payload, operation == "systemone")
                self.assertEqual(isinstance(payload["questions"], list), operation == "decisions")
        payload = decisiontools.decision_payload("systemone", "deployment", json_state=True)
        self.assertIsInstance(payload["state"], dict)
        payload = decisiontools.decision_payload("decisions", "deployment", image_url="data:image/png;base64,fixture")
        self.assertEqual(payload["input"][0]["content"][1]["type"], "input_image")

    def test_malformed_success_refusals_and_numeric_bounds_fail(self):
        for operation in ("decisions", "systemone"):
            payload = decisiontools.decision_payload(operation, "deployment")
            good = response(payload, operation)
            for alteration in ("missing", "refusal", "probability", "choice", "score", "usage"):
                value = copy.deepcopy(good)
                answer = (value["answers"]["outage"] if operation == "systemone"
                          else value["answers"][0])
                if alteration == "missing":
                    value["answers"] = {}
                elif alteration == "refusal":
                    answer["type"] = "refusal"
                elif alteration == "probability":
                    answer["noul" if operation == "systemone" else "probability"] = float("nan")
                elif alteration in ("choice", "score"):
                    index = "team" if alteration == "choice" else "severity"
                    changed = value["answers"][index] if operation == "systemone" else value["answers"][1 if alteration == "choice" else 2]
                    changed[alteration] = "unknown" if alteration == "choice" else 3
                else:
                    value["usage"] = {}
                with self.subTest(operation=operation, alteration=alteration):
                    self.assertTrue(decisiontools.decision_response_errors(value, payload, operation))
        payload = decisiontools.decision_payload("decisions", "deployment")
        value = response(payload, "decisions")
        value["answers"][1]["probabilities"] = {"engineering": 0.9, "billing": 0.1}
        self.assertTrue(decisiontools.decision_response_errors(value, payload, "decisions"))

    def test_request_policy_has_exact_limits_and_no_token_policy(self):
        contract = dict(allowed_models=["first", "second"], requests_per_minute=7,
                        request_quota=9, quota_period_seconds=86400)
        root = ET.fromstring(decisiontools.build_product_policy_xml(contract))
        self.assertEqual(root.find(".//rate-limit-by-key").get("calls"), "7")
        self.assertEqual(root.find(".//quota-by-key").get("calls"), "9")
        self.assertIsNone(root.find(".//llm-token-limit"))
        for value in (0, -1, True):
            with self.subTest(value=value), self.assertRaises(ValueError):
                decisiontools.build_product_policy_xml({**contract, "request_quota": value})
        with self.assertRaises(ValueError):
            decisiontools.build_product_policy_xml({**contract, "quota_period_seconds": 299})
        scoped = ET.fromstring(decisiontools.build_product_policy_xml({**contract, "counter_scope": "run123"}))
        self.assertIn("run123", scoped.find(".//quota-by-key").get("counter-key"))

    def test_release_note_and_component_tracks_match_manifest(self):
        manifest = json.loads((ROOT / "release.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["routing-version"], "1.1.0")
        self.assertEqual(manifest["backend-contract-version"], "1.2.0")
        self.assertEqual(manifest["access-contract-version"], "1.2.0")
        note = ROOT / "releases" / (manifest["master-version"] + ".md")
        self.assertTrue(note.is_file())
        self.assertIn("Known limitations", note.read_text(encoding="utf-8"))

    def test_catalog_distinguishes_decisions_without_changing_old_inference(self):
        catalog = ModelCatalog(backends())
        self.assertEqual(catalog.models_for("systemone"), ["custom-microsoft"])
        self.assertEqual(catalog.models_for("decisions"), ["custom-openai"])
        self.assertEqual(catalog.models_for("chat"), ["custom-openai"])
        self.assertEqual(ModelCatalog(backends(), {"custom-microsoft": []}).models_for("systemone"), [])
        self.assertEqual(validationtools.infer_model_operations("gpt-example"), ["chat", "responses"])

    def test_complete_source_preserves_live_settings_and_rejects_drift(self):
        live = live_contract()
        source = {"apim": live["apim"], "llmBackendConfig": backends(), "modelAliases": []}
        original = copy.deepcopy(source)
        effective = decisiontools.preserve_live_contract(source, live)
        self.assertEqual(source, original)
        self.assertIs(effective["configureCircuitBreaker"], False)
        self.assertEqual(effective["llmBackendConfig"], live["backends"])
        for alteration in ("omitted", "model", "alias", "settings", "endpoint", "target"):
            changed = copy.deepcopy(source)
            if alteration == "omitted":
                changed["llmBackendConfig"].pop()
            elif alteration == "model":
                changed["llmBackendConfig"][0]["supportedModels"][0]["timeout"] = 1
            elif alteration == "alias":
                changed["modelAliases"] = [{"name": "new-alias"}]
            elif alteration == "settings":
                changed["configureCircuitBreaker"] = True
            elif alteration == "endpoint":
                changed["llmBackendConfig"][1]["endpoint"] += "providers/microsoft/v1/systemone"
            else:
                changed["apim"] = {**changed["apim"], "name": "other"}
            with self.subTest(alteration=alteration), self.assertRaises(ValueError):
                decisiontools.preserve_live_contract(changed, live)

    def test_existing_openai_deployment_can_gain_only_additive_capability_metadata(self):
        live = live_contract()
        live["backends"][0]["supportedModels"][0]["operations"] = ["chat", "responses"]
        source = {"apim": live["apim"], "llmBackendConfig": backends(), "modelAliases": []}
        effective = decisiontools.preserve_live_contract(source, live)
        self.assertIn("decisions", effective["llmBackendConfig"][0]["supportedModels"][0]["operations"])
        source["llmBackendConfig"][0]["supportedModels"][0]["operations"] = ["decisions"]
        with self.assertRaises(ValueError):
            decisiontools.preserve_live_contract(source, live)

    def test_empty_live_target_requires_verified_arm_identity_and_warns(self):
        live = live_contract()
        source = {"apim": copy.deepcopy(live["apim"]), "llmBackendConfig": backends(), "modelAliases": []}
        live["apim"] = {}
        original = copy.deepcopy(live)
        with self.assertRaisesRegex(ValueError, "APIM coordinates"):
            decisiontools.preserve_live_contract(source, live)
        with patch("decisiontools.utils.print_warning") as warning:
            effective = decisiontools.preserve_live_contract(
                source, live, verified_apim_resource_id=APIM_RESOURCE_ID,
            )
        self.assertEqual(effective["apim"], source["apim"])
        self.assertEqual(effective["llmBackendConfig"], source["llmBackendConfig"])
        self.assertEqual(live, original)
        warning.assert_called_once()

    def test_verified_arm_identity_cannot_bypass_wrong_or_malformed_target(self):
        live = live_contract()
        source = {"apim": copy.deepcopy(live["apim"]), "llmBackendConfig": backends(), "modelAliases": []}
        for field in ("subscriptionId", "resourceGroupName", "name"):
            mismatch = copy.deepcopy(live)
            mismatch["apim"][field] = "different"
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "different APIM"):
                decisiontools.preserve_live_contract(
                    source, mismatch, verified_apim_resource_id=APIM_RESOURCE_ID,
                )
        for target in (None, [], "", {"name": "fixture-apim"}):
            live["apim"] = target
            with self.subTest(target=target), self.assertRaises(ValueError):
                decisiontools.preserve_live_contract(
                    source, live, verified_apim_resource_id=APIM_RESOURCE_ID,
                )
        live["apim"] = {}
        for resource_id in (
            "", "/fixture/apim", APIM_RESOURCE_ID + "/apis/unified-ai",
            APIM_RESOURCE_ID.replace("/service/", "/products/"),
            APIM_RESOURCE_ID.replace("fixture-apim", "different"),
            APIM_RESOURCE_ID.replace("fixture-subscription", "different"),
            APIM_RESOURCE_ID.replace("fixture-rg", "different"),
        ):
            with self.subTest(resource_id=resource_id), self.assertRaises(ValueError):
                decisiontools.preserve_live_contract(
                    source, live, verified_apim_resource_id=resource_id,
                )

    def test_apim_identity_matches_azure_case_insensitive_resource_names(self):
        live = live_contract()
        source = {"apim": copy.deepcopy(live["apim"]), "llmBackendConfig": backends(), "modelAliases": []}
        live["apim"] = {key: value.upper() for key, value in live["apim"].items()}
        self.assertEqual(decisiontools.preserve_live_contract(source, live)["apim"], source["apim"])

    def test_fragment_modules_default_target_to_actual_deployment_scope(self):
        for directory in (
            ROOT / "bicep" / "infra" / "modules" / "apim",
            ROOT / "bicep" / "infra" / "llm-backend-onboarding" / "modules",
        ):
            source = (directory / "llm-policy-fragments.bicep").read_text(encoding="utf-8")
            with self.subTest(module=directory):
                self.assertIn(
                    "param apimTarget object = {\n"
                    "  subscriptionId: subscription().subscriptionId\n"
                    "  resourceGroupName: resourceGroup().name\n"
                    "  name: apimServiceName\n}",
                    source,
                )

    def test_inventory_preserves_independent_backends_even_on_the_same_foundry_host(self):
        source = {"llmBackendConfig": backends()}
        inventory = [
            {"name": "foundry"}, {"name": "native"},
            {"name": "content-safety-backend", "description": "Content Safety Service Backend",
             "url": backends()[0]["endpoint"], "supportedModels": []},
            {"name": "tool-service", "description": "Published Tool Backend"},
        ]
        with patch("decisiontools.utils.print_info") as info:
            required = decisiontools.validate_llm_backend_inventory(source, live_contract(), inventory, [])
        self.assertEqual(required, {"foundry", "native"})
        self.assertIn("content-safety-backend", info.call_args.args[0])
        self.assertIn("tool-service", info.call_args.args[0])
        self.assertEqual(source["llmBackendConfig"], backends())

    def test_inventory_reports_missing_llm_backends_and_model_pool_members(self):
        source = {"llmBackendConfig": backends()}
        for inventory, pools, missing in (
            ([{"name": "omitted-llm", "description": "LLM Backend: azure-decision - omitted-llm"}],
             [], "omitted-llm"),
            ([{"name": "custom-llm", "supportedModels": ["custom-model"]}], [], "custom-llm"),
            ([{"name": "pooled-llm"}], [
                {"name": "managed-model-pool", "description": "Backend pool for model: custom-model",
                 "services": [{"id": "/backends/pooled-llm"}]},
            ], "pooled-llm"),
            ([{"name": "contract-member"}], [
                {"name": "foundry", "services": [{"id": APIM_RESOURCE_ID + "/backends/contract-member"}]},
            ], "contract-member"),
        ):
            with self.subTest(missing=missing), self.assertRaisesRegex(ValueError, missing):
                decisiontools.validate_llm_backend_inventory(source, live_contract(), inventory, pools)
        with self.assertRaisesRegex(ValueError, "native"):
            decisiontools.validate_llm_backend_inventory(
                {"llmBackendConfig": backends()[:1]}, live_contract(), [], [],
            )

    def test_inventory_matches_backend_ids_case_insensitively(self):
        required = decisiontools.validate_llm_backend_inventory(
            {"llmBackendConfig": backends()}, live_contract(),
            [{"name": "FOUNDRY", "description": "LLM Backend: ai-foundry"}], [],
        )
        self.assertEqual(required, {"foundry", "native"})


class DecisionNotebookTests(unittest.TestCase):
    def test_step_six_explains_each_test_and_samples_match_generated_requests(self):
        notebook = json.loads((ROOT / "validation" / NOTEBOOK).read_text(encoding="utf-8"))
        guide = next("".join(cell["source"]) for cell in notebook["cells"]
                     if cell["cell_type"] == "markdown"
                     and "".join(cell["source"]).startswith("## 6."))
        for description in (
            "Binary decision", "Classification", "Grading", "Multiple questions",
            "Gateway route aliases", "Fresh and normal metadata", "Alternate input",
            "Usage and refusal handling", "East US 2",
            "/unified-ai/v1/decisions", "/unified-ai/openai/v1/decisions",
            "/unified-ai/providers/microsoft/v1/systemone",
        ):
            self.assertIn(description, guide)
        examples = [json.loads(value) for value in re.findall(r"```json\n(.*?)\n```", guide, re.DOTALL)]
        self.assertEqual(examples, [
            decisiontools.decision_payload("decisions", "gpt-6-luna"),
            decisiontools.decision_payload("systemone", "Decision-1"),
        ])

    def test_step_six_serialized_requests_always_include_model_even_on_http_400(self):
        import requests

        namespace, _ = self.initialize()
        selected = namespace["selected"]
        namespace["selected"] = {}
        exec(compile(cells(NOTEBOOK)[5], NOTEBOOK + ":request-helper", "exec"), namespace)
        namespace["selected"] = selected
        prepared_requests = []

        def send(prepared, **kwargs):
            payload = json.loads(prepared.body)
            operation = "systemone" if "systemone" in prepared.url else "decisions"
            self.assertEqual(payload["model"], selected[operation])
            self.assertEqual(prepared.headers["Content-Type"], "application/json")
            prepared_requests.append(prepared)
            failed = "api-version=" in prepared.url
            body = {"message": "The requested operation is unsupported."} if failed else response(payload, operation)
            result = requests.Response()
            result.status_code = 400 if failed else 200
            result._content = json.dumps(body).encode("utf-8")
            result.headers.update({
                "Content-Type": "application/json",
                "x-ms-region": "East US 2" if failed else "Sweden Central",
                "UAIG-Model-Id": selected[operation],
                "UAIG-Backend": "native" if operation == "systemone" else "foundry",
                "UAIG-API-Type": operation if operation == "systemone" else
                "decisions-openai-v1" if "/openai/v1/" in prepared.url else "decisions",
                "UAIG-Final-Path": "/providers/microsoft/v1/systemone" if operation == "systemone"
                else "/openai/v1/decisions",
            })
            result.request = prepared
            return result

        try:
            with patch.object(namespace["transport"].session, "send", side_effect=send), \
                    contextlib.redirect_stdout(io.StringIO()):
                exec(compile(cells(NOTEBOOK)[6], NOTEBOOK + ":serialized-step-six", "exec"), namespace)
            self.assertEqual(len(prepared_requests), 8)
            self.assertEqual(sum("api-version=" in request.url for request in prepared_requests), 3)
            failures = [result for result in namespace["run"].results if result.status == "FAIL"]
            self.assertEqual(len(failures), 3)
            for result in failures:
                self.assertIn(result.actual["request_model"], selected.values())
                self.assertIn("unsupported", result.actual["errors"][0])
                self.assertIn("East US 2", result.actual["errors"][0])
                self.assertNotIn("no model identity", str(result.actual))
            self.assertEqual(namespace["provider_success"], {"decisions", "systemone"})
        finally:
            namespace["transport"].close()

    def test_request_helper_blocks_missing_model_except_deliberate_negative_probe(self):
        namespace, _ = self.initialize()
        namespace["selected"] = {}
        exec(compile(cells(NOTEBOOK)[5], NOTEBOOK + ":request-helper", "exec"), namespace)
        with patch.object(namespace["transport"], "request") as request:
            for payload in ({}, {"model": None}, {"model": ""}, {"model": " "}, {"model": 42}):
                with self.subTest(payload=payload), self.assertRaisesRegex(ValueError, "model"):
                    namespace["invoke"]("decisions", payload)
            request.assert_not_called()
            namespace["invoke"]("decisions", {"questions": []}, require_model=False)
            self.assertNotIn("model", request.call_args.kwargs["json"])
        namespace["transport"].close()

    def test_run_all_reloads_a_stale_helper_without_a_kernel_restart(self):
        with patch.object(decisiontools, "live_decision_catalog", side_effect=AssertionError("Stale helper")) as stale:
            namespace = configured(NOTEBOOK)
            self.assertIsNot(namespace["live_decision_catalog"], stale)
            catalog = namespace["live_decision_catalog"](
                live_contract(), [{"name": "foundry"}, {"name": "native"}], {},
            )
            self.assertEqual(catalog.models_for("systemone"), ["custom-microsoft"])

    def initialize(self, configured_backends=None, *, legacy_target=False,
                   additions_file=None, live_backend_config=None, saved_capabilities=None):
        namespace = configured(NOTEBOOK)
        namespace["backend_additions_file"] = additions_file
        data = backends() if configured_backends is None else configured_backends
        context = context_fixture(capabilities={}, backends=data)
        if saved_capabilities is not None:
            context.config["capabilities"] = saved_capabilities
        context.config["location"] = "fixture-location"
        boundary = initialized_apim()
        apim = boundary.return_value
        apim.apim_service_id = APIM_RESOURCE_ID
        metadata = " ".join(path for routes in decisiontools.ROUTES.values() for path in routes)
        fragments = {"request-processor": "is-decision-request",
                     "path-builder": "systemone", "metadata-config": metadata,
                     "set-target-backend-pool": "systemone-pool-names"}
        apim.client.policy_fragment.get.side_effect = lambda *args: SimpleNamespace(value=fragments[args[2]])
        live = live_contract()
        live["backends"] = data if live_backend_config is None else live_backend_config
        apim.get_backends.return_value = ([{"name": item["backendId"]} for item in live["backends"]], [])
        if legacy_target:
            live["apim"] = {}
        result = HTTPResult(200, live, "", {}, b"", 0)
        namespace["APIMClientTool"] = boundary
        with patch.object(validationtools.ValidationContext, "load", return_value=context), \
                patch.object(validationtools.RequestTransport, "request", return_value=result), \
                patch("apimtools.APIMClientTool", boundary):
            exec(compile(cells(NOTEBOOK)[1], NOTEBOOK + ":initialize", "exec"), namespace)
        return namespace, apim

    def test_live_inventory_wins_over_stale_azd_and_local_configuration(self):
        with patch("notebookdefaults.backend_source", side_effect=AssertionError("Must not load onboarding source")):
            namespace, _ = self.initialize(
                backends()[:1], additions_file="nonexistent.json", live_backend_config=backends(),
            )
        self.assertEqual(namespace["selected"], {"decisions": "custom-openai", "systemone": "custom-microsoft"})
        self.assertIsNone(namespace["desired"])
        self.assertEqual(namespace["context"].catalog.backends, backends())

    def test_empty_identity_does_not_force_readonly_backend_changes(self):
        with patch("decisiontools.utils.print_warning"):
            namespace, apim = self.initialize(legacy_target=True)
        self.assertEqual(namespace["selected"], {
            "decisions": "custom-openai", "systemone": "custom-microsoft",
        })
        apim.get_backends.return_value = ([{"name": "foundry"}, {"name": "native"}], [])
        with patch("contracttools.prepare_artifact") as prepare:
            namespace["prepare_artifact"] = prepare
            exec(compile(cells(NOTEBOOK)[2], NOTEBOOK + ":preview", "exec"), namespace)
            prepare.assert_not_called()
        self.assertIsNone(namespace["onboarding_artifact"])

    def test_registered_targets_never_deploy_backend_metadata_repairs(self):
        with patch("decisiontools.utils.print_warning"):
            namespace, apim = self.initialize(legacy_target=True)
        with patch.object(contracttools.ContractArtifact, "deploy") as deploy:
            exec(compile(cells(NOTEBOOK)[2], NOTEBOOK + ":live-preview", "exec"), namespace)
            exec(compile(cells(NOTEBOOK)[3], NOTEBOOK + ":live-no-deploy", "exec"), namespace)
            deploy.assert_not_called()
        self.assertEqual(namespace["live_contract"]["apim"], {})

    def test_actual_notebook_blocks_predeploy_target_change_and_unrepaired_metadata(self):
        with patch("decisiontools.utils.print_warning"):
            namespace, _ = self.initialize(legacy_target=True)
        from unittest.mock import Mock
        artifact = Mock()
        namespace["desired"] = {
            "apim": live_contract()["apim"], "llmBackendConfig": backends(), "modelAliases": [],
        }
        artifact.compile.return_value = {"parametersJson": {"parameters": {
            key: {"value": value} for key, value in namespace["desired"].items()
        }}}
        namespace["onboarding_artifact"] = artifact
        namespace["live_ids"] = {"foundry", "native"}
        wrong = copy.deepcopy(namespace["live_contract"])
        wrong["apim"] = {**live_contract()["apim"], "name": "another-apim"}
        with patch.object(validationtools.RequestTransport, "request",
                          return_value=HTTPResult(200, wrong, "", {}, b"", 0)), \
                patch("decisiontools.utils.print_warning"), \
                self.assertRaisesRegex(ValueError, "different APIM"):
            exec(compile(cells(NOTEBOOK)[3], NOTEBOOK + ":drift", "exec"), namespace)
        artifact.deploy.assert_not_called()
        legacy = HTTPResult(200, namespace["live_contract"], "", {}, b"", 0)
        with patch.object(validationtools.RequestTransport, "request",
                          side_effect=[legacy, legacy]), \
                patch("decisiontools.utils.print_warning"), \
                self.assertRaisesRegex(ValueError, "APIM coordinates"):
            exec(compile(cells(NOTEBOOK)[3], NOTEBOOK + ":unrepaired", "exec"), namespace)

    def test_actual_notebook_selects_both_custom_deployments_and_noops_when_current(self):
        namespace, apim = self.initialize()
        self.assertEqual(namespace["selected"], {
            "decisions": "custom-openai", "systemone": "custom-microsoft",
        })
        apim.get_backends.return_value = ([{"name": "foundry"}, {"name": "native"}], [])
        with patch("contracttools.prepare_artifact") as prepare:
            namespace["prepare_artifact"] = prepare
            exec(compile(cells(NOTEBOOK)[2], NOTEBOOK + ":preview", "exec"), namespace)
            prepare.assert_not_called()
        self.assertIsNone(namespace["onboarding_artifact"])

    def test_actual_notebook_preview_does_not_require_content_safety_in_llm_source(self):
        namespace, apim = self.initialize()
        apim.get_backends.return_value = ([
            {"name": "foundry"}, {"name": "native"},
            {"name": "content-safety-backend", "description": "Content Safety Service Backend",
             "url": backends()[0]["endpoint"], "supportedModels": []},
        ], [])
        with patch("contracttools.prepare_artifact") as prepare:
            namespace["prepare_artifact"] = prepare
            exec(compile(cells(NOTEBOOK)[2], NOTEBOOK + ":mixed-inventory", "exec"), namespace)
            prepare.assert_not_called()
        self.assertEqual(namespace["live_ids"], {"foundry", "native"})

    def test_unrelated_live_registrations_do_not_force_backend_onboarding(self):
        namespace, apim = self.initialize()
        apim.get_backends.return_value = ([
            {"name": "foundry"}, {"name": "native"},
            {"name": "omitted-systemone", "description": "LLM Backend: azure-decision"},
            {"name": "content-safety-backend", "description": "Content Safety Service Backend"},
        ], [])
        with patch("contracttools.prepare_artifact") as prepare:
            namespace["prepare_artifact"] = prepare
            exec(compile(cells(NOTEBOOK)[2], NOTEBOOK + ":independent-registration", "exec"), namespace)
            prepare.assert_not_called()

    def test_actual_notebook_rechecks_inventory_before_deployment(self):
        namespace, apim = self.initialize()
        from unittest.mock import Mock
        artifact = Mock()
        namespace["desired"] = {
            "apim": live_contract()["apim"], "llmBackendConfig": backends(), "modelAliases": [],
        }
        artifact.compile.return_value = {"parametersJson": {"parameters": {
            key: {"value": value} for key, value in namespace["desired"].items()
        }}}
        namespace["onboarding_artifact"] = artifact
        namespace["live_ids"] = {"foundry", "native"}
        apim.get_backends.return_value = ([
            {"name": "foundry"}, {"name": "native"},
            {"name": "new-llm-after-preview", "description": "LLM Backend: ai-foundry"},
        ], [])
        with patch.object(validationtools.RequestTransport, "request",
                          return_value=HTTPResult(200, live_contract(), "", {}, b"", 0)), \
                self.assertRaisesRegex(ValueError, "new-llm-after-preview"):
            exec(compile(cells(NOTEBOOK)[3], NOTEBOOK + ":inventory-drift", "exec"), namespace)
        artifact.deploy.assert_not_called()

    def test_missing_provider_is_explicit_skip_not_an_arbitrary_gpt_request(self):
        data = backends()[:1]
        data[0]["supportedModels"] = [{"name": "gpt-chat-only"}]
        namespace, _ = self.initialize(data)
        self.assertEqual(namespace["selected"], {})
        exec(compile(cells(NOTEBOOK)[2], NOTEBOOK + ":missing-preview", "exec"), namespace)
        exec(compile(cells(NOTEBOOK)[3], NOTEBOOK + ":missing-summary", "exec"), namespace)
        self.assertEqual([r.status for r in namespace["run"].results], ["SKIP", "SKIP"])

    def test_default_target_models_work_without_capability_overrides_or_backend_changes(self):
        deployed = backends()
        deployed[0]["supportedModels"] = [{"name": "gpt-6-luna"}]
        deployed[1]["supportedModels"] = [{"name": "Decision-1"}]
        with patch("notebookdefaults.backend_source", side_effect=AssertionError("Static source must not be used")):
            namespace, _ = self.initialize(
                backends()[:1], live_backend_config=deployed,
                saved_capabilities={"gpt-6-luna": ["chat"], "Decision-1": ["chat"]},
            )
            namespace["source_parameters_file"] = "stale-source.json"
            with patch.object(contracttools.ContractArtifact, "deploy") as deploy, \
                    patch("contracttools.prepare_artifact") as prepare:
                namespace["prepare_artifact"] = prepare
                exec(compile(cells(NOTEBOOK)[2], NOTEBOOK + ":ready-preview", "exec"), namespace)
                exec(compile(cells(NOTEBOOK)[3], NOTEBOOK + ":ready-no-deploy", "exec"), namespace)
                prepare.assert_not_called()
                deploy.assert_not_called()
        self.assertEqual(namespace["selected"], {"decisions": "gpt-6-luna", "systemone": "Decision-1"})

    def test_error_checks_accept_actual_apim_error_envelopes(self):
        namespace, _ = self.initialize()
        namespace["selected"] = {}
        exec(compile(cells(NOTEBOOK)[5], NOTEBOOK + ":error-helpers", "exec"), namespace)
        for body in (
            {"statusCode": 401, "message": "Access denied."},
            {"statusCode": 429, "message": "Rate limit is exceeded."},
            {"statusCode": 403, "message": "Out of call volume quota."},
            {"error": {"code": "invalid_request", "message": "Invalid request."}},
        ):
            with self.subTest(body=body):
                self.assertTrue(namespace["error_body"](body))
        for body in ({}, {"error": 42}, {"message": ""}, None):
            with self.subTest(body=body):
                self.assertFalse(namespace["error_body"](body))

    def test_explicit_onboarding_is_only_used_when_a_provider_is_missing(self):
        namespace, _ = self.initialize(backends()[:1])
        namespace["backend_additions"] = backends()[1:]
        from unittest.mock import Mock
        namespace["backend_source"] = Mock(return_value={
            "apim": live_contract()["apim"], "llmBackendConfig": backends()[:1], "modelAliases": [],
        })
        namespace["prepare_artifact"] = Mock()
        exec(compile(cells(NOTEBOOK)[2], NOTEBOOK + ":explicit-onboarding", "exec"), namespace)
        namespace["backend_source"].assert_called_once()
        self.assertEqual(namespace["desired"]["llmBackendConfig"], backends())
        namespace["prepare_artifact"].assert_called_once()

    def test_dynamic_request_contract_is_the_actual_notebook_generator(self):
        namespace, _ = self.initialize()
        with patch("contracttools.prepare_artifact") as prepare:
            namespace["prepare_artifact"] = prepare
            exec(compile(cells(NOTEBOOK)[4], NOTEBOOK + ":access", "exec"), namespace)
        parameters = prepare.call_args.args[1]
        self.assertEqual(parameters["apiNameMapping"], {"LLM": ["unified-ai"]})
        policy = parameters["services"][0]["policyXml"]
        self.assertIn("rate-limit-by-key", policy)
        self.assertNotIn("llm-token-limit", policy)
        self.assertEqual(parameters["useTargetFoundry"], False)

    def test_run_all_checks_both_providers_limits_and_legacy_without_cloud(self):
        namespace, apim = self.initialize()
        apim.get_backends.return_value = ([{"name": "foundry"}, {"name": "native"}], [])
        apim.get_subscription_key.side_effect = lambda name: "fixture-" + name
        counters = {}

        def deploy(artifact, *args, **kwargs):
            name = artifact.params_file.parent.name
            product = "LLM-Testing-" + name + "-DEV"
            return {"products": {"value": [{"productId": product}]},
                    "subscriptions": {"value": [{"name": name, "productId": product}]}}

        def request(_transport, method, url, **kwargs):
            payload = kwargs.get("json", {})
            path = url.split("/unified-ai", 1)[-1]
            key = kwargs.get("headers", {}).get("api-key")
            status, body, headers = 200, {}, {}
            if "/version/backend-contract" in url:
                body = live_contract()
            elif key in (None, "invalid-validation-key"):
                status = 401
            elif method != "POST":
                status, headers = 405, {"Allow": "POST"}
            elif path.endswith("-extra"):
                status = 403
            elif not payload.get("model"):
                status = 400
            elif payload.get("questions") is None and not path.endswith("chat/completions"):
                status = 400
            elif path.endswith("chat/completions"):
                body = {"choices": [{"message": {"content": "Hello."}}]}
            else:
                operation = "systemone" if path.endswith("systemone") else "decisions"
                expected_model = "custom-microsoft" if operation == "systemone" else "custom-openai"
                if payload["model"] != expected_model:
                    status = 400
                else:
                    counters[key] = counters.get(key, 0) + 1
                    if key == "fixture-rate" and counters[key] > 1:
                        status = 429
                    elif key == "fixture-quota" and counters[key] > 1:
                        status = 403
                    else:
                        body = response(payload, operation)
                        headers = {
                            "UAIG-Model-Id": expected_model,
                            "UAIG-Backend": "native" if operation == "systemone" else "foundry",
                            "UAIG-API-Type": operation if operation == "systemone" else
                            "decisions-openai-v1" if path.startswith("/openai/") else "decisions",
                            "UAIG-Final-Path": path if operation == "systemone" else "/openai/v1/decisions",
                        }
            if status >= 400:
                body = {"error": {"code": "fixture_error"}}
            return HTTPResult(status, body, json.dumps(body), headers, b"", 0)

        directory = ROOT / "validation" / ".runs"
        directory.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=directory) as temporary, \
                patch.object(contracttools.ContractArtifact, "deploy", deploy), \
                patch.object(validationtools.RequestTransport, "request", request), \
                contextlib.redirect_stdout(io.StringIO()):
            namespace["run_dir"] = Path(temporary)
            for index, code in enumerate(cells(NOTEBOOK)[2:], start=2):
                exec(compile(code, f"{NOTEBOOK}:{index}", "exec"), namespace)
            self.assertEqual(namespace["provider_success"], {"decisions", "systemone"})
            self.assertEqual(namespace["summary"]["FAIL"], 0)
            self.assertEqual(namespace["summary"]["BLOCKED"], 0)
            checks = {result.case: result.status for result in namespace["run"].results}
            self.assertEqual(checks["Rate:threshold"], "PASS")
            self.assertEqual(checks["Quota:threshold"], "PASS")
            self.assertEqual(checks["legacy-chat"], "PASS")
            self.assertGreater(namespace["summary"]["PASS"], 20)


if __name__ == "__main__":
    unittest.main()
