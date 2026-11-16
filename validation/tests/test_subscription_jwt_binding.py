"""Source-level regression tests for #184. These do NOT execute policies inside Azure APIM."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INFRA = ROOT / "bicep/infra"
SECURITY = INFRA / "modules/apim/policies/frag-security-handler.xml"
ONBOARD = INFRA / "citadel-access-contracts/modules/apimOnboardService.bicep"
CONTRACTS = INFRA / "citadel-access-contracts/main.bicep"
README = INFRA / "citadel-access-contracts/README.md"
SECONDARY = (
    "modules/apim/policies/ai-search-index-api-policy.xml",
    "modules/apim/policies/ai-search-service-api-policy.xml",
    "modules/apim/policies/doc-intelligence-api-policy.xml",
    "modules/apim/policies/openai-realtime-policy.xml",
    "modules/apim/policies/ai-model-inference-api-policy.xml",
    "modules/apim/policies/translator-api-policy.xml",
    "citadel-publish-contracts/policies/baseline-a2a-policy.xml",
)


class SubscriptionOwnershipSecurityTests(unittest.TestCase):

    def test_authorization_runs_after_jwt_and_before_backend(self):
        policy = SECURITY.read_text(encoding="utf-8")
        self.assertLess(policy.index('output-token-variable-name="validated-jwt"'),
                        policy.index('var bindingsJson ='))
        self.assertLess(policy.index('var requiredRoles ='),
                        policy.index('var bindingsJson ='))
        self.assertLess(policy.index('code="403" reason="Subscription identity mismatch"'),
                        policy.index('<!-- Remove api-key header'))
        self.assertIn('subscription_identity_mismatch', policy)

    def test_binding_checks_exact_subscription_and_exact_validated_identity(self):
        policy = SECURITY.read_text(encoding="utf-8")
        required = (
            'context.Subscription?.Id',
            'jwtSubscriptionBindingsJson',
            'GetValueOrDefault(&quot;tid&quot;',
            'GetValueOrDefault(&quot;oid&quot;',
            'binding[&quot;subscriptionId&quot;]',
            'identity[&quot;tenantId&quot;]',
            'identity[&quot;objectId&quot;]',
            'matching.Length != 1',
            'permitted == null',
            '!permitted.Any',
            'StringComparison.OrdinalIgnoreCase',
            'catch {',
            'context.Subscription == null',
        )
        for expression in required:
            with self.subTest(expression=expression):
                self.assertIn(expression, policy)

    def test_product_policy_supports_independent_subscriptions_and_forces_jwt(self):
        source = ONBOARD.read_text(encoding="utf-8")
        required = (
            'param jwtAuthorizedCallers array = []',
            'param jwtAdditionalSubscriptionBindings array = []',
            'subscriptionId: subscriptionName',
            'concat(ownJwtSubscriptionBinding, jwtAdditionalSubscriptionBindings)',
            "length(union(jwtBindingIds, [])) == length(jwtBindingIds)",
            'base64(string(validatedJwtSubscriptionBindings))',
            'name="jwtSubscriptionBindingsJson"',
            'name="jwtRequired" value="true"',
            "replace(sourcePolicyXml, '</inbound>'",
            "fail('Subscription-bound JWT Product policies",
            'value: securedProductPolicyXml',
            'empty(validatedJwtSubscriptionBindings)',
        )
        for expression in required:
            with self.subTest(expression=expression):
                self.assertIn(expression, source)

    def test_same_grants_for_primary_and_mirrored_gateway(self):
        source = CONTRACTS.read_text(encoding="utf-8")
        for expression in (
            'jwtAuthorizedCallers: s.?jwtAuthorizedCallers ?? []',
            'jwtAuthorizedCallers: item.s.?jwtAuthorizedCallers ?? []',
            'jwtAdditionalSubscriptionBindings: s.?jwtAdditionalSubscriptionBindings ?? []',
            'jwtAdditionalSubscriptionBindings: item.s.?jwtAdditionalSubscriptionBindings ?? []',
            'explicitPrimaryKey: onboard[item.serviceIndex].outputs.subscriptionPrimaryKey',
        ):
            with self.subTest(expression=expression):
                self.assertIn(expression, source)

    def test_jwt_is_checked_before_downstream_identity_for_secondary_apis(self):
        for filename in SECONDARY:
            with self.subTest(filename=filename):
                policy = (INFRA / filename).read_text(encoding="utf-8")
                inbound = policy.split('<inbound>', 1)[1].split('</inbound>', 1)[0]
                self.assertIn('jwtRequired', inbound)
                self.assertIn('fragment-id="security-handler"', inbound)
                if '<authentication-managed-identity' in inbound:
                    self.assertLess(inbound.index('fragment-id="security-handler"'),
                                    inbound.index('<authentication-managed-identity'))

    def test_documented_migration_and_scoping_caveats(self):
        docs = README.read_text(encoding="utf-8")
        for expression in (
            'Issue #184', 'JWT B + Key A', 'JWT B + Key B',
            '403', 'fail closed', 'all-APIs', 'before rollout',
        ):
            with self.subTest(expression=expression):
                self.assertIn(expression.lower(), docs.lower())


if __name__ == "__main__":
    unittest.main()
