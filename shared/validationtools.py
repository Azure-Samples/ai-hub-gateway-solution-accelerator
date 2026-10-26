"""Strict, cloud-independent plumbing for the validation notebooks.

Configuration precedence is explicit overrides, one selected azd snapshot, then
non-resource defaults. Operation overrides replace name-based assumptions per
model. Model selection follows deployment order; skip keywords affect tests only.
"""

from __future__ import annotations

import copy
import json
import math
import os
import re
import shutil
import subprocess
import time
import warnings
from collections import Counter
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Any, Callable, Mapping, Sequence
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
if __package__:
    from . import utils
else:
    import utils


class ValidationError(RuntimeError):
    """Invalid configuration, unsuccessful command, or failed validation."""


class ValidationBlocked(ValidationError):
    """Required coverage cannot be performed with the available configuration."""


REPO_ROOT = Path(__file__).resolve().parents[1]
_REDACTED = "[REDACTED]"
_SECRET_KEY = re.compile(
    r"authorization|(?:api|subscription|access|primary|secondary)[_-]?key|"
    r"^key$|private[_-]?key|keyvalue|secret|password|token|credential|cookie|signature", re.IGNORECASE
)
_PUBLIC_METRIC_KEYS = {
    "prompttokens", "completiontokens", "totaltokens", "inputtokens", "outputtokens",
    "tokensperminute", "tokenquota", "tokenquotaperiod", "tokenusage",
}
_PUBLIC_METADATA_SUFFIX = re.compile(r"(?:name|names|uri|url|id|ids|source|reference)$", re.I)


def redact(value: Any) -> Any:
    """Return a report-safe copy; redact credentials in headers, URLs and text."""
    if isinstance(value, Mapping):
        return {
            str(key): _REDACTED if (
                _SECRET_KEY.search(str(key))
                and re.sub(r"[^a-z0-9]", "", str(key).lower()) not in _PUBLIC_METRIC_KEYS
                and not _PUBLIC_METADATA_SUFFIX.search(str(key))
            ) else redact(item)
            for key, item in value.items()
        }
    if isinstance(value, (list, tuple)):
        return [redact(item) for item in value]
    if not isinstance(value, str):
        return value
    text = re.sub(r"(?i)\bBearer\s+[^\s,\"'}]+", "Bearer " + _REDACTED, value)
    text = re.sub(
        r"""(?ix)(["']?(?:authorization|[\w-]*(?:key|secret|password|token|cookie|signature))
        ["']?\s*[:=]\s*)(["'])(.*?)\2""",
        lambda match: match[1] + match[2] + _REDACTED + match[2],
        text,
    )
    text = re.sub(
        r"(?i)(\b(?:api[_-]?key|subscription[_-]?key|[\w-]*secret[\w-]*|"
        r"[\w-]*password[\w-]*|[\w-]*token[\w-]*|authorization|cookie)"
        r"\s*[:=]\s*)(?!\[REDACTED\])[^\s,;}&]+",
        lambda match: match[1] + _REDACTED,
        text,
    )
    text = re.sub(r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b", _REDACTED, text)
    if text.startswith(("https://", "http://")):
        parts = urlsplit(text)
        netloc = parts.netloc
        if "@" in netloc:
            netloc = _REDACTED + "@" + netloc.rsplit("@", 1)[1]
        query = [
            (key, _REDACTED if _SECRET_KEY.search(key) or key.lower() == "sig" else item)
            for key, item in parse_qsl(parts.query, keep_blank_values=True)
        ]
        text = urlunsplit((parts.scheme, netloc, parts.path, urlencode(query), parts.fragment))
    else:
        text = re.sub(r"""https?://[^\s"'<>]+""", lambda match: redact(match.group(0)), text)
    return text


def _run_json(arguments: Sequence[str]) -> Any:
    """Run an argument vector without shell interpolation or permissive parsing."""
    executable = shutil.which(arguments[0])
    command = list(arguments)
    if executable:
        command[0] = executable
        path = Path(executable)
        if path.suffix.lower() in {".cmd", ".bat"}:
            interpreters = (path.parent.parent / "python.exe", path.parent / "python.exe")
            interpreter = next((candidate for candidate in interpreters if candidate.is_file()), None)
            if arguments[0] != "az" or interpreter is None:
                raise ValidationError(f"{arguments[0]} needs a native executable; refusing shell interpolation")
            command = [str(interpreter), "-IB", "-X", "utf8", "-m", "azure.cli", *arguments[1:]]
    utils.format_command(list(arguments), title="Environment / Azure CLI command", diagnostic=True)
    started = time.perf_counter()
    try:
        completed = subprocess.run(
            command, capture_output=True, text=True, check=False,
            shell=False, timeout=120, encoding="utf-8",
            env={**os.environ, "PYTHONIOENCODING": "utf-8", "PYTHONUTF8": "1"},
        )
    except (OSError, UnicodeError, subprocess.SubprocessError) as error:
        utils.format_result("Command could not execute", status="ERROR",
                            error_type=type(error).__name__, details=str(error))
        raise ValidationError(f"Unable to run {arguments[0]}: {redact(str(error))}") from error
    if completed.returncode:
        detail = redact(completed.stderr.strip() or completed.stdout.strip())
        utils.format_result("Command failed", status="ERROR", exit_code=completed.returncode, details=detail)
        raise ValidationError(f"{arguments[0]} failed ({completed.returncode}): {detail}")
    try:
        data = json.loads(completed.stdout)
    except (json.JSONDecodeError, TypeError) as error:
        utils.format_result("Command returned invalid JSON", status="ERROR", command=arguments[0])
        raise ValidationError(f"{arguments[0]} returned invalid JSON") from error
    utils.format_result("Command executed successfully", exit_code=0,
                        elapsed_seconds=round(time.perf_counter() - started, 3), diagnostic=True)
    return data


_ALIASES = {
    "resource_group": ("AZURE_RESOURCE_GROUP", "GOVERNANCE_HUB_RESOURCE_GROUP"),
    "location": ("AZURE_LOCATION", "LOCATION"),
    "subscription_id": ("AZURE_SUBSCRIPTION_ID", "SUBSCRIPTION_ID"),
    "apim_name": ("APIM_NAME", "APIM_RESOURCE_NAME"),
    "gateway_url": ("APIM_GATEWAY_URL",),
    "apim_aoi_path": ("APIM_AOI_PATH",),
    "llm_backends": ("LLM_BACKEND_CONFIG", "LLM_BACKENDS_CONFIG"),
    "capabilities": ("VALIDATION_MODEL_CAPABILITIES",),
    "skipped_models": ("VALIDATION_SKIPPED_MODELS",),
    "infer_operations": ("VALIDATION_INFER_OPERATIONS",),
    "model_aliases": ("MODEL_ALIASES", "LLM_MODEL_ALIASES"),
    "tenant_id": ("AZURE_TENANT_ID", "TENANT_ID"),
    "ai_foundry_services": ("AI_FOUNDRY_SERVICES",),
    "key_vault_name": ("KEY_VAULT_NAME",),
    "key_vault_uri": ("KEY_VAULT_URI",),
    "entra_auth_enabled": ("ENTRA_AUTH_ENABLED",),
    "entra_client_id": ("ENTRA_CLIENT_ID", "AZURE_CLIENT_ID"),
    "entra_tenant_id": ("ENTRA_TENANT_ID", "AZURE_TENANT_ID"),
    "entra_audience": ("ENTRA_AUDIENCE", "AZURE_AUDIENCE"),
    "cosmos_db_account_name": ("COSMOS_DB_ACCOUNT_NAME",),
    "event_hub_name": ("EVENT_HUB_NAME",),
    "environment": ("AZURE_ENV_NAME",),
    "allowed_models": ("VALIDATION_ALLOWED_MODELS",),
}
_JSON_KEYS = {
    "llm_backends": list, "capabilities": dict, "ai_foundry_services": list,
    "skipped_models": list, "model_aliases": list,
}
_PLACEHOLDER = re.compile(r"REPLACE|<[^>]+>|\$\{[^}]+\}|^(?:your[-_ ].*|changeme|todo|placeholder)$", re.I)

def _boolean(value: Any, label: str) -> bool:
    if isinstance(value, str) and value.lower() in {"true", "false"}:
        return value.lower() == "true"
    if not isinstance(value, bool):
        raise ValidationError(f"{label} must be true or false")
    return value


def _canonical(values: Mapping[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(dict(values))
    for canonical, aliases in _ALIASES.items():
        if canonical not in values:
            for alias in aliases:
                if alias in values and values[alias] is not None and values[alias] != "":
                    result[canonical] = copy.deepcopy(values[alias])
                    break
        for alias in aliases:
            result.pop(alias, None)
    return result


def _decode(value: Any, expected_type: type, label: str) -> Any:
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except json.JSONDecodeError as error:
            raise ValidationError(f"{label} is not valid JSON") from error
    if not isinstance(value, expected_type):
        raise ValidationError(f"{label} must be a {expected_type.__name__}")
    return copy.deepcopy(value)


def _merge(base: Any, explicit: Any) -> Any:
    if isinstance(base, Mapping) and isinstance(explicit, Mapping):
        result = copy.deepcopy(dict(base))
        for key, value in explicit.items():
            result[key] = _merge(result[key], value) if key in result else copy.deepcopy(value)
        return result
    return copy.deepcopy(explicit)


def merge_backends(base: Sequence[Mapping[str, Any]], explicit: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    """Merge by backend ID and model name, preserving provider-specific fields."""
    result = copy.deepcopy(list(base))
    for backend in explicit:
        if not isinstance(backend, Mapping):
            raise ValidationError("Each llm_backends entry must be an object")
        backend_id = backend.get("backendId", backend.get("backend_id"))
        position = next(
            (index for index, item in enumerate(result)
             if backend_id and item.get("backendId", item.get("backend_id")) == backend_id),
            None,
        )
        if position is None:
            result.append(copy.deepcopy(dict(backend)))
            continue
        previous = result[position]
        merged = _merge(previous, backend)
        model_key = "supportedModels" if "supportedModels" in backend else "models"
        if model_key in backend:
            models = copy.deepcopy(previous.get(model_key, []))
            for model in backend[model_key]:
                name = model if isinstance(model, str) else model.get("name", model.get("modelName"))
                existing = next(
                    (index for index, item in enumerate(models)
                     if (item if isinstance(item, str) else item.get("name", item.get("modelName"))) == name),
                    None,
                )
                if existing is None:
                    models.append(copy.deepcopy(model))
                else:
                    models[existing] = _merge(models[existing], model)
            merged[model_key] = models
        result[position] = merged
    return result


@dataclass
class ModelEntry:
    name: str
    backend_id: str
    backend_type: str
    protocol: str | None
    deployment_name: str | None
    version: str | None
    model_format: str | None
    api_version: str | None
    inference_api_version: str | None
    retirement_date: str | None
    session_aware: bool
    session_affinity: dict[str, Any]
    capabilities: tuple[str, ...]
    metadata: dict[str, Any] = field(repr=False)
    backend_metadata: dict[str, Any] = field(repr=False)
    operations_source: str = "inferred"


def infer_model_operations(name: str) -> list[str]:
    """Default assumptions, not a claim that the deployed provider supports them."""
    if not isinstance(name, str) or not name.strip():
        raise ValidationError("Operation inference requires a nonempty model name")
    normalized = name.casefold()
    if "image" in normalized or "flux" in normalized:
        return ["image-generation", "image-edit"]
    if "embedding" in normalized or "text" in normalized:
        return ["embeddings"]
    if "gpt" in normalized:
        return ["chat", "responses"]
    return ["chat"]


class ModelCatalog:
    """Deployed entries, resolved operations and test exclusions, in source order."""

    def __init__(
        self, backends: Sequence[Mapping[str, Any]],
        capabilities: Mapping[str, Any] | None = None,
        allowed_models: Sequence[str] | None = None,
        *, skipped_models: Sequence[str] | None = None, infer_operations: bool = True,
    ):
        if not isinstance(backends, (list, tuple)):
            raise ValidationError("llm_backends must be an array")
        self.backends = copy.deepcopy(list(backends))
        self.capabilities = _decode(capabilities if capabilities is not None else {}, dict, "capabilities")
        self.infer_operations = _boolean(infer_operations, "infer_operations")
        if skipped_models is not None and (
            not isinstance(skipped_models, (list, tuple))
            or any(not isinstance(keyword, str) or not keyword.strip() for keyword in skipped_models)
        ):
            raise ValidationError("skipped_models must be an array of nonempty keyword strings")
        self.skipped_models = tuple(dict.fromkeys(keyword.strip().casefold() for keyword in (skipped_models or [])))
        self.allowed_models = None if allowed_models is None else tuple(allowed_models)
        if self.allowed_models is not None and (
            isinstance(allowed_models, str) or not all(isinstance(name, str) for name in self.allowed_models)
        ):
            raise ValidationError("allowed_models must be an array of model names")
        for name, operations in self.capabilities.items():
            if not isinstance(name, str) or not name:
                raise ValidationError("Capability model names must be nonempty strings")
            self._operations(operations, name)
        self.entries: list[ModelEntry] = []
        seen: set[tuple[str, str]] = set()
        retirement_warnings: set[tuple[str, str]] = set()
        for backend in self.backends:
            if not isinstance(backend, Mapping):
                raise ValidationError("Each llm_backends entry must be an object")
            backend_id = backend.get("backendId", backend.get("backend_id"))
            backend_type = backend.get("backendType", backend.get("backend_type"))
            if (
                not isinstance(backend_id, str) or not backend_id or _PLACEHOLDER.search(backend_id)
                or not isinstance(backend_type, str) or not backend_type or _PLACEHOLDER.search(backend_type)
            ):
                raise ValidationError("Every backend requires backendId and backendType")
            models = backend.get("supportedModels", backend.get("models", []))
            if not isinstance(models, list):
                raise ValidationError(f"Models for backend {backend_id} must be an array")
            for raw in models:
                model = {"name": raw} if isinstance(raw, str) else copy.deepcopy(raw)
                if not isinstance(model, Mapping):
                    raise ValidationError(f"Model in backend {backend_id} must be an object or name")
                name = model.get("name", model.get("modelName", model.get("model_name")))
                if not isinstance(name, str) or not name.strip() or _PLACEHOLDER.search(name):
                    raise ValidationError(f"Backend {backend_id} has a missing/placeholder model name")
                if (backend_id, name) in seen:
                    continue
                seen.add((backend_id, name))
                if name in self.capabilities:
                    operations = self.capabilities[name]
                    operation_source = "override"
                elif model.get("operations") is not None or (
                    isinstance(model.get("capabilities"), (list, tuple))
                    or isinstance(model.get("capabilities"), Mapping)
                    and model["capabilities"].get("operations", model["capabilities"].get("capabilities")) is not None
                ):
                    operations = model["operations"] if model.get("operations") is not None else model["capabilities"]
                    operation_source = "metadata"
                else:
                    operations = infer_model_operations(name) if self.infer_operations else []
                    operation_source = "inferred" if self.infer_operations else "unmapped"
                operations = self._operations(operations, name)
                retired = model.get("retirementDate", model.get("retirement_date"))
                if retired:
                    retirement_key = (name, str(retired))
                    try:
                        is_retired = date.fromisoformat(str(retired)) <= date.today()
                        message = f"Model {name} declares retirement {retired}; still eligible. Verify provider availability."
                    except ValueError:
                        is_retired = True
                        message = f"Model {name} has invalid retirement metadata; verify its retirement date."
                    if is_retired and retirement_key not in retirement_warnings:
                        warnings.warn(message, UserWarning, stacklevel=2)
                        retirement_warnings.add(retirement_key)
                protocol = model.get("protocol", backend.get("protocol"))
                if protocol is not None and not isinstance(protocol, str):
                    raise ValidationError(f"{name}.protocol must be a string or null")
                self.entries.append(ModelEntry(
                    name=name, backend_id=backend_id, backend_type=backend_type,
                    protocol=protocol,
                    deployment_name=model.get("deploymentName", model.get("deployment_name")),
                    version=model.get("modelVersion", model.get("version")),
                    model_format=model.get("modelFormat", model.get("format")),
                    api_version=model.get("apiVersion", backend.get("apiVersion")),
                    inference_api_version=model.get("inferenceApiVersion", backend.get("inferenceApiVersion")),
                    retirement_date=retired,
                    session_aware=_boolean(
                        model.get("sessionAwareModel", model.get("session_aware", False)),
                        f"{name}.sessionAwareModel",
                    ),
                    session_affinity=copy.deepcopy(backend.get("sessionAffinity", {})),
                    capabilities=operations, metadata=dict(model), backend_metadata=copy.deepcopy(dict(backend)),
                    operations_source=operation_source,
                ))

    @staticmethod
    def _operations(value: Any, name: str) -> tuple[str, ...]:
        if isinstance(value, Mapping):
            value = value.get("operations", value.get("capabilities"))
        if not isinstance(value, (list, tuple)) or not all(isinstance(item, str) and item for item in value):
            raise ValidationError(f"Capabilities for {name} must be an array of operation names")
        return tuple(dict.fromkeys(value))

    def models_for(self, operation: str, backend_type: str | None = None) -> list[str]:
        return list(dict.fromkeys(
            entry.name for entry in self.entries
            if self._supports(entry, operation) and not self.is_skipped(entry.name)
            and (backend_type is None or backend_type == entry.backend_type)
            and (self.allowed_models is None or entry.name in self.allowed_models)
        ))

    def operations(self, name: str) -> list[str]:
        """Return resolved operations; explicit lists replace inferred operations."""
        return list(dict.fromkeys(
            operation for entry in self.entries if entry.name == name
            for operation in entry.capabilities
        ))

    @staticmethod
    def _supports(entry: ModelEntry, operation: str) -> bool:
        return operation in entry.capabilities or (
            operation == "streaming" and entry.operations_source == "inferred"
            and "chat" in entry.capabilities
        )

    def skip_reason(self, name: str) -> str:
        matches = [keyword for keyword in self.skipped_models if keyword in name.casefold()]
        if matches:
            return "Matched skipped_models keyword(s): " + ", ".join(matches)
        entries = [entry for entry in self.entries if entry.name == name]
        if entries and all(not entry.capabilities and entry.operations_source in ("override", "metadata")
                           for entry in entries):
            return "Explicit operation mapping disables this model"
        return ""

    def is_skipped(self, name: str) -> bool:
        return bool(self.skip_reason(name))

    def optional_response_retrieval(self, name: str, status: int, body: Any = None) -> bool:
        """Treat GET 404 as optional for every model; preserve mini-specific limits."""
        if status == 404:
            return True
        inferred = any(entry.name == name and entry.operations_source == "inferred"
                       and "responses" in entry.capabilities for entry in self.entries)
        if not inferred or "mini" not in name.casefold():
            return False
        if status in (405, 501):
            return True
        error = body.get("error") if isinstance(body, Mapping) else None
        code = str(error.get("code", "")) if isinstance(error, Mapping) else ""
        return status == 400 and code.casefold() in {
            "operationnotsupported", "unsupported_operation", "unsupportedoperation", "notimplemented",
        }

    def alias_members(
        self, members: Sequence[str], operation: str,
        backend_type: str | None = None, min_members: int = 1,
    ) -> list[str]:
        """Validate alias members sharing an explicit wire protocol across clouds.

        Missing/blank protocols only match within the same backend type. Backend
        pools remain type-specific; this cross-cloud rule applies only to aliases.
        """
        if isinstance(members, str) or not members or len(set(members)) != len(members):
            raise ValidationBlocked("Aliases require distinct deployed member names")
        if isinstance(min_members, bool) or not isinstance(min_members, int) or min_members < 1:
            raise ValidationError("min_members must be a positive integer")
        if len(members) < min_members:
            raise ValidationBlocked(f"Alias requires at least {min_members} distinct members")
        common: set[tuple[str, str]] | None = None
        for name in members:
            self.select(operation, override=name, backend_type=backend_type)
            protocols = {
                ("protocol", entry.protocol) if entry.protocol and entry.protocol.strip()
                else ("backend_type", entry.backend_type)
                for entry in self.entries
                if entry.name == name and self._supports(entry, operation)
                and (backend_type is None or entry.backend_type == backend_type)
            }
            common = protocols if common is None else common & protocols
        if not common:
            raise ValidationBlocked(
                "Alias members have no common explicit wire protocol or same-type unknown protocol. "
                "Annotate backend/model protocol explicitly for cross-cloud aliases."
            )
        return list(members)

    def validate_alias(
        self, members: Sequence[str], operation: str,
        backend_type: str | None = None, min_members: int = 1,
    ) -> list[str]:
        """Equivalent public spelling for alias_members."""
        return self.alias_members(members, operation, backend_type, min_members)

    def select(
        self, operation: str, override: str | None = None,
        backend_type: str | None = None, min_backends: int = 1,
    ) -> str:
        if isinstance(min_backends, bool) or not isinstance(min_backends, int) or min_backends < 1:
            raise ValidationError("min_backends must be a positive integer")
        candidates = self.models_for(operation, backend_type)
        if override is not None:
            if not isinstance(override, str) or not override:
                raise ValidationError("A model override must be a nonempty name")
            candidates = [override] if override in candidates else []
        for name in candidates:
            groups: dict[tuple[str, str | None], set[str]] = {}
            for entry in self.entries:
                if entry.name == name and self._supports(entry, operation) and (
                    backend_type is None or entry.backend_type == backend_type
                ):
                    groups.setdefault((entry.backend_type, entry.protocol), set()).add(entry.backend_id)
            if any(len(members) >= min_backends for members in groups.values()):
                return name
        suffix = f" for override {override!r}" if override is not None else ""
        raise ValidationBlocked(
            f"No eligible deployed model supports {operation!r}{suffix} "
            f"with {min_backends} compatible backend(s). Check deployment/access and supply "
            "VALIDATION_MODEL_CAPABILITIES as {model_name: ['chat', 'responses', ...]}."
        )

    def reconcile(self, discovered: Sequence[Any]) -> dict[str, list[str]]:
        """Describe configuration/discovery drift; do not silently replace either."""
        names = []
        for model in discovered:
            name = model if isinstance(model, str) else model.get("id", model.get("name"))
            if not isinstance(name, str) or not name:
                raise ValidationError("Gateway discovery entry requires a model id/name")
            names.append(name)
        configured = list(dict.fromkeys(entry.name for entry in self.entries))
        return {
            "configured_only": [name for name in configured if name not in names],
            "discovered_only": list(dict.fromkeys(name for name in names if name not in configured)),
            "common": [name for name in configured if name in names],
        }

    def report(self) -> list[dict[str, Any]]:
        return [redact({
            "model": entry.name, "deployment": entry.deployment_name,
            "backend": entry.backend_id, "type": entry.backend_type,
            "protocol": entry.protocol, "operations": entry.capabilities,
            "source": entry.operations_source, "skipped": self.skip_reason(entry.name),
            "retirement": entry.retirement_date,
        }) for entry in self.entries]


@dataclass
class ValidationContext:
    config: dict[str, Any] = field(repr=False)
    account: dict[str, Any] = field(repr=False)
    catalog: ModelCatalog
    provenance: dict[str, str]
    azd_snapshot: dict[str, Any] = field(repr=False)

    @property
    def root(self) -> Path:
        return REPO_ROOT

    @classmethod
    def load(
        cls, overrides: Mapping[str, Any] | None = None,
        environment: str | None = None, from_azd: bool = True,
        *, operation_overrides: Mapping[str, Any] | None = None,
        skipped_models: Sequence[str] | None = None,
    ) -> ValidationContext:
        if overrides is not None and not isinstance(overrides, Mapping):
            raise ValidationError("overrides must be a configuration object")
        if environment is not None and (not isinstance(environment, str) or not environment.strip()):
            raise ValidationError("environment must be a nonempty name")
        snapshot: dict[str, Any] = {}
        if from_azd:
            arguments = ["azd", "env", "get-values", "--output", "json"]
            if environment is not None:
                arguments.extend(["--environment", environment])
            snapshot = _run_json(arguments)
            if not isinstance(snapshot, dict):
                raise ValidationError("azd environment values must be a JSON object")
        config = _canonical(snapshot)
        explicit = _canonical(overrides or {})
        if operation_overrides is not None:
            if not isinstance(operation_overrides, Mapping):
                raise ValidationError("operation_overrides must map model names to operation arrays")
            explicit["capabilities"] = copy.deepcopy(dict(operation_overrides))
        if skipped_models is not None:
            explicit["skipped_models"] = list(skipped_models) if isinstance(skipped_models, (list, tuple)) else skipped_models
        provenance = {key: "azd" for key in config}
        for key, value in explicit.items():
            if key in config and key in {"llm_backends", "capabilities"} and not (
                key == "capabilities" and operation_overrides is not None
            ):
                expected_type = _JSON_KEYS[key]
                base = _decode(config[key], expected_type, key)
                incoming = _decode(value, expected_type, key)
                value = merge_backends(base, incoming) if key == "llm_backends" else _merge(base, incoming)
            config[key] = copy.deepcopy(value)
            provenance[key] = "explicit"
        if environment is not None:
            selected = snapshot.get("AZURE_ENV_NAME")
            if selected and selected != environment:
                raise ValidationError("azd returned values for a different environment")
            config["environment"] = environment
            provenance["environment"] = "explicit"
        for key, default in {
            "llm_backends": [], "capabilities": {}, "ai_foundry_services": [],
            "key_vault_name": "", "key_vault_uri": "", "entra_auth_enabled": False,
            "entra_client_id": "", "entra_tenant_id": "", "entra_audience": "",
            "skipped_models": [], "model_aliases": [], "infer_operations": True,
        }.items():
            if key not in config:
                config[key] = default
                provenance[key] = "default"
        for key, expected_type in _JSON_KEYS.items():
            config[key] = _decode(config[key], expected_type, key)
        gateway_keys = ("resource_group", "location", "subscription_id", "apim_name")
        try:
            utils.require_inputs({
                key: config.get(key) if isinstance(config.get(key), str) else None
                for key in gateway_keys
            })
        except ValueError as error:
            raise ValidationError(f"Missing or placeholder gateway configuration. {error}") from error
        for key in gateway_keys:
            value = config[key]
            config[key] = value.strip()
        for key in ("entra_auth_enabled", "enable_key_vault", "enable_foundry_integration", "enable_entra_auth",
                    "infer_operations"):
            if key in config:
                config[key] = _boolean(config[key], key)
        if config.get("enable_key_vault") and not config.get("key_vault_name"):
            raise ValidationError("Key Vault integration is enabled but key_vault_name is missing")
        if config.get("enable_entra_auth") and not all(config.get(key) for key in ("entra_client_id", "entra_tenant_id")):
            raise ValidationError("Entra integration is enabled but client/tenant coordinates are missing")
        if config.get("enable_foundry_integration"):
            services = config["ai_foundry_services"]
            selected = config.get("foundry_service_name")
            matches = services if not selected else [
                service for service in services if isinstance(service, Mapping)
                and service.get("name", service.get("accountName")) == selected
            ]
            if len(matches) != 1:
                raise ValidationError("Enabled Foundry integration requires exactly one selected AI Foundry service")
        account = _run_json(["az", "account", "show", "--output", "json"])
        if not isinstance(account, dict) or not isinstance(account.get("id"), str) or not account["id"]:
            raise ValidationError("az account show returned no subscription id")
        if account["id"].lower() != config["subscription_id"].lower():
            raise ValidationError("Active Azure subscription differs from configured subscription_id; select it explicitly")
        if config.get("entra_tenant_id") and account.get("tenantId") != config["entra_tenant_id"]:
            raise ValidationError("Active Azure tenant differs from configured entra_tenant_id")
        target_tenant = config.get("tenant_id") or account.get("tenantId")
        if target_tenant:
            utils.require_inputs({"tenant_id": target_tenant})
            if account.get("tenantId") and target_tenant != account["tenantId"]:
                raise ValidationError("Active Azure tenant differs from configured tenant_id")
            config["tenant_id"] = target_tenant
        catalog = ModelCatalog(config["llm_backends"], config["capabilities"], config.get("allowed_models"),
                               skipped_models=config["skipped_models"], infer_operations=config["infer_operations"])
        utils.format_output("Loaded Azure target", {
            "environment": config.get("environment") or environment or "manual",
            "subscription": config["subscription_id"], "subscription name": account.get("name"),
            "tenant": config.get("tenant_id") or account.get("tenantId"),
            "APIM": config["apim_name"], "resource group": config["resource_group"],
            "region": config["location"], "backends": len(config["llm_backends"]),
            "models": len({entry.name for entry in catalog.entries}),
        }, part="INFO")
        return cls(config, copy.deepcopy(account), catalog, provenance, copy.deepcopy(snapshot))

    def report(self) -> dict[str, Any]:
        return redact({
            "configuration": self.config, "provenance": self.provenance,
            "models": self.catalog.report(),
        })


@dataclass
class ValidationResult:
    case: str
    status: str
    required: bool = True
    expected: Any = ""
    actual: Any = ""
    reason: str = ""
    evidence: dict[str, Any] = field(default_factory=dict)


class ValidationRun:
    """One accumulating collector; finish is the verdict, not a print-only step."""

    def __init__(self, name: str):
        self.name = name
        self.results: list[ValidationResult] = []

    def check(
        self, case: str, condition: Any, expected: Any = "", actual: Any = "",
        required: bool = True, **evidence: Any,
    ) -> ValidationResult:
        result = ValidationResult(
            case, "PASS" if bool(condition) else "FAIL", required,
            redact(expected), redact(actual), evidence=redact(evidence),
        )
        self.results.append(result)
        utils.format_output(case, {
            "expected": result.expected, "actual": result.actual,
            "required": required, "evidence": result.evidence,
        }, status=result.status, diagnostic=True)
        return result

    def skip(self, case: str, reason: str) -> ValidationResult:
        if not isinstance(reason, str) or not reason.strip():
            raise ValidationError("SKIP requires a reason")
        result = ValidationResult(case, "SKIP", False, reason=redact(reason))
        self.results.append(result)
        utils.format_output(case, {"reason": result.reason, "required": False}, status="SKIP")
        return result

    def blocked(self, case: str, reason: str, required: bool = True) -> ValidationResult:
        if not isinstance(reason, str) or not reason.strip():
            raise ValidationError("BLOCKED requires a reason")
        result = ValidationResult(case, "BLOCKED", required, reason=redact(reason))
        self.results.append(result)
        utils.format_output(case, {"reason": result.reason, "required": required, "coverage": "BLOCKED"},
                            status="BLOCKED" if required else "WARNING")
        return result

    def finish(self) -> dict[str, Any]:
        counts = {status: 0 for status in ("PASS", "FAIL", "SKIP", "BLOCKED")}
        counts.update(Counter(result.status for result in self.results))
        executed = counts["PASS"] + counts["FAIL"]
        failed = not executed or counts["FAIL"] or any(
            result.status == "BLOCKED" and result.required for result in self.results
        )
        utils.format_output(f"Validation: {self.name}", {
            "executed": executed, "planned": len(self.results), "counts": counts,
        }, status="FAIL" if failed else "WARNING" if counts["SKIP"] or counts["BLOCKED"] else "PASS")
        utils.format_table("Validation cases", [
            {"case": result.case, "status": result.status, "required": result.required,
             "expected": result.expected, "actual": result.reason or result.actual}
            for result in self.results
        ], status="FAIL" if failed else "WARNING" if counts["SKIP"] or counts["BLOCKED"] else "PASS")
        if not executed:
            raise ValidationError("No validation checks executed; empty or entirely skipped/blocked runs cannot pass")
        if counts["FAIL"] or any(result.status == "BLOCKED" and result.required for result in self.results):
            raise ValidationError(f"{redact(self.name)} failed or has blocked required coverage")
        return {"name": redact(self.name), "planned": len(self.results), "executed": executed, **counts}


@dataclass
class HTTPResult:
    status_code: int | None
    json_body: Any = field(repr=False)
    text: str = field(repr=False)
    headers: Mapping[str, str] = field(repr=False)
    content: bytes = field(repr=False)
    duration: float
    error: str | None = None
    json_error: str | None = None
    response: Any = field(default=None, repr=False)

    @property
    def body(self) -> Any:
        return self.json_body

    @property
    def usage(self) -> Any:
        return self.json_body.get("usage", {}) if isinstance(self.json_body, dict) else {}

    @property
    def gateway_headers(self) -> dict[str, str]:
        return {key: value for key, value in self.headers.items() if key.lower().startswith("uaig-")}

    def check(
        self, expected_status: int | Sequence[int] = 200,
        body_check: Callable[[Any], bool] | None = None, require_json: bool = True,
    ) -> bool:
        expected = [expected_status] if isinstance(expected_status, int) else list(expected_status)
        if self.error or self.status_code not in expected:
            return False
        if self.status_code is not None and self.status_code >= 400 and body_check is None:
            return False
        if require_json and (self.json_error or self.json_body is None):
            return False
        if body_check is not None:
            try:
                return bool(body_check(self.json_body if require_json else self.content))
            except (KeyError, IndexError, TypeError, ValueError, AttributeError):
                return False
        return True

    def report(self) -> dict[str, Any]:
        return redact({
            "status_code": self.status_code, "body": self.json_body if self.json_error is None else self.text,
            "headers": self.headers, "duration": self.duration, "error": self.error,
            "json_error": self.json_error,
        })


class RequestTransport:
    """One request per call. One instance owns one independent affinity cookie jar."""

    def __init__(self, session: Any = None, timeout: float = 60):
        if not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or timeout <= 0:
            raise ValidationError("Request timeout must be finite and positive")
        import requests

        self._requests = requests
        self.session = session if session is not None else requests.Session()
        if session is None:
            adapter = requests.adapters.HTTPAdapter(max_retries=0)
            self.session.mount("http://", adapter)
            self.session.mount("https://", adapter)
        elif isinstance(session, requests.Session):
            if any(adapter.max_retries.total not in (0, False) for adapter in session.adapters.values()):
                raise ValidationError("Injected sessions must disable implicit retries")
        self.timeout = timeout

    def request(self, method: str, url: str, **kwargs: Any) -> HTTPResult:
        if kwargs.get("stream"):
            raise ValidationError("Use explicit streaming consumption/validation rather than buffered transport")
        kwargs.setdefault("timeout", self.timeout)
        timeouts = kwargs["timeout"] if isinstance(kwargs["timeout"], tuple) else (kwargs["timeout"],)
        if not timeouts or any(
            isinstance(value, bool) or not isinstance(value, (int, float))
            or not math.isfinite(value) or value <= 0 for value in timeouts
        ):
            raise ValidationError("Each request timeout must be finite and positive")
        kwargs.setdefault("allow_redirects", False)
        payload = kwargs.get("json")
        utils.format_output("HTTP request", {
            "method": method, "endpoint": url,
            "model": (payload.get("model") if isinstance(payload, Mapping) else None)
                     or (kwargs.get("headers") or {}).get("x-ai-model"),
            "query": kwargs.get("params", {}), "timeout seconds": kwargs["timeout"],
        }, part="INFO")
        started = time.perf_counter()
        try:
            response = self.session.request(method, url, **kwargs)
        except self._requests.exceptions.RequestException as error:
            utils.format_result("HTTP request failed", status="ERROR",
                                error_type=type(error).__name__, details=str(error))
            return HTTPResult(
                None, None, "", {}, b"", time.perf_counter() - started,
                error=redact(str(error)),
            )
        body = None
        json_error = None
        try:
            body = response.json()
        except (ValueError, TypeError) as error:
            json_error = f"Response is not valid JSON ({type(error).__name__})"
        result = HTTPResult(
            response.status_code, body, response.text,
            self._requests.structures.CaseInsensitiveDict(response.headers),
            response.content, time.perf_counter() - started,
            json_error=json_error, response=response,
        )
        utils.format_http_response(response, elapsed=result.duration,
                                   body=body if json_error is None else result.text,
                                   parse_error=json_error)
        return result

    def close(self) -> None:
        self.session.close()

    def __enter__(self) -> RequestTransport:
        return self

    def __exit__(self, *_: Any) -> None:
        self.close()


def valid_chat(body: Any) -> bool:
    try:
        choices = body["choices"]
        return bool(choices) and all(
            isinstance(choice["message"]["content"], str) and bool(choice["message"]["content"].strip())
            for choice in choices
        )
    except (KeyError, TypeError):
        return False


def valid_embeddings(body: Any) -> bool:
    try:
        vectors = [item["embedding"] for item in body["data"]]
        return bool(vectors) and len({len(vector) for vector in vectors}) == 1 and all(
            bool(vector) and all(
                isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
                for value in vector
            ) for vector in vectors
        )
    except (KeyError, TypeError):
        return False


def valid_response(body: Any) -> bool:
    if (
        not isinstance(body, dict) or not isinstance(body.get("id"), str) or not body["id"]
        or body.get("status") != "completed" or not isinstance(body.get("output"), list)
    ):
        return False
    return any(
        isinstance(item, dict) and isinstance(item.get("content"), list) and any(
            isinstance(content, dict) and isinstance(content.get("text"), str)
            and bool(content["text"].strip())
            for content in item["content"]
        ) for item in body["output"]
    )
