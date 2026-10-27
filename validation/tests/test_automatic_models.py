import copy
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "shared"))
import utils
from validationtools import (
    ModelCatalog, ValidationBlocked, ValidationContext, ValidationError, infer_model_operations,
)


def backend(*names):
    return [{"backendId": "primary", "backendType": "ai-foundry",
             "endpoint": "https://fixture.services.ai.azure.com",
             "supportedModels": [{"name": name} for name in names]}]


class AutomaticOperationTests(unittest.TestCase):
    def test_name_rules_are_case_insensitive_and_specific_rules_take_precedence(self):
        for name, expected in (
            ("GPT-example", ["chat", "responses"]),
            ("gPt-mini-example", ["chat", "responses"]),
            ("GPT-IMAGE-example", ["image-generation", "image-edit"]),
            ("FLUX-example", ["image-generation", "image-edit"]),
            ("some-image-text-model", ["image-generation", "image-edit"]),
            ("TEXT-model", ["embeddings"]),
            ("EMBEDDING-model", ["embeddings"]),
            ("gpt-text-example", ["embeddings"]),
            ("provider-chat-model", ["chat"]),
        ):
            with self.subTest(model=name):
                self.assertEqual(infer_model_operations(name), expected)
                self.assertEqual(ModelCatalog(backend(name)).operations(name), expected)
        for name in ("", " ", None, 42):
            with self.subTest(invalid=name), self.assertRaises(ValidationError):
                infer_model_operations(name)

    def test_explicit_operations_replace_inference_completely(self):
        catalog = ModelCatalog(backend("gpt-one", "plain-model", "gpt-disabled"),
                               {"gpt-one": ["embeddings"], "gpt-disabled": []})
        self.assertEqual(catalog.operations("gpt-one"), ["embeddings"])
        self.assertEqual(catalog.operations("plain-model"), ["chat"])
        self.assertEqual(catalog.operations("gpt-disabled"), [])
        self.assertTrue(catalog.is_skipped("gpt-disabled"))
        self.assertEqual(catalog.models_for("chat"), ["plain-model"])
        sources = {entry.name: entry.operations_source for entry in catalog.entries}
        self.assertEqual(sources["gpt-one"], "override")
        self.assertEqual(sources["plain-model"], "inferred")
        utils.require_capabilities(catalog)

    def test_explicit_metadata_precedes_inference_but_override_precedes_metadata(self):
        data = backend("gpt-one")
        data[0]["supportedModels"][0]["operations"] = ["embeddings"]
        self.assertEqual(ModelCatalog(data).operations("gpt-one"), ["embeddings"])
        self.assertEqual(ModelCatalog(data, {"gpt-one": ["chat"]}).operations("gpt-one"), ["chat"])

    def test_null_operation_metadata_does_not_disable_automatic_defaults(self):
        data = backend("gpt-one")
        data[0]["supportedModels"][0].update(operations=None, capabilities={"operations": None})
        self.assertEqual(ModelCatalog(data).operations("gpt-one"), ["chat", "responses"])

    def test_streaming_assumption_only_applies_to_inferred_chat(self):
        self.assertEqual(ModelCatalog(backend("gpt-one", "text-one")).models_for("streaming"), ["gpt-one"])
        self.assertEqual(ModelCatalog(backend("gpt-one"), {"gpt-one": ["chat"]}).models_for("streaming"), [])
        self.assertEqual(ModelCatalog(backend("gpt-one"), {"gpt-one": ["chat", "streaming"]})
                         .select("streaming"), "gpt-one")

    def test_strict_mapping_mode_remains_available(self):
        catalog = ModelCatalog(backend("gpt-one", "other"), {"gpt-one": ["chat"]}, infer_operations=False)
        self.assertEqual(catalog.operations("other"), [])
        self.assertEqual(catalog.models_for("responses"), [])
        with self.assertRaisesRegex(ValueError, "VALIDATION_MODEL_CAPABILITIES"):
            utils.require_capabilities(catalog)

    def test_unknown_models_are_not_invented_from_discovery(self):
        catalog = ModelCatalog(backend("gpt-one"))
        self.assertEqual(catalog.operations("undeployed-gpt"), [])
        with self.assertRaises(ValidationBlocked):
            catalog.select("chat", override="undeployed-gpt")

    def test_skip_keywords_filter_every_selection_without_changing_deployment(self):
        data = backend("GPT-MINI-blue", "my-LEGACY-chat", "gpt-active", "flux-image")
        original = copy.deepcopy(data)
        catalog = ModelCatalog(data, skipped_models=[" Mini ", "legacy", "MINI"])
        self.assertEqual(catalog.models_for("chat"), ["gpt-active"])
        self.assertEqual(catalog.models_for("responses"), ["gpt-active"])
        self.assertEqual(catalog.models_for("streaming"), ["gpt-active"])
        self.assertTrue(catalog.is_skipped("GPT-MINI-blue"))
        self.assertEqual(catalog.skipped_models, ("mini", "legacy"))
        with self.assertRaises(ValidationBlocked):
            catalog.select("chat", override="GPT-MINI-blue")
        with self.assertRaises(ValidationBlocked):
            catalog.alias_members(["gpt-active", "my-LEGACY-chat"], "chat")
        self.assertEqual(data, original)
        self.assertEqual(catalog.backends, original)
        self.assertEqual(len(catalog.entries), 4)
        self.assertTrue(catalog.report()[0]["skipped"])

    def test_empty_or_invalid_skip_keywords_fail_explicitly(self):
        for keywords in ("mini", [""], [" "], [None], [3]):
            with self.subTest(keywords=keywords), self.assertRaises(ValidationError):
                ModelCatalog(backend("gpt-one"), skipped_models=keywords)
        with self.assertRaisesRegex(ValueError, "No models selected"):
            utils.require_capabilities(ModelCatalog(backend("gpt-mini"), skipped_models=["GPT"]))

    def test_get_404_is_optional_for_all_models_and_other_limits_remain_mini_specific(self):
        catalog = ModelCatalog(backend("gpt-MINI-blue", "gpt-full", "other-mini"))
        for name in ("gpt-MINI-blue", "gpt-full", "other-mini", "arbitrary-model"):
            self.assertTrue(catalog.optional_response_retrieval(name, 404))
        for status in (405, 501):
            self.assertTrue(catalog.optional_response_retrieval("gpt-MINI-blue", status))
            self.assertFalse(catalog.optional_response_retrieval("gpt-full", status))
            self.assertFalse(catalog.optional_response_retrieval("other-mini", status))
        for status in (200, 401, 403, 429, 500, 503):
            self.assertFalse(catalog.optional_response_retrieval("gpt-MINI-blue", status))
        self.assertTrue(catalog.optional_response_retrieval(
            "gpt-MINI-blue", 400, {"error": {"code": "OperationNotSupported"}}))
        self.assertFalse(catalog.optional_response_retrieval(
            "gpt-MINI-blue", 400, {"error": {"code": "invalid_parameter"}}))
        strict = ModelCatalog(backend("gpt-mini"), {"gpt-mini": ["chat", "responses"]})
        self.assertTrue(strict.optional_response_retrieval("gpt-mini", 404))
        for status in (400, 401, 403, 405, 429, 500, 501, 503):
            self.assertFalse(strict.optional_response_retrieval("gpt-mini", status))


class AzdAutomaticConfigurationTests(unittest.TestCase):
    def snapshot(self):
        return {
            "AZURE_RESOURCE_GROUP": "fixture-rg", "AZURE_LOCATION": "fixture-location",
            "AZURE_SUBSCRIPTION_ID": "fixture-sub", "AZURE_TENANT_ID": "fixture-tenant",
            "AZURE_ENV_NAME": "fixture-env", "APIM_NAME": "fixture-apim",
            "LLM_BACKEND_CONFIG": json.dumps(backend("gpt-one", "text-one", "gpt-mini")),
        }

    def account(self):
        return {"id": "fixture-sub", "tenantId": "fixture-tenant", "name": "Fixture Subscription"}

    def test_standard_azd_outputs_do_not_require_capability_configuration(self):
        with patch("validationtools._run_json", side_effect=[self.snapshot(), self.account()]):
            context = ValidationContext.load()
        utils.require_capabilities(context.catalog)
        self.assertEqual(context.catalog.operations("gpt-one"), ["chat", "responses"])
        self.assertEqual(context.config["tenant_id"], "fixture-tenant")
        self.assertEqual(context.config["model_aliases"], [])

    def test_environment_mapping_and_skip_values_are_loaded_with_explicit_precedence(self):
        snapshot = self.snapshot()
        snapshot["VALIDATION_MODEL_CAPABILITIES"] = json.dumps({"gpt-one": ["embeddings"]})
        snapshot["VALIDATION_SKIPPED_MODELS"] = '["MINI"]'
        snapshot["MODEL_ALIASES"] = '[{"name":"chat", "models":["gpt-one"]}]'
        with patch("validationtools._run_json", side_effect=[snapshot, self.account()]):
            context = ValidationContext.load()
        self.assertEqual(context.catalog.operations("gpt-one"), ["embeddings"])
        self.assertTrue(context.catalog.is_skipped("gpt-mini"))
        self.assertEqual(context.config["model_aliases"][0]["name"], "chat")
        with patch("validationtools._run_json", side_effect=[snapshot, self.account()]):
            context = ValidationContext.load(operation_overrides={"gpt-one": ["chat"]}, skipped_models=[])
        self.assertEqual(context.catalog.operations("gpt-one"), ["chat"])
        self.assertFalse(context.catalog.is_skipped("gpt-mini"))
        with patch("validationtools._run_json", side_effect=[snapshot, self.account()]):
            automatic = ValidationContext.load(operation_overrides={})
        self.assertEqual(automatic.config["capabilities"], {})
        self.assertEqual(automatic.catalog.operations("gpt-one"), ["chat", "responses"])


if __name__ == "__main__":
    unittest.main()
