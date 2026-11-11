"""Execute the shipped APIM expressions, not a parallel routing implementation."""

import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PRIMARY = ROOT / "bicep" / "infra" / "modules" / "apim" / "policies"
ONBOARDING = ROOT / "bicep" / "infra" / "llm-backend-onboarding" / "modules" / "policies"


def expressions(source, name):
    return re.findall(
        rf'<set-variable name="{re.escape(name)}" value="@\{{(.*?)\}}"\s*/>',
        source, re.DOTALL,
    )


class DecisionRoutingTests(unittest.TestCase):
    def test_mirrored_fragments_are_identical(self):
        for name in ("frag-metadata-config.xml", "frag-set-target-backend-pool.xml"):
            self.assertEqual((PRIMARY / name).read_bytes(), (ONBOARDING / name).read_bytes())

    def test_decision_branch_preserves_body_and_cleans_only_api_version(self):
        source = (PRIMARY / "frag-path-builder.xml").read_text(encoding="utf-8")
        branch = source[source.index('<when condition="@(context.Variables.GetValueOrDefault<bool>("is-decision-request"'):
                        source.index("<!-- Gemini OpenAI API")]
        self.assertNotIn("<set-body", branch)
        self.assertIn('<set-query-parameter name="api-version" exists-action="delete"', branch)
        self.assertEqual(branch.count("<set-query-parameter"), 1)
        self.assertIn('copy-unmatched-params="true"', source)
        processor = (PRIMARY / "frag-request-processor.xml").read_text(encoding="utf-8")
        self.assertLess(processor.index('name="is-decision-request"'),
                        processor.index("<!-- Parse request body"))
        self.assertIn('<set-status code="405"', processor)
        self.assertIn('<set-header name="Allow"', processor)
        self.assertIn('!path.Equals(basePath, StringComparison.OrdinalIgnoreCase)', processor)

    def test_unsupported_metrics_are_gated_without_changing_shared_token_policy(self):
        source = (PRIMARY / "unified-ai-api-policy.xml").read_text(encoding="utf-8")
        self.assertRegex(source, r'(?s)is-decision-request.*?<otherwise>\s*'
                         r'<include-fragment fragment-id="set-llm-usage"')
        self.assertIn("<llm-token-limit", (ROOT / "bicep" / "infra" /
                      "citadel-access-contracts" / "policies" /
                      "default-ai-product-policy.xml").read_text(encoding="utf-8"))

    def test_actual_policy_expressions(self):
        powershell = shutil.which("pwsh")
        if not powershell:
            self.skipTest("PowerShell 7 with its bundled Newtonsoft.Json is required")
        processor = (PRIMARY / "frag-request-processor.xml").read_text(encoding="utf-8")
        selector = (PRIMARY / "frag-set-target-backend-pool.xml").read_text(encoding="utf-8")
        builder = (PRIMARY / "frag-path-builder.xml").read_text(encoding="utf-8")
        metadata = (PRIMARY / "frag-metadata-config.xml").read_text(encoding="utf-8")
        raw = re.search(r'return @"(.*?)";', metadata, re.DOTALL).group(1)
        methods = {
            "Detect": ("string", expressions(processor, "api-type")[0]),
            "IsDecision": ("bool", expressions(processor, "is-decision-request")[0]),
            "NativeNames": ("JArray", expressions(selector, "systemone-pool-names")[0]),
            "Filter": ("JArray", expressions(selector, "backendPools")[0]),
            "Alias": ("JObject", expressions(selector, "alias-resolution")[0]),
            "Select": ("string", expressions(selector, "targetBackendPool")[0]),
            "Guard": ("string", expressions(selector, "targetBackendPool")[1]),
            "Build": ("string", expressions(builder, "finalPath")[0]),
            "RejectPath": ("bool", re.search(
                r'<when condition="@\{(\s*var path =.*?return !path\.Equals.*?)\}">',
                processor, re.DOTALL,
            ).group(1)),
            "RejectMethod": ("bool", 'return ' + re.search(
                r'<when condition="@\((context\.Request\.Method != "POST")\)">',
                processor,
            ).group(1) + ';'),
        }
        source = r"""
using System;
using System.Linq;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;
public class Variables : Dictionary<string, object> {
    public T GetValueOrDefault<T>(string key, T fallback = default(T)) {
        return ContainsKey(key) ? (T)this[key] : fallback;
    }
}
public class Request { public string Method = "POST"; }
public class Context {
    public Variables Variables = new Variables();
    public Request Request = new Request();
}
public static class DecisionPolicyTests {
    // METHODS
    static int checks = 0;
    static void Check(bool value, string message) {
        checks++; if (!value) throw new Exception(message);
    }
    static JObject Metadata() { return JObject.Parse(@"METADATA".Replace('\'', '"')); }
    static Context Setup(string path) {
        var c = new Context();
        c.Variables["config-api-types"] = Metadata()["api-types"];
        c.Variables["config-backend-path-templates"] = Metadata()["backend-path-templates"];
        c.Variables["routing-processed-path"] = path;
        var api = Detect(c); c.Variables["api-type"] = api;
        c.Variables["api-base-path"] = (string)Metadata()["api-types"][api]["base-path"];
        c.Variables["is-decision-request"] = IsDecision(c);
        c.Variables["compatiblePoolTypes"] =
            (string)Metadata()["api-types"][api]["compatible-pool-types"] ?? "";
        c.Variables["requestedModel"] = "shared";
        c.Variables["backendPools"] = JArray.Parse(@"[
          {'poolName':'native','poolType':'azure-decision','supportedModels':['shared']},
          {'poolName':'foundry','poolType':'ai-foundry','supportedModels':['shared']},
          {'poolName':'alias:mix','poolType':'alias','isAlias':true,'aliasName':'mix',
           'members':[{'model':'shared','pools':[
             {'poolName':'native','poolType':'azure-decision'},
             {'poolName':'foundry','poolType':'ai-foundry'}]},
             {'model':'nativeonly','pools':[{'poolName':'native','poolType':'azure-decision'}]}]}]");
        c.Variables["systemone-pool-names"] = NativeNames(c);
        c.Variables["backendPools"] = Filter(c);
        return c;
    }
    public static void Run() {
        foreach (var route in new[] {
            "/v1/decisions", "/openai/v1/decisions", "/providers/microsoft/v1/systemone"
        }) {
            foreach (var suffix in new[] { "", "/" }) {
                var c = Setup(route + suffix);
                var native = route.Contains("systemone");
                Check((bool)c.Variables["is-decision-request"], "Detection: " + route);
                Check(!RejectPath(c), "Exact path rejected");
                Check(!RejectMethod(c), "POST rejected");
                c.Request.Method = "GET";
                Check(RejectMethod(c), "GET accepted as non-LLM request");
                c.Variables["routing-processed-path"] = route + "-extra";
                Check(RejectPath(c), "Prefix collision accepted");
                c.Variables["routing-processed-path"] = route + "/child";
                Check(RejectPath(c), "Descendant path accepted");
                var selected = Select(c);
                Check(selected == (native ? "native" : "foundry"), "Pool: " + route);
                c.Variables["targetBackendPool"] = selected;
                Check(Guard(c) == selected, "Valid selection rejected");
                c.Variables["targetPoolType"] = native ? "azure-decision" : "ai-foundry";
                Check(Build(c) == (native ? route : "/openai/v1/decisions"), "Final path");
                c.Variables["requestedModel"] = "mix";
                var alias = Alias(c);
                Check((string)alias["picked"]["poolName"] == selected, "Alias isolation");
                var fallback = (JArray)alias["fallback"];
                Check(fallback.Count == (native ? 1 : 0), "Incompatible retry member");
                Check(fallback.OfType<JObject>().All(p =>
                    (string)p["poolType"] == (native ? "azure-decision" : "ai-foundry")), "Retry pool type");
            }
        }
        foreach (var route in new[] {"/openai/v1/chat/completions", "/openai/responses",
                                     "/v1/images/generations", "/models/chat/completions"}) {
            var c = Setup(route);
            Check(!(bool)c.Variables["is-decision-request"], "Legacy detection changed");
            Check(Select(c) == "foundry", "Native pool leaked into legacy route");
            c.Variables["requestedModel"] = "mix";
            Check((string)Alias(c)["picked"]["poolName"] == "foundry", "Legacy alias leak");
            c.Variables["targetBackendPool"] = "native";
            Check(Guard(c) == "ERROR_MODEL_NOT_SUPPORTED", "Legacy default/override leak");
        }
        foreach (var route in new[] {"/v1/decisions", "/providers/microsoft/v1/systemone"}) {
            var c = Setup(route);
            c.Variables["targetBackendPool"] = route.Contains("systemone") ? "foundry" : "native";
            Check(Guard(c) == "ERROR_MODEL_NOT_SUPPORTED", "Incompatible default accepted");
            c.Variables["requestedModel"] = "missing";
            Check(Select(c) == "ERROR_MODEL_NOT_SUPPORTED", "Unknown model fallback");
            c.Variables["targetPoolType"] = "azure-mai";
            Check(Build(c) == "", "Unsupported backend got a path");
        }
        Console.WriteLine(checks + " actual policy assertions passed");
    }
}
"""
        source = source.replace("// METHODS", "\n".join(
            f"static {kind} {name}(Context context) {{ {body} }}"
            for name, (kind, body) in methods.items()
        )).replace("METADATA", raw.replace('"', '""'))
        script = (
            "$ErrorActionPreference='Stop'\n"
            "$refs = @((Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll').FullName)"
            " + @([Newtonsoft.Json.Linq.JObject].Assembly.Location)\n"
            "Add-Type -ReferencedAssemblies $refs -CompilerOptions '/nowarn:1701' "
            "-TypeDefinition @'\n" + source + "\n'@\n[DecisionPolicyTests]::Run()"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "decision-policy-tests.ps1"
            path.write_text(script, encoding="utf-8")
            result = subprocess.run(
                [powershell, "-NoProfile", "-File", str(path)],
                capture_output=True, text=True, encoding="utf-8", timeout=90,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("actual policy assertions passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
