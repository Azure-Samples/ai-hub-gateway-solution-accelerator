"""Offline regressions for Foundry v1 routing with dated client API versions."""

import base64
import re
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
POLICIES = (
    ROOT / "bicep" / "infra" / "modules" / "apim" / "policies"
    / "frag-set-backend-authorization.xml",
    ROOT / "bicep" / "infra" / "llm-backend-onboarding" / "modules" / "policies"
    / "frag-set-backend-authorization.xml",
)


def foundry_branch(source):
    start = source.index('== "ai-foundry")">')
    end = source.index('== "gemini-openai")">', start)
    return source[start:end].rsplit("<when", 1)[0]


class FoundryApiVersionTests(unittest.TestCase):
    def test_deployment_copies_stay_identical(self):
        self.assertEqual(
            POLICIES[0].read_text(encoding="utf-8"),
            POLICIES[1].read_text(encoding="utf-8"),
        )

    def test_v1_query_cleanup_precedes_rewrite_and_preserves_other_inputs(self):
        for path in POLICIES:
            with self.subTest(policy=path):
                branch = foundry_branch(path.read_text(encoding="utf-8"))
                cleanup = re.search(
                    r'<choose>\s*<when condition="@\((.*?)\)">\s*'
                    r'(?:<!--.*?-->\s*)?'
                    r'<set-query-parameter name="api-version" exists-action="delete"\s*/>'
                    r'\s*</when>\s*</choose>',
                    branch, re.DOTALL,
                )
                self.assertIsNotNone(cleanup, "Foundry v1 must remove dated api-version")
                rewrite = branch.index("<rewrite-uri template=")
                self.assertLess(cleanup.end(), rewrite)
                self.assertIn('copy-unmatched-params="true"', branch[rewrite:])
                self.assertNotIn("<set-body", branch)
                self.assertEqual(branch.count("<set-query-parameter"), 1)

    def test_actual_csharp_routing_and_version_condition(self):
        branch = foundry_branch(POLICIES[0].read_text(encoding="utf-8"))
        rewrite = re.search(
            r'<set-variable name="rewriteTemplate" value="@\{(.*?)\}"\s*/>',
            branch, re.DOTALL,
        )
        condition = re.search(
            r'<when condition="@\((.*?)\)">\s*'
            r'(?:<!--.*?-->\s*)?'
            r'<set-query-parameter name="api-version" exists-action="delete"',
            branch, re.DOTALL,
        )
        self.assertIsNotNone(rewrite)
        self.assertIsNotNone(condition, "Missing v1-specific query cleanup")
        powershell = shutil.which("powershell") or shutil.which("pwsh")
        if not powershell:
            self.skipTest("PowerShell is required to execute the APIM C# expressions")

        harness = r"""
using System;
using System.Collections.Generic;

public class GatewayVariables : Dictionary<string, object>
{
    public T GetValueOrDefault<T>(string key, T fallback = default(T))
    {
        return ContainsKey(key) ? (T)this[key] : fallback;
    }
}
public class GatewayUrl { public string Path; }
public class GatewayRequest { public GatewayUrl OriginalUrl; public GatewayUrl Url; }
public class GatewayApi { public string Path; }
public class GatewayContext
{
    public GatewayVariables Variables = new GatewayVariables();
    public GatewayRequest Request;
    public GatewayApi Api;
}
public static class FoundryRoutingRegression
{
    static string Rewrite(string apiPrefix, string originalPath, string currentPath)
    {
        var context = new GatewayContext {
            Api = new GatewayApi { Path = apiPrefix },
            Request = new GatewayRequest {
                OriginalUrl = new GatewayUrl { Path = originalPath },
                Url = new GatewayUrl { Path = currentPath }
            }
        };
        // REWRITE_EXPRESSION
    }
    static bool RemovesApiVersion(string template)
    {
        var context = new GatewayContext();
        context.Variables["rewriteTemplate"] = template;
        return // VERSION_EXPRESSION
        ;
    }
    static void Check(bool passed, string message)
    {
        if (!passed) { throw new Exception(message); }
    }
    public static void Run()
    {
        int cases = 0;
        foreach (var operation in new[] {
            "chat/completions", "embeddings", "responses",
            "responses/resp_test", "responses/resp_test/input_items"
        })
        {
            var expected = "openai/v1/" + operation;
            foreach (var currentPath in new[] {
                "/models/" + operation, "/" + expected
            })
            {
                var actual = Rewrite("models", "/models/" + operation, currentPath);
                Check(actual == expected, "Incorrect or stacked backend path: " + actual);
                Check(RemovesApiVersion(actual), "Dated api-version would reach " + actual);
                cases++;
            }
        }
        foreach (var template in new[] {
            "/openai/v1/chat/completions", "OPENAI/V1/responses"
        })
        {
            Check(RemovesApiVersion(template), "v1 path was not recognized");
            cases++;
        }
        foreach (var template in new[] {
            "models/chat/completions", "openai/deployments/model/embeddings",
            "openai/v10/chat/completions", ""
        })
        {
            Check(!RemovesApiVersion(template), "Legacy API version would be removed");
            cases++;
        }
        Console.WriteLine(cases + " routing cases passed");
    }
}
"""
        harness = harness.replace("// REWRITE_EXPRESSION", rewrite.group(1))
        harness = harness.replace("// VERSION_EXPRESSION", condition.group(1))
        script = (
            "$ErrorActionPreference = 'Stop'\n"
            "Add-Type -TypeDefinition @'\n" + harness + "\n'@\n"
            "[FoundryRoutingRegression]::Run()\n"
        )
        result = subprocess.run(
            [powershell, "-NoProfile", "-NonInteractive", "-EncodedCommand",
             base64.b64encode(script.encode("utf-16-le")).decode("ascii")],
            capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("16 routing cases passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
