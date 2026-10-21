"""Small consumer-side mechanics shared by the validation notebooks.

Feature configuration, SDK calls, request payloads, and assertions stay in cells.
None of these functions performs work at import time.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from copy import deepcopy
from pathlib import Path
from typing import Any
import time
if __package__:
    from . import utils
    from .contracttools import prepare_artifact
else:
    import utils
    from contracttools import prepare_artifact


def cli_json(*arguments: str) -> Any:
    """Run an explicit Azure CLI query without echoing credentials or output."""
    command = ["az", *arguments, "--output", "json", "--only-show-errors"]
    utils.format_command(command, title="Azure query", diagnostic=True)
    started = time.perf_counter()
    executable = shutil.which("az")
    if not executable:
        utils.format_result("Azure CLI is unavailable", status="ERROR")
        raise RuntimeError("Azure CLI is required.")
    command[0] = executable
    executable_path = Path(executable)
    if executable_path.suffix.lower() in (".cmd", ".bat"):
        candidates = (executable_path.parent.parent / "python.exe", executable_path.parent / "python.exe")
        interpreter = next((candidate for candidate in candidates if candidate.is_file()), None)
        if interpreter is None:
            raise RuntimeError("Azure CLI needs a native interpreter; refusing shell interpolation.")
        command = [str(interpreter), "-IB", "-X", "utf8", "-m", "azure.cli", *command[1:]]
    environment = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUTF8="1")
    try:
        result = subprocess.run(
            command, capture_output=True, text=True, encoding="utf-8", check=False,
            env=environment, timeout=120, shell=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        utils.format_result("Azure query could not execute", status="ERROR",
                            error_type=type(exc).__name__)
        raise RuntimeError(f"Azure CLI query could not execute ({type(exc).__name__}).") from exc
    if result.returncode:
        utils.format_result("Azure query failed", status="ERROR",
                            exit_code=result.returncode, operation=arguments[:3])
        raise RuntimeError(f"Azure CLI {arguments[:3]!r} failed (exit {result.returncode}).")
    if not result.stdout.strip():
        utils.format_result("Azure query returned no data", status="INFO", diagnostic=True,
                            operation=arguments[:3], elapsed_seconds=round(time.perf_counter() - started, 3))
        return None
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        utils.format_result("Azure query returned invalid JSON", status="ERROR", operation=arguments[:3])
        raise RuntimeError("Azure CLI returned invalid JSON.") from exc
    utils.format_result("Azure query executed successfully", elapsed_seconds=round(time.perf_counter() - started, 3),
                        diagnostic=True)
    return data


def access_artifact(root, directory, context, apim, use_case, api_names, policy):
    """Generate editable access parameters and a relative, editable policy file."""
    parameters = {
        "apim": {
            "subscriptionId": context.config["subscription_id"],
            "resourceGroupName": context.config["resource_group"],
            "name": apim.apim_resource_name,
        },
        "keyVault": {"subscriptionId": "", "resourceGroupName": "", "name": ""},
        "useTargetAzureKeyVault": False,
        "useTargetFoundry": False,
        "useCase": use_case,
        "apiNameMapping": {"LLM": api_names},
        "services": [{
            "code": "LLM",
            "endpointSecretName": "VALIDATION-LLM-ENDPOINT",
            "apiKeySecretName": "VALIDATION-LLM-KEY",
            "policyXml": policy,
        }],
        "productTerms": "Validation-only access contract; retain until explicit cleanup.",
    }
    return prepare_artifact(
        Path(root) / "bicep" / "infra" / "citadel-access-contracts" / "main.bicep",
        parameters, Path(directory), policies={"ai-product-policy.xml": policy},
    )


def contract_identifiers(outputs, expected_product):
    """Require the deployed output's exact product/subscription relationship."""
    products = outputs.get("products", {}).get("value", [])
    subscriptions = outputs.get("subscriptions", {}).get("value", [])
    if not any(item.get("productId") == expected_product for item in products):
        raise RuntimeError(f"Deployment did not return product {expected_product!r}.")
    matches = [item for item in subscriptions if item.get("productId") == expected_product]
    if len(matches) != 1:
        raise RuntimeError("Deployment must return exactly one matching subscription.")
    subscription = matches[0]
    name = subscription.get("subscriptionName") or subscription.get("name")
    if not name:
        # The existing template returns subscriptionId rather than subscriptionName.
        name = subscription.get("subscriptionId", "").rstrip("/").rsplit("/", 1)[-1]
    if not name:
        raise RuntimeError("Deployment subscription output contains no exact identifier.")
    return expected_product, name


def load_contract_manifest(path):
    """Normalize a sanitized handoff; disabled/null Foundry entries are not connections."""
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    contracts = data.get("contracts")
    if not isinstance(contracts, (list, dict)):
        raise ValueError("Manifest requires a contracts list or keyed object.")
    if isinstance(contracts, list):
        names = {"Sales": "Sales-Assistant", "HR": "HR-ChatAgent", "Support": "Support-Bot"}
        normalized = {}
        for item in contracts:
            name = item.get("name") or names.get(item.get("business_unit"))
            if not name:
                raise ValueError("Handoff contracts require a known business_unit or explicit name.")
            if name in normalized:
                raise ValueError(f"Ambiguous predecessor for {name!r}.")
            normalized[name] = dict(item)
            # CLI projection turns the template's disabled {} entry into a
            # truthy object of null fields; it is not a published connection.
            connections = [
                connection for connection in item.get("connections", [])
                if isinstance(connection, dict)
                and isinstance(connection.get("connectionName"), str)
                and connection["connectionName"].strip()
            ] if item.get("use_foundry") is not False else []
            normalized[name]["connections"] = connections
            if len(connections) == 1:
                connection = connections[0]
                normalized[name].setdefault("connection_name", connection["connectionName"])
                if not normalized[name].get("project_endpoint"):
                    account = connection.get("foundryAccount")
                    project = connection.get("foundryProject")
                    if not account or not project:
                        raise ValueError(f"Contract {name!r} has no complete Foundry project coordinates.")
                    normalized[name]["project_endpoint"] = (
                        f"https://{account}.services.ai.azure.com/api/projects/{project}"
                    )
        contracts = normalized
    for name, item in contracts.items():
        for field in ("product_id", "subscription_name", "allowed_models"):
            if not item.get(field):
                raise ValueError(f"Contract {name!r} is missing {field!r}.")
        if any(key in item for key in ("key", "api_key", "subscription_key", "token")):
            raise ValueError("Predecessor manifests must not contain credentials.")
    return contracts


def find_access_contract_manifest(root, apim_coordinates, environment=None):
    """Find the latest complete Access Contracts handoff for this exact gateway."""
    directory = Path(root) / "validation" / ".runs" / "access-contracts"
    required_agents = {"Sales-Assistant", "HR-ChatAgent", "Support-Bot"}
    expected = {field: str(apim_coordinates.get(field) or "").casefold()
                for field in ("subscriptionId", "resourceGroupName", "name")}
    if not all(expected.values()):
        return None
    candidates = []
    for path in directory.glob("*/access-contracts.json"):
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise ValueError(f"Access Contracts manifest {path} cannot be read; rerun Access Contracts or supply manifest_path.") from exc
        if not isinstance(document, dict):
            raise ValueError(f"Access Contracts manifest {path} must contain a JSON object.")
        records = document.get("contracts")
        records = list(records.values()) if isinstance(records, dict) else records
        if not isinstance(records, list) or not records:
            continue
        if not all(
            isinstance(record, dict) and isinstance(record.get("apim"), dict)
            and all(str(record["apim"].get(field, "")).casefold() == value
                    for field, value in expected.items())
            for record in records
        ):
            continue
        saved_environment = document.get("environment")
        if environment and saved_environment and saved_environment != environment:
            continue
        contracts = load_contract_manifest(path)
        if not required_agents.issubset(contracts):
            continue
        candidates.append((path.stat().st_mtime_ns, path))
    if not candidates:
        return None
    newest = max(timestamp for timestamp, _ in candidates)
    matches = [path for timestamp, path in candidates if timestamp == newest]
    if len(matches) != 1:
        raise ValueError("Multiple equally recent Access Contracts handoffs match this gateway; set manifest_path explicitly.")
    return matches[0]


def complete_backend_parameters(source, additions, *, confirmed_complete):
    """Losslessly merge new IDs; never silently replace shared backend records."""
    if confirmed_complete is not True:
        raise ValueError(
            "Confirm the source contains ALL existing backends, aliases and global "
            "routing options before redeploying shared policy fragments."
        )
    if not isinstance(source, dict) or not source.get("llmBackendConfig"):
        raise ValueError("Supply the full onboarding parameter object, not an azd model list.")
    if "modelAliases" not in source:
        raise ValueError("Source must explicitly include all existing modelAliases (even []).")
    merged = deepcopy(source)
    backends = merged["llmBackendConfig"]
    if not isinstance(backends, list) or not isinstance(merged["modelAliases"], list):
        raise ValueError("llmBackendConfig and modelAliases must be arrays.")
    alias_names = [alias["name"] for alias in merged["modelAliases"]]
    if len(alias_names) != len(set(alias_names)):
        raise ValueError("Source has duplicate alias names.")
    identifiers = [item["backendId"] for item in backends]
    if len(identifiers) != len(set(identifiers)):
        raise ValueError("Source has duplicate backend IDs.")
    for item in additions:
        if item["backendId"] in identifiers:
            raise ValueError(f"Refusing hidden update of backend {item['backendId']!r}.")
        backends.append(deepcopy(item))
        identifiers.append(item["backendId"])
    for backend in backends:
        auth = backend.get("authConfig") or {}
        if auth.get("secretValue"):
            raise ValueError("Use Key Vault references; inline provider secrets are not persisted.")
        if backend.get("authType", "").startswith("api-key-"):
            if not auth.get("namedValueKey") or not auth.get("keyVaultSecretUri"):
                raise ValueError("API-key backends require independent named-value and KV references.")
    return merged


def review_backend_artifact(artifact, source, target, existing_ids):
    """Recheck edited parameters before a shared-routing deployment.

    Fresh backend/alias edits are allowed; changes to predecessor records or
    global routing options must first be reflected in the explicitly approved
    complete source. Compiling alone cannot establish safe merge semantics.
    """
    compiled = artifact.compile()
    document = compiled["parametersJson"]
    if isinstance(document, str):
        document = json.loads(document)
    effective = {name: entry.get("value") for name, entry in document["parameters"].items()}
    if effective.get("apim") != target:
        raise ValueError("Edited parameters target another APIM environment.")
    complete_backend_parameters(effective, [], confirmed_complete=True)
    current = {backend["backendId"]: backend for backend in effective["llmBackendConfig"]}
    if not set(existing_ids) <= current.keys():
        raise ValueError("Edited parameters omitted live backends.")
    for predecessor in source["llmBackendConfig"]:
        if current.get(predecessor["backendId"]) != predecessor:
            raise ValueError("Edited parameters changed a predecessor backend; review the complete source first.")
    aliases = {alias["name"]: alias for alias in effective["modelAliases"]}
    for predecessor in source["modelAliases"]:
        if aliases.get(predecessor["name"]) != predecessor:
            raise ValueError("Edited parameters changed or omitted a predecessor alias.")
    for key, value in source.items():
        if key not in {"apim", "llmBackendConfig", "modelAliases"} and effective.get(key) != value:
            raise ValueError(f"Edited parameters changed global option {key!r}; review the complete source first.")
    return effective


def chat_content(data):
    """Require the actual chat response shape rather than a printable object."""
    if not isinstance(data, dict):
        return ""
    choices = data.get("choices") or []
    if not choices or not isinstance(choices[0], dict):
        return ""
    return (choices[0].get("message") or {}).get("content") or ""


def error_code(data):
    if not isinstance(data, dict):
        return ""
    error = data.get("error") or {}
    return error.get("code", "") if isinstance(error, dict) else ""


def delete_owned_product(context, apim, product_id):
    """Delete one caller-confirmed run-owned product; no subscription enumeration."""
    cli_json(
        "apim", "product", "delete",
        "--resource-group", context.config["resource_group"],
        "--service-name", apim.apim_resource_name,
        "--product-id", product_id, "--delete-subscriptions", "true", "--yes",
    )
