"""Source regression checks for the opt-in alert profile; no Azure resources."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "bicep/infra/app-insights-alert"


def rules(text):
    # Compare complete legacy definitions, not merely names.
    return re.findall(r"  \{\n    name: '(?:throttling|quota-exceeded|backend-failure)'\n.*?\n  \}", text, re.S)


class AlertProfileTests(unittest.TestCase):
    def setUp(self):
        self.main = (ROOT / "main.bicep").read_text()
        self.default = (ROOT / "main.bicepparam").read_text()
        self.enhanced = (ROOT / "enhanced.bicepparam").read_text()

    def test_legacy_defaults(self):
        self.assertEqual(len(rules(self.main)), 3)
        self.assertEqual(rules(self.main), rules(self.default))
        self.assertEqual(rules(self.default), rules(self.enhanced))
        self.assertNotIn("logQueryOverride:", self.default)
        self.assertNotIn("nativeMetric:", self.default)
        self.assertIn("param alertMode string = 'logQuery'", self.main)

    def test_unique_rule_names(self):
        names = re.findall(r"^    name: '([^']+)'$", self.enhanced, re.M)
        self.assertEqual(len(names), len(set(names)))
        self.assertIn("usage-telemetry-failure", names)
        self.assertIn("guardrail-evaluation-failure", names)
        self.assertNotIn("jailbreak-detected", names)

    def test_legacy_resource_names_and_action_group(self):
        self.assertEqual(self.main.count("name: '${namePrefix}-${alert.name}-alert'"), 2)
        self.assertEqual(self.main.count("actionGroupId: actionGroup.outputs.id"), 2)
        self.assertIn("name: '${namePrefix}-alerts-ag'", self.main)
        self.assertIn("output alertRuleNames array", self.main)

    def test_platform_override_validation(self):
        for file in ("log-query-alert.bicep", "metric-alert.bicep"):
            module = (ROOT / "modules" / file).read_text()
            self.assertRegex(module, r"@allowed\(\[\s*''\s*\]\)\s*param platformScopeValidation string = ''")
        self.assertIn("Conflicting alert overrides", self.main)
        self.assertIn("Empty query override", self.main)
        self.assertIn("skipMetricValidation: !contains(alert, 'nativeMetric')", self.main)

    def test_absence_query_and_security_thresholds(self):
        self.assertEqual(self.enhanced.count("expected >= 10 and observed == 0"), 2)
        self.assertEqual(self.enhanced.count("print AggregatedValue = iff"), 2)
        for name in ("auth-failure", "content-safety"):
            self.assertRegex(self.enhanced, rf"name: '{name}'\s+alertType: '{name}'\s+severity: 2\s+operator: 'GreaterThan'\s+threshold: 10")
        self.assertIn('LastErrorSource contains "content-safety"', self.enhanced)
        self.assertIn("ResponseCode between (500 .. 599)", self.enhanced)


if __name__ == "__main__":
    unittest.main()
