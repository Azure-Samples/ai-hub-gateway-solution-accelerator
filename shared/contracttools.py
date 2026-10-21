"""Small, secret-conscious helpers for editable contract deployment artifacts.

Public API:
* ``render_bicep(value)`` renders JSON-like values losslessly. Finite floating
  point values use json() expressions; unsupported values fail without coercion.
* ``write_parameters(template, parameters, directory)`` returns a generated
  ``main.bicepparam`` Path. ``PolicyReference(filename)`` renders loadTextContent.
* ``prepare_artifact(template, parameters, run_dir, policies=None)`` returns a
  ContractArtifact. policies maps relative XML filenames to contents; matching
  parameter strings become file references without changing the caller's dict.
* ``preview(params_file)`` validates locally and returns the editable file text;
  ``compile_parameters(params_file)`` compiles the actual, possibly edited file
  with ``az bicep build-params --stdout`` (no Azure calls or ARM files).
* ``deploy_contract(params_file, location, name, required_outputs=())`` compiles
  first, then explicitly deploys at subscription scope. It returns raw ARM
  output envelopes, ``{name: {type: ..., value: ...}}``, never credentials.
  Secret-bearing outputs are excluded from the CLI projection; unexpected
  credential fields are removed defensively. Known endpoint/subscription/Foundry metadata
  is projected through explicit field allowlists, preserving exact subscription
  identifiers and Key Vault reference names, never their credential values.
  Resolve subscription keys afresh.
* ``access_policy(models, tpm, quota, period, inbound_extra='', ...)`` composes
  ordered LLM access XML, with optional JWT and PII sections.

ContractArtifact provides preview/compile/deploy, a sanitized manifest, explicit
record_resource(resource_id, created=..., shared=False, predecessor=False), and
cleanup_candidates(). It never deletes resources. Deployment success is NOT
ownership evidence: callers must explicitly establish newly created resources.
Place run_dir under the ignored validation/.runs/<scenario>/<run-id> directory.
Credential-shaped fields, JWTs, bearer tokens, private keys and credential URLs
are rejected before persistence, including after manual parameter edits. Secret
names, Key Vault references and APIM named-value references are metadata, not
credentials. Arbitrary unlabeled strings cannot be proven secret-free; do not
pass secret material to this API. CLI failures intentionally omit raw output.
"""

from __future__ import annotations

import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
if __package__:
    from . import utils
else:
    import utils
from dataclasses import dataclass
from typing import Any, Iterable
from xml.etree import ElementTree as ET
from xml.sax.saxutils import quoteattr


class ContractError(RuntimeError):
    """Invalid artifacts, unsafe credentials, or unsuccessful CLI operations."""


_IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_SECRET_WORDS = re.compile(
    r"secret|password|credential|authorization|apikey|subscriptionkey|"
    r"primarykey|secondarykey|accesskey|accountkey|connectionstring|"
    r"rotationkeyoverride|clientassertion|sastoken|accesstoken|refreshtoken|"
    r"bearertoken|privatekey|^token$|^key$",
    re.IGNORECASE,
)
_SECRET_VALUE = re.compile(
    r"-----BEGIN (?:[A-Z ]*PRIVATE KEY)|\bBearer\s+[A-Za-z0-9._~+/=-]+|"
    r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|"
    r"(?i:[?&](?:sig|api[_-]?key|access[_-]?token|client[_-]?secret)=)[^&#\s]+|"
    r"(?i:AccountKey|SharedAccessKey|Password)\s*=\s*[^;\s]+"
)


def _secret_field(name: str) -> bool:
    normalized = re.sub(r"[^a-z0-9]", "", name.lower())
    if normalized.endswith(("name", "names", "uri", "url", "id", "ids", "reference")):
        return False
    if normalized in {
        "keyvault", "additionalkeyvaults", "usetargetazurekeyvault", "usekeyvault",
        "useprimarykey", "activekeyslot", "keyrotationenabled", "keyrotationapplied",
        "rotationkeyseed", "tokenquota", "tokenquotaperiod", "tokensperminute",
        "maxoutputtokens", "maxtokens", "tokenusage", "forwardsubscriptionkeytosource",
    }:
        return False
    return bool(_SECRET_WORDS.search(normalized))


def _reference(value: Any) -> bool:
    if isinstance(value, str):
        return bool(re.fullmatch(r"\{\{[^{}\r\n]+\}\}", value)) or bool(
            re.fullmatch(r"https://[^/\s]+\.vault\.azure\.net/secrets/[^?\s]+", value)
        )
    if isinstance(value, dict) and set(value) == {"reference"}:
        ref = value["reference"]
        return (
            isinstance(ref, dict)
            and isinstance(ref.get("keyVault"), dict)
            and isinstance(ref["keyVault"].get("id"), str)
            and isinstance(ref.get("secretName"), str)
        )
    return False


def _check_secrets(value: Any) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if not isinstance(key, str):
                raise ContractError("Object keys must be strings.")
            if _secret_field(key) and child not in ("", None, [], {}) and not _reference(child):
                raise ContractError("Inline credential field rejected; use a secret reference.")
            _check_secrets(child)
    elif isinstance(value, (list, tuple)):
        for child in value:
            _check_secrets(child)
    elif isinstance(value, str):
        if _SECRET_VALUE.search(value):
            raise ContractError("Credential-shaped text rejected; use a secret reference.")
        if re.match(r"^\s*(?:<!--.*?-->\s*)*<policies(?:\s|>)", value, re.DOTALL):
            try:
                root = ET.fromstring(value)
            except ET.ParseError:
                raise ContractError("Policy XML is malformed.") from None
            _check_policy_credentials(root)


def _check_policy_credentials(root: ET.Element) -> None:
    for node in root.iter():
        if node.tag in {"set-header", "set-variable"} and _secret_field(node.get("name", "")):
            values = [node.get("value", "")] + [n.text or "" for n in node.findall("value")]
            if any(v and not _reference(v) for v in values):
                raise ContractError("Inline policy credentials rejected; use named values.")


def _quote(value: str) -> str:
    escaped = []
    for char in value:
        if char in {"\\", "'", "\r", "\n", "\t"}:
            escaped.append({"\\": "\\\\", "'": "\\'", "\r": "\\r",
                            "\n": "\\n", "\t": "\\t"}[char])
        elif ord(char) < 32 or ord(char) == 127:
            escaped.append(f"\\u{{{ord(char):x}}}")
        else:
            escaped.append(char)
    return "'" + "".join(escaped).replace("${", r"\${") + "'"


@dataclass(frozen=True)
class PolicyReference:
    """A relative XML file loaded beside the .bicepparam, not arbitrary code."""

    filename: str

    def __post_init__(self) -> None:
        path = Path(self.filename)
        if path.is_absolute() or path.drive or ".." in path.parts or path.suffix.lower() != ".xml":
            raise ContractError("Policy references must be relative XML filenames.")


def render_bicep(value: Any) -> str:
    """Render JSON-like data; preserve object order, strings and integer values."""
    if isinstance(value, PolicyReference):
        return f"loadTextContent({_quote(Path(value.filename).as_posix())})"
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        if not -(2**63) <= value < 2**63:
            raise ValueError("Bicep integers must fit in signed 64 bits.")
        return str(value) if value != -(2**63) else "(-9223372036854775807 - 1)"
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError("Nonfinite floating point values are not valid JSON.")
        return f"json({_quote(json.dumps(value, allow_nan=False))})"
    if isinstance(value, str):
        return _quote(value)
    if isinstance(value, (list, tuple)):
        return "[\n" + "\n".join("  " + render_bicep(v).replace("\n", "\n  ")
                                for v in value) + "\n]"
    if isinstance(value, dict):
        if not all(isinstance(k, str) for k in value):
            raise TypeError("Bicep object keys must be strings.")
        return "{\n" + "\n".join(
            f"  {_quote(k)}: " + render_bicep(v).replace("\n", "\n  ")
            for k, v in value.items()
        ) + "\n}"
    raise TypeError(f"Unsupported Bicep value type: {type(value).__name__}")


def _parameter_text(template: Path, parameters: dict, directory: Path) -> str:
    if not template.is_file() or template.suffix.lower() != ".bicep":
        raise ContractError("An existing .bicep template is required.")
    if not isinstance(parameters, dict) or not all(
        isinstance(k, str) and _IDENTIFIER.fullmatch(k) for k in parameters
    ):
        raise ContractError("Parameters require valid Bicep identifiers.")
    _check_secrets(parameters)
    secure_names = re.findall(
        r"@secure\(\)\s*(?:@\w+\([^\n]*\)\s*)*param\s+(\w+)",
        template.read_text(encoding="utf-8"),
    )
    if any(k in parameters and parameters[k] not in ("", None, {})
           and not _reference(parameters[k]) for k in secure_names):
        raise ContractError("Inline secure parameter rejected before writing.")
    relative = os.path.relpath(template.resolve(), directory.resolve()).replace("\\", "/")
    return "using " + _quote(relative) + "\n\n" + "\n\n".join(
        f"param {key} = {render_bicep(value)}" for key, value in parameters.items()
    ) + "\n"


def write_parameters(template: Path, parameters: dict, directory: Path) -> Path:
    """Write an editable parameter file after validating all values for safety."""
    template, directory = Path(template), Path(directory)
    text = _parameter_text(template, parameters, directory)
    directory.mkdir(parents=True, exist_ok=True)
    params_file = directory / "main.bicepparam"
    params_file.write_text(text, encoding="utf-8", newline="")
    return params_file


def _run_az(arguments: list[str]) -> dict:
    utils.format_command(["az", *arguments], title="Bicep / contract command", diagnostic=True)
    started = time.perf_counter()
    executable = shutil.which("az")
    if executable is None:
        utils.format_result("Azure CLI is unavailable", status="ERROR", guidance="Install Azure CLI and Bicep.")
        raise ContractError("Azure CLI is required; install az and the Bicep compiler.")
    command = [executable]
    if os.name == "nt" and Path(executable).suffix.lower() == ".cmd":
        bundled_python = Path(executable).parent.parent / "python.exe"
        if bundled_python.is_file():
            # The MSI az.cmd uses -I, which ignores PYTHONIOENCODING/PYTHONUTF8.
            # Preserve its isolated launcher but explicitly enable UTF-8.
            command = [str(bundled_python), "-IB", "-X", "utf8", "-m", "azure.cli"]
    try:
        result = subprocess.run(
            [*command, *arguments, "--only-show-errors"],
            capture_output=True, text=True, encoding="utf-8", check=False,
            env={**os.environ, "AZURE_CORE_COLLECT_TELEMETRY": "false",
                 "PYTHONIOENCODING": "utf-8", "PYTHONUTF8": "1"},
        )
    except (OSError, UnicodeError):
        utils.format_result("Azure CLI could not execute", status="ERROR", operation=arguments[:3])
        raise ContractError("Unable to execute Azure CLI.") from None
    if result.returncode:
        codes = sorted(set(re.findall(r"\bBCP\d+\b", result.stderr or "")))
        utils.format_result("Azure CLI command failed", status="ERROR",
                            operation=arguments[:3], exit_code=result.returncode,
                            compiler_diagnostic_codes=codes,
                            guidance="Review the editable parameter/template file; raw CLI output is withheld to protect credentials.")
        raise ContractError(f"Azure CLI operation failed (exit {result.returncode}); "
                            "raw output withheld to protect credentials.")
    try:
        parsed = json.loads(result.stdout)
    except (TypeError, json.JSONDecodeError):
        utils.format_result("Azure CLI returned invalid JSON", status="ERROR", operation=arguments[:3])
        raise ContractError("Azure CLI returned invalid JSON; raw output withheld.") from None
    if not isinstance(parsed, dict):
        utils.format_result("Azure CLI returned an unexpected JSON shape", status="ERROR", operation=arguments[:3])
        raise ContractError("Azure CLI returned an unexpected JSON shape.")
    utils.format_result("Azure CLI command executed successfully",
                        elapsed_seconds=round(time.perf_counter() - started, 3), exit_code=0, diagnostic=True)
    if result.stderr and result.stderr.strip():
        utils.format_result("Azure CLI emitted diagnostics", status="WARNING",
                            compiler_diagnostic_codes=sorted(set(re.findall(r"\bBCP\d+\b", result.stderr))),
                            details="Review compiler/CLI diagnostics if needed; raw stderr is withheld to protect credentials.")
    return parsed


def _compiled_docs(compiled: dict) -> tuple[dict, dict]:
    try:
        template = compiled["templateJson"]
        parameters = compiled["parametersJson"]
        template = json.loads(template) if isinstance(template, str) else template
        parameters = json.loads(parameters) if isinstance(parameters, str) else parameters
        if not isinstance(template, dict) or not isinstance(parameters, dict):
            raise ValueError
        supplied = parameters["parameters"]
        if not isinstance(supplied, dict):
            raise ValueError
    except (KeyError, ValueError, TypeError):
        raise ContractError("Bicep compiler returned invalid template/parameter documents.") from None
    if any(not isinstance(entry, dict) or not ({"value", "reference"} & set(entry))
           for entry in supplied.values()):
        raise ContractError("Bicep compiler returned malformed parameter entries.")
    _check_secrets({name: entry.get("value") if "value" in entry else entry
                    for name, entry in supplied.items()})
    for name, entry in supplied.items():
        definition = template.get("parameters", {}).get(name, {})
        if str(definition.get("type", "")).lower() in {"securestring", "secureobject"}:
            if not _reference(entry) and entry.get("value") not in ("", None, {}):
                raise ContractError("Inline secure parameter rejected; use a Key Vault reference.")
    return template, parameters


def compile_parameters(params_file: Path) -> dict:
    """Compile the current artifact locally, then inspect its resolved values."""
    params_file = Path(params_file).resolve()
    if not params_file.is_file() or params_file.suffix.lower() != ".bicepparam":
        raise ContractError("An existing .bicepparam file is required.")
    compiled = _run_az(["bicep", "build-params", "--file", str(params_file), "--stdout"])
    _compiled_docs(compiled)
    return compiled


def preview(params_file: Path) -> str:
    """Return the actual authored file only after its resolved values are safe."""
    compile_parameters(params_file)
    text = Path(params_file).read_text(encoding="utf-8")
    _check_secrets(text)
    return text


def _safe_outputs(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: _safe_outputs(child) for key, child in value.items()
                if not _secret_field(key) and not (
                    isinstance(child, dict)
                    and str(child.get("type", "")).lower().startswith("secure")
                )}
    if isinstance(value, list):
        return [_safe_outputs(child) for child in value]
    if isinstance(value, str) and _SECRET_VALUE.search(value):
        return "[REDACTED]"
    return value


def _output_is_secret(name: str, definition: dict, template: dict,
                      seen: set[str] | None = None) -> bool:
    if _secret_field(name) or str(definition.get("type", "")).lower().startswith("secure"):
        return True
    # ARM object/copy definitions retain nested field names. Exclude the whole
    # output rather than asking az to print a nested key and redacting it later.
    text = json.dumps(definition)
    fields = re.findall(r'"([^"]+)"\s*:', text)
    references = re.findall(r"(?:parameters|variables)\('([^']+)'\)", text)
    module_outputs = re.findall(r"\.([A-Za-z_]\w*)", text)
    if any(_secret_field(field) for field in fields + references + module_outputs):
        return True
    if re.search(r"\b(?:listKeys|listSecrets|getSecret)\s*\(", text, re.IGNORECASE):
        return True
    for parameter in re.findall(r"parameters\('([^']+)'\)", text):
        parameter_definition = template.get("parameters", {}).get(parameter, {})
        if str(parameter_definition.get("type", "")).lower().startswith("secure"):
            return True
        default = parameter_definition.get("defaultValue")
        try:
            _check_secrets(default)
        except ContractError:
            return True
    seen = set() if seen is None else seen
    for variable in re.findall(r"variables\('([^']+)'\)", text):
        if variable not in seen:
            seen.add(variable)
            if _output_is_secret(variable, {"value": template.get("variables", {}).get(variable)},
                                 template, seen):
                return True
    return False


def deploy_contract(params_file: Path, location: str, name: str, *,
                    required_outputs: Iterable[str] = ()) -> dict:
    """Compile before deploying; return credential-free raw ARM output envelopes."""
    if not location or not name:
        raise ContractError("Deployment location and name are required.")
    _check_secrets([location, name])
    template, compiled_parameters = _compiled_docs(compile_parameters(params_file))
    output_definitions = template.get("outputs", {})
    names = [key for key, definition in output_definitions.items()
             if not _output_is_secret(key, definition, template)]
    # Compiled reference expressions can mark whole metadata outputs as sensitive.
    # Project known-safe fields before the CLI serializes any credential values.
    metadata_projections = {
        "endpoints": (
            '{type:properties.outputs.endpoints.type,'
            'value:properties.outputs.endpoints.value[].{'
            'code:code,productId:productId,subscriptionName:subscriptionName,endpoint:endpoint,'
            'assetEndpoints:assetEndpoints[].{secretName:secretName,endpoint:endpoint}}}'
        ),
        "subscriptions": (
            '{type:properties.outputs.subscriptions.type,'
            'value:properties.outputs.subscriptions.value[].{'
            'name:name,subscriptionName:subscriptionName,subscriptionId:subscriptionId,productId:productId,'
            'keyVaultApiKeySecretName:keyVaultApiKeySecretName,'
            'keyVaultEndpointSecretName:keyVaultEndpointSecretName,'
            'keyVaultEndpointSecretNames:keyVaultEndpointSecretNames}}'
        ),
        "foundryConnections": (
            '{type:properties.outputs.foundryConnections.type,'
            'value:properties.outputs.foundryConnections.value[].{'
            'code:code,connectionName:connectionName,targetUrl:targetUrl,'
            'foundryAccount:foundryAccount,foundryProject:foundryProject,'
            'authType:authType,managedIdentityAudience:managedIdentityAudience}}'
        ),
    }
    projected_outputs = {
        key: projection for key, projection in metadata_projections.items()
        if str(output_definitions.get(key, {}).get("type", "")).lower() == "array"
    }
    names.extend(key for key in projected_outputs if key not in names)
    required_outputs = tuple(required_outputs)
    if any(key not in names for key in required_outputs):
        raise ContractError("A required output is absent or contains credential fields.")
    output_query = "{" + ",".join(
        f"{json.dumps(key)}:" + (
            projected_outputs[key] if key in projected_outputs
            else f"properties.outputs.{json.dumps(key)}"
        ) for key in names
    ) + "}" if names else "`{}`"
    query = "{state:properties.provisioningState,outputs:" + output_query + "}"
    backend_config = compiled_parameters["parameters"].get("llmBackendConfig", {}).get("value", [])
    models = list(dict.fromkeys(
        model.get("name") if isinstance(model, dict) else model
        for backend in backend_config for model in backend.get("supportedModels", [])
    ))
    utils.format_command([
        "az", "deployment", "sub", "create", "--location", location, "--name", name,
        "--parameters", str(Path(params_file).resolve()),
    ], title="Deploy contract", models=models, output="Credential-safe output projection")
    result = _run_az([
        "deployment", "sub", "create", "--location", location, "--name", name,
        "--parameters", str(Path(params_file).resolve()), "--query", query,
        "--output", "json",
    ])
    if result.get("state") != "Succeeded" or not isinstance(result.get("outputs"), dict):
        utils.format_result("Contract deployment did not succeed", status="ERROR",
                            deployment=name, state=result.get("state"))
        raise ContractError("Deployment did not succeed or returned invalid outputs.")
    outputs = _safe_outputs(result["outputs"])
    for key, entry in outputs.items():
        if not isinstance(entry, dict) or "value" not in entry or "type" not in entry:
            utils.format_result("Malformed deployment output", status="ERROR",
                                deployment=name, output_name=key)
            raise ContractError("Deployment returned a malformed ARM output envelope.")
    if any(key not in outputs or outputs[key]["value"] in (None, "", [], {})
           for key in required_outputs):
        utils.format_result("Required deployment output is missing", status="ERROR",
                            deployment=name, required_outputs=list(required_outputs))
        raise ContractError("Deployment is missing a required nonempty output.")
    utils.format_result("Contract deployed successfully", deployment=name, outputs=list(outputs),
                        backends=outputs.get("backendIds", {}).get("value"),
                        pools=outputs.get("poolNames", {}).get("value"))
    return outputs


def access_policy(allowed_models: Iterable[str] | str, tokens_per_minute: int,
                  token_quota: int, token_quota_period: str, inbound_extra: str = "",
                  *, jwt_required: bool | None = None, pii_inbound: str = "",
                  pii_outbound: str = "") -> str:
    """Compose base, JWT, model/RBAC, capacity, extra/PII, and outbound sections."""
    models = allowed_models if isinstance(allowed_models, str) else ",".join(allowed_models)
    if any(isinstance(n, bool) or not isinstance(n, int) or n <= 0
           for n in (tokens_per_minute, token_quota)):
        raise ValueError("Token capacity and quota must be positive integers.")
    if token_quota_period not in {"Hourly", "Daily", "Weekly", "Monthly", "Yearly"}:
        raise ValueError("Unsupported APIM token quota period.")
    if jwt_required is not None and not isinstance(jwt_required, bool):
        raise TypeError("jwt_required must be bool or None.")
    jwt = (f'<set-variable name="jwtRequired" value="{str(jwt_required).lower()}" />'
           if jwt_required is not None else "")
    xml = f"""<policies>
  <inbound>
    <base />
    {jwt}
    <include-fragment fragment-id="set-llm-requested-model" />
    <set-variable name="allowedModels" value={quoteattr(models)} />
    <include-fragment fragment-id="validate-model-access" />
    <llm-token-limit counter-key="@(context.Subscription.Id)" tokens-per-minute="{tokens_per_minute}" estimate-prompt-tokens="false" token-quota="{token_quota}" token-quota-period="{token_quota_period}" />
    <set-variable name="enableResponseHeaders" value="@(true)" />
    {inbound_extra}
    {pii_inbound}
  </inbound>
  <backend><base /></backend>
  <outbound><base />{pii_outbound}</outbound>
  <on-error><base /></on-error>
</policies>"""
    _validate_policy(xml)
    return xml


def _validate_policy(xml: str) -> None:
    _check_secrets(xml)
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        raise ContractError("Policy XML is malformed.") from None
    if root.tag != "policies":
        raise ContractError("A policy document requires a policies root.")
    _check_policy_credentials(root)


@dataclass(frozen=True)
class ContractArtifact:
    """An editable parameter file and a credential-free run ownership manifest."""

    params_file: Path
    manifest_file: Path

    def preview(self) -> str:
        return preview(self.params_file)

    def compile(self) -> dict:
        return compile_parameters(self.params_file)

    def deploy(self, location: str, name: str, *,
               required_outputs: Iterable[str] = ()) -> dict:
        outputs = deploy_contract(self.params_file, location, name,
                                  required_outputs=required_outputs)
        manifest = self._manifest()
        manifest["deployment"] = {"name": name, "location": location}
        manifest["outputs"] = outputs
        self._save(manifest)
        return outputs

    def _manifest(self) -> dict:
        try:
            manifest = json.loads(self.manifest_file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            raise ContractError("Run manifest is missing or malformed.") from None
        if not isinstance(manifest, dict) or manifest.get("params_file") != str(self.params_file):
            raise ContractError("Run manifest does not belong to this artifact.")
        _check_secrets(manifest)
        return manifest

    def _save(self, manifest: dict) -> None:
        _check_secrets(manifest)
        self.manifest_file.write_text(json.dumps(manifest, indent=2) + "\n",
                                      encoding="utf-8", newline="")

    def record_resource(self, resource_id: str, *, created: bool,
                        shared: bool = False, predecessor: bool = False) -> None:
        """Explicitly attest creation; conflicting records permanently retain it."""
        if not isinstance(resource_id, str) or not re.fullmatch(
            r"/subscriptions/[^/]+/resourceGroups/[^/]+/providers/[^/]+/(?:[^/]+/[^/]+)(?:/[^/]+/[^/]+)*",
            resource_id, re.IGNORECASE,
        ):
            raise ContractError("Ownership requires a full Azure resource ID.")
        if not all(isinstance(v, bool) for v in (created, shared, predecessor)):
            raise TypeError("Ownership flags must be explicit booleans.")
        _check_secrets(resource_id)
        manifest = self._manifest()
        records = manifest["resources"]
        existing = next((r for r in records
                         if r["resource_id"].lower() == resource_id.lower()), None)
        if existing:
            existing.update(created=existing["created"] and created,
                            shared=existing["shared"] or shared,
                            predecessor=existing["predecessor"] or predecessor)
        else:
            records.append({"resource_id": resource_id, "created": created,
                            "shared": shared, "predecessor": predecessor})
        self._save(manifest)

    def cleanup_candidates(self) -> list[str]:
        """Preview only explicit, newly created, nonshared, nonpredecessor IDs."""
        return [r["resource_id"] for r in self._manifest()["resources"]
                if r.get("created") is True and r.get("shared") is False
                and r.get("predecessor") is False]


def prepare_artifact(template: Path, parameters: dict, run_dir: Path,
                     policies: dict[str, str] | None = None) -> ContractArtifact:
    """Prepare XML, editable parameters and manifest; never deploy implicitly."""
    template, run_dir = Path(template).resolve(), Path(run_dir).resolve()
    policies = policies or {}
    references = {}
    for filename, xml in policies.items():
        reference = PolicyReference(filename)
        if not (run_dir / filename).resolve().is_relative_to(run_dir):
            raise ContractError("Policy files must remain inside the run directory.")
        _validate_policy(xml)
        references[xml] = reference

    def replace(value: Any) -> Any:
        if isinstance(value, str):
            return references.get(value, value)
        if isinstance(value, dict):
            return {k: replace(v) for k, v in value.items()}
        if isinstance(value, (list, tuple)):
            return [replace(v) for v in value]
        return value

    _check_secrets(parameters)
    replaced = replace(parameters)
    text = _parameter_text(template, replaced, run_dir)
    manifest_file = run_dir / "manifest.json"
    if manifest_file.exists():
        raise ContractError("Use a fresh run directory; existing ownership must not be overwritten.")
    run_dir.mkdir(parents=True, exist_ok=True)
    for filename, xml in policies.items():
        policy_file = run_dir / filename
        policy_file.parent.mkdir(parents=True, exist_ok=True)
        policy_file.write_text(xml, encoding="utf-8", newline="")
    params_file = run_dir / "main.bicepparam"
    params_file.write_text(text, encoding="utf-8", newline="")
    artifact = ContractArtifact(params_file, manifest_file)
    artifact._save({
        "version": 1, "template": str(template), "params_file": str(params_file),
        "policies": list(policies), "resources": [], "outputs": {},
    })
    return artifact
