"""Offline Entra token and notebook regressions; no live credentials or Azure calls."""

import base64
import copy
import io
import json
import sys
import time
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "shared"))
import jwttools
from validation.tests.test_notebook_experience import cells, configured, context_fixture, initialize, initialized_apim


def token(roles=None, **overrides):
    claims = {
        "ver": "2.0", "aud": "fixture-client", "tid": "fixture-tenant",
        "iss": "https://login.microsoftonline.com/fixture-tenant/v2.0",
        "azp": "fixture-client", "oid": "fixture-sp", "iat": time.time() - 10,
        "nbf": time.time() - 10, "exp": time.time() + 3600,
        "roles": ["Model.Invoke"] if roles is None else roles,
        **overrides,
    }
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")
    return encode({"alg": "RS256", "kid": "fixture-key"}) + "." + encode(claims) + ".signature"


def setup_context():
    context = context_fixture()
    context.config.update(
        entra_client_id="fixture-client", entra_tenant_id="fixture-tenant",
        entra_audience="api://fixture-client", ENTRA_CLIENT_SECRET="fixture-secret",
        ENTRA_VALIDATION_NEGATIVE_CLIENT_ID="negative-client",
        ENTRA_VALIDATION_NEGATIVE_CLIENT_SECRET="negative-secret",
    )
    context.account["user"] = {"type": "user"}
    return context


class JwtToolsTests(unittest.TestCase):
    def test_client_and_resource_application_ids_remain_distinct(self):
        context = setup_context()
        context.config.update(entra_client_id="calling-client", entra_audience="api://gateway-resource")
        settings = jwttools.jwt_configuration(context.config, context.account)
        self.assertEqual(settings["client_id"], "calling-client")
        self.assertEqual(settings["resource_id"], "gateway-resource")
        report = jwttools.validate_jwt(
            token(aud="gateway-resource", azp="calling-client"),
            tenant_id="fixture-tenant", resource_id="gateway-resource",
            client_id="calling-client", required_role="Model.Invoke",
        )
        self.assertEqual(report["claim_checks"], "PASS")

    def validate(self, value, **kwargs):
        return jwttools.validate_jwt(
            value, tenant_id="fixture-tenant", resource_id="fixture-client", **kwargs,
        )

    def test_decodes_and_checks_each_identity_without_signature_claim(self):
        for value, expectations in (
            (token(), {"client_id": "fixture-client", "required_role": "Model.Invoke"}),
            (token(["MCP.Invoke"], azp="negative-client"),
             {"client_id": "negative-client", "forbidden_role": "Model.Invoke"}),
            (token(scp="access_as_user", oid="fixture-user", azp="azure-cli"),
             {"user_id": "fixture-user", "delegated": True, "required_role": "Model.Invoke"}),
        ):
            report = self.validate(value, **expectations)
            self.assertEqual(report["claim_checks"], "PASS")
            self.assertIn("Not performed", report["signature_validation"])
            self.assertNotIn(value, json.dumps(report))

    def test_rejects_wrong_audience_issuer_identity_scope_lifetime_or_roles(self):
        variants = (
            {"aud": "api://fixture-client"}, {"iss": "https://wrong"},
            {"tid": "wrong"}, {"ver": "1.0"}, {"azp": "other-client"},
            {"roles": []}, {"roles": "Model.Invoke"}, {"scp": "access_as_user"},
            {"exp": time.time() - 1}, {"exp": True}, {"exp": float("nan")},
            {"nbf": time.time() + 300}, {"iat": "yesterday"},
        )
        for overrides in variants:
            with self.subTest(overrides=overrides), self.assertRaises(jwttools.ValidationError):
                self.validate(token(**overrides), client_id="fixture-client", required_role="Model.Invoke")
        for kwargs in ({"scp": "wrong", "oid": "fixture-user"},
                       {"scp": "access_as_user", "oid": "another-user"}):
            with self.assertRaises(jwttools.ValidationError):
                self.validate(token(**kwargs), delegated=True, user_id="fixture-user")
        with self.assertRaises(jwttools.ValidationError):
            self.validate(token(), client_id="fixture-client", forbidden_role="Model.Invoke")

    def test_malformed_tokens_fail_without_exposing_bytes(self):
        for value in ("secret", "a.b.", "!.!.signature", "e30.W10.signature"):
            with self.subTest(value=value), self.assertRaises(jwttools.ValidationError) as raised:
                jwttools.decode_jwt(value)
            self.assertNotIn(value, str(raised.exception))

    def test_manual_credentials_and_token_overrides_win_without_mutating_configuration(self):
        context = setup_context()
        original = copy.deepcopy(context.config)
        resolved = jwttools.jwt_configuration(
            context.config, context.account, client_secret="override-secret",
            no_role_token="override-negative-token", user_token="override-user-token",
        )
        self.assertEqual(resolved["client_secret"], "override-secret")
        self.assertEqual(resolved["no_role_token"], "override-negative-token")
        self.assertEqual(resolved["user_token"], "override-user-token")
        self.assertEqual(context.config, original)

    @patch("jwttools.requests.post")
    def test_application_tokens_use_resource_scope_and_fail_without_logging_responses(self, post):
        post.return_value = SimpleNamespace(status_code=200, json=lambda: {"access_token": token()})
        value = jwttools.acquire_application_token("fixture-tenant", "api://fixture-client", "client", "secret")
        self.assertTrue(value)
        self.assertEqual(post.call_args.kwargs["data"]["scope"], "api://fixture-client/.default")
        self.assertEqual(post.call_args.kwargs["data"]["client_secret"], "secret")
        self.assertEqual(post.call_args.kwargs["timeout"], 30)
        post.return_value = SimpleNamespace(status_code=401, text="sensitive response")
        output = io.StringIO()
        with redirect_stdout(output), self.assertRaises(jwttools.ValidationError) as raised:
            jwttools.acquire_application_token("fixture-tenant", "api://fixture-client", "client", "secret")
        self.assertNotIn("sensitive", output.getvalue() + str(raised.exception))

    @patch("jwttools._run_json")
    def test_current_user_uses_cli_scope_without_login_or_identity_fallback(self, run):
        run.return_value = {"accessToken": "fixture-token"}
        self.assertEqual(jwttools.acquire_user_token("tenant", "api://resource"), "fixture-token")
        self.assertEqual(run.call_args.args[0], [
            "az", "account", "get-access-token", "--tenant", "tenant",
            "--scope", "api://resource/access_as_user", "--output", "json",
        ])
        run.side_effect = jwttools.ValidationError("MFA required")
        with self.assertRaisesRegex(jwttools.ValidationError, "renewed sign-in/MFA"):
            jwttools.acquire_user_token("tenant", "api://resource")
        with self.assertRaisesRegex(jwttools.ValidationError, "not an SP"):
            jwttools.signed_in_user({"user": {"type": "servicePrincipal"}})


class AutomaticNotebookTests(unittest.TestCase):
    def discovery_namespace(self):
        namespace = self.namespace()
        boundary = initialized_apim()
        descriptors = {
            "models": {"name": "actual-universal-api", "url": "https://gateway.example/models/"},
            "unified-ai": {"name": "actual-unified-api", "url": "https://gateway.example/unified-ai/"},
        }
        boundary.return_value.discover_api_exact.side_effect = descriptors.__getitem__
        namespace["APIMClientTool"] = boundary
        with redirect_stdout(io.StringIO()):
            exec(cells("citadel-jwt-authentication-tests.ipynb")[2], namespace)
        return namespace, boundary.return_value

    def test_discovers_only_universal_and_unified_v1_without_legacy_openai(self):
        namespace, apim = self.discovery_namespace()
        self.assertEqual([call.args[0] for call in apim.discover_api_exact.call_args_list],
                         ["models", "unified-ai"])
        self.assertEqual(namespace["universal_llm_chat_url"],
                         "https://gateway.example/models/chat/completions?api-version=2024-05-01-preview")
        self.assertEqual(namespace["unified_ai_v1_chat_url"],
                         "https://gateway.example/unified-ai/v1/chat/completions")
        self.assertNotIn("openai_api_version", namespace)

    def test_exactly_two_body_model_endpoints_cover_both_positive_identities(self):
        namespace, _ = self.discovery_namespace()
        source = next(cell for cell in cells("citadel-jwt-authentication-tests.ipynb")
                      if "def auth_case(" in cell)
        with redirect_stdout(io.StringIO()):
            exec(source, namespace)
        self.assertEqual([endpoint["name"] for endpoint in namespace["api_endpoints"]],
                         ["Universal LLM API", "Unified AI API (OpenAI v1)"])
        self.assertEqual([endpoint["url"] for endpoint in namespace["api_endpoints"]], [
            namespace["universal_llm_chat_url"], namespace["unified_ai_v1_chat_url"],
        ])
        self.assertTrue(all(endpoint["payload"]["model"] == namespace["model_name"]
                            for endpoint in namespace["api_endpoints"]))
        namespace.update(positive_tokens={"service-principal": token(),
                                         "current-user": token(scp="access_as_user", oid="fixture-user")},
                         jwt_api_key="jwt-key", role_api_key="role-key",
                         transport=Mock())
        namespace["transport"].request.return_value = SimpleNamespace(
            status_code=200, json_body={"choices": [{"message": {"content": "Hello"}}]},
            error=None, duration=0.01,
        )
        with redirect_stdout(io.StringIO()):
            for cell in cells("citadel-jwt-authentication-tests.ipynb"):
                if 'auth_case(f"01-' in cell or 'auth_case(f"05-' in cell:
                    exec(cell, namespace)
        calls = namespace["transport"].request.call_args_list
        self.assertEqual(len(calls), 8)
        self.assertEqual({call.args[1] for call in calls},
                         {endpoint["url"] for endpoint in namespace["api_endpoints"]})
        self.assertTrue(all(result.status == "PASS" for result in namespace["run"].results))

    def test_both_contracts_grant_only_the_discovered_universal_and_unified_apis(self):
        namespace, _ = self.discovery_namespace()
        namespace.update(
            jwt_contract={"business_unit": "Tests", "use_case_name": "JWT", "environment": "DEV",
                          "apikey_secret": "JWT-KEY", "use_keyvault": False},
            role_contract={"business_unit": "Tests", "use_case_name": "Roles", "environment": "DEV",
                           "apikey_secret": "ROLE-KEY", "use_keyvault": False},
            jwt_product_policy=namespace["access_policy"](["future-model"], 5000, 100000, "Monthly",
                                                        jwt_required=True),
            write_parameters=Mock(return_value=Path("mocked.bicepparam")),
            preview=Mock(return_value="using 'main.bicep'"),
        )
        with redirect_stdout(io.StringIO()):
            for cell in cells("citadel-jwt-authentication-tests.ipynb"):
                if "jwt_parameters = access_parameters(" in cell or "role_parameters = access_parameters(" in cell:
                    exec(cell, namespace)
        for key in ("jwt_parameters", "role_parameters"):
            self.assertEqual(namespace[key]["apiNameMapping"],
                             {"LLM": ["actual-universal-api", "actual-unified-api"]})

    def test_saved_preflight_and_guidance_do_not_require_a_manual_jwt(self):
        notebook_path = Path(__file__).resolve().parents[1] / "citadel-jwt-authentication-tests.ipynb"
        notebook = json.loads(notebook_path.read_text(encoding="utf-8"))
        preflight = cells(notebook_path.name)[1]
        self.assertIn("jwt_settings = jwt_configuration(", preflight)
        self.assertNotIn('"jwt.no_role_token_fixture":', preflight)
        self.assertNotIn("no_role_token_fixture.split", preflight)
        guidance = "\n".join("".join(cell["source"]) for cell in notebook["cells"]
                             if cell["cell_type"] == "markdown")
        self.assertNotIn("Supply it before Run All", guidance)
        self.assertNotIn("containing an actual unexpired no-role JWT", guidance)
        self.assertNotIn("acquire the `access_as_user` token separately", guidance)

    def namespace(self):
        with patch.dict("os.environ", {
            "VALIDATION_ENTRA_CLIENT_SECRET": "", "VALIDATION_JWT_NO_ROLE_TOKEN": "",
            "VALIDATION_JWT_DEVICE_TOKEN": "",
        }):
            namespace = configured("citadel-jwt-authentication-tests.ipynb")
        initialize("citadel-jwt-authentication-tests.ipynb", namespace, setup_context())
        return namespace

    def test_run_all_acquires_three_tokens_and_checks_all_claims_without_manual_inputs(self):
        namespace = self.namespace()
        application = token()
        negative = token(["MCP.Invoke"], azp="negative-client")
        user = token(scp="access_as_user", oid="fixture-user", azp="azure-cli")
        responses = [SimpleNamespace(status_code=200, json=lambda value=value: {"access_token": value})
                     for value in (application, negative)]
        output = io.StringIO()
        with patch("jwttools.requests.post", side_effect=responses) as post, \
                patch("jwttools._run_json", side_effect=[{"id": "fixture-user"}, {"accessToken": user}]) as cli, \
                redirect_stdout(output):
            for index in (3, 4, 5, 6):
                exec(cells("citadel-jwt-authentication-tests.ipynb")[index], namespace)
        self.assertEqual(post.call_count, 2)
        self.assertEqual(cli.call_count, 2)
        self.assertEqual(set(namespace["positive_tokens"]), {"service-principal", "current-user"})
        self.assertEqual(len(namespace["token_inspections"]), 3)
        self.assertEqual(namespace["no_role_token_fixture"], negative)
        for sensitive in (application, negative, user, "fixture-secret", "negative-secret"):
            self.assertNotIn(sensitive, output.getvalue())

    def test_optional_fixtures_skip_only_their_corresponding_acquisition(self):
        namespace = self.namespace()
        user = token(scp="access_as_user", oid="fixture-user")
        negative = token(["MCP.Invoke"], azp="override-client")
        namespace["jwt_settings"]["no_role_token"] = negative
        namespace["device_token_fixture"] = user
        with patch("jwttools.requests.post", return_value=SimpleNamespace(
                status_code=200, json=lambda: {"access_token": token()})) as post, \
                patch("jwttools._run_json", return_value={"id": "fixture-user"}) as cli, \
                redirect_stdout(io.StringIO()):
            for index in (3, 4, 5):
                exec(cells("citadel-jwt-authentication-tests.ipynb")[index], namespace)
        self.assertEqual(post.call_count, 1)
        self.assertEqual(cli.call_count, 1)
        self.assertEqual(namespace["device_flow_token"], user)

    def test_positive_http_tests_cover_both_identities(self):
        namespace = self.namespace()
        namespace.update(positive_tokens={"service-principal": "app-token", "current-user": "user-token"},
                         jwt_api_key="jwt-key", role_api_key="role-key", auth_case=Mock())
        for cell in cells("citadel-jwt-authentication-tests.ipynb"):
            if 'auth_case(f"01-' in cell or 'auth_case(f"05-' in cell:
                with redirect_stdout(io.StringIO()):
                    exec(cell, namespace)
        self.assertEqual(namespace["auth_case"].call_count, 4)
        self.assertEqual({call.args[2] for call in namespace["auth_case"].call_args_list},
                         {"app-token", "user-token"})


if __name__ == "__main__":
    unittest.main()
