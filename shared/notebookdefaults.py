"""Complete deployment inputs for the provisioning validation notebooks.

Deployment inventory is never filtered by test-operation or skip preferences.
An optional source file is authoritative; otherwise the selected azd snapshot
and its optional template settings provide the complete backend source.
"""

from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import re
from typing import Any

if __package__:
    from . import utils
    from .consumerhelpers import complete_backend_parameters
    from .validationtools import ModelCatalog
else:
    import utils
    from consumerhelpers import complete_backend_parameters
    from validationtools import ModelCatalog


_GLOBALS = (
    "apimManagedIdentity", "configureCircuitBreaker", "circuitBreakerDefaults",
    "configureSessionAffinity", "sessionAffinityDefaults", "awsRegion",
    "anthropicVersion", "keyVaultName",
)


def _decoded(value: Any) -> Any:
    if isinstance(value, str):
        try:
            return json.loads(value)
        except json.JSONDecodeError:
            pass
    return value


def _value(values: dict, name: str) -> Any:
    snake = re.sub(r"(?<!^)(?=[A-Z])", "_", name)
    for key in (name, snake, snake.upper()):
        if key in values:
            return _decoded(values[key])
    return None


def backend_source(context, apim, source_file=None, template_options=None):
    """Return a deep, validated source object without removing any deployment.

    Flat JSON and ARM parameter JSON are accepted as explicit source overrides.
    Missing identity metadata is resolved from the APIM SDK; multiple assigned
    identities require an explicit choice rather than guessing.
    """
    if source_file:
        source = json.loads(Path(source_file).read_text(encoding="utf-8"))
        if "parameters" in source:
            source = {key: value["value"] for key, value in source["parameters"].items()}
    else:
        source = {
            "llmBackendConfig": deepcopy(context.config["llm_backends"]),
            "modelAliases": deepcopy(context.config.get("model_aliases", [])),
        }
        settings = {**context.azd_snapshot, **context.config}
        for name in _GLOBALS:
            value = _value(settings, name)
            if value is not None:
                source[name] = value
        for key in ("LLM_BACKEND_TEMPLATE_OPTIONS", "backend_template_options"):
            options = _decoded(settings.get(key, {}))
            if not isinstance(options, dict):
                raise ValueError(f"{key} must be a template-option object.")
            source.update(deepcopy(options))
    if template_options:
        source.update(deepcopy(template_options))
    source.setdefault("modelAliases", [])
    source["apim"] = {
        "subscriptionId": context.config["subscription_id"],
        "resourceGroupName": context.config["resource_group"],
        "name": apim.apim_resource_name,
    }
    if not source.get("apimManagedIdentity"):
        service = apim.client.api_management_service.get(
            resource_group_name=context.config["resource_group"],
            service_name=apim.apim_resource_name,
        )
        identity = getattr(service, "identity", None)
        identities = getattr(identity, "user_assigned_identities", None) or {}
        if len(identities) != 1:
            raise ValueError(
                "APIM needs one user-assigned identity or explicit "
                "backend_template_options.apimManagedIdentity coordinates."
            )
        resource_id = next(iter(identities))
        match = re.fullmatch(
            r"/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/"
            r"Microsoft\.ManagedIdentity/userAssignedIdentities/([^/]+)",
            resource_id, re.IGNORECASE,
        )
        if not match:
            raise ValueError("APIM returned an invalid user-assigned identity resource ID.")
        source["apimManagedIdentity"] = dict(
            zip(("subscriptionId", "resourceGroupName", "name"), match.groups())
        )
    utils.require_inputs({
        "routing.llmBackendConfig": True if source.get("llmBackendConfig") else None,
        **{f"routing.apimManagedIdentity.{key}": source["apimManagedIdentity"].get(key)
           for key in ("subscriptionId", "resourceGroupName", "name")},
    })
    return complete_backend_parameters(source, [], confirmed_complete=True)


def source_catalog(context, source):
    """Rebuild from the authoritative complete inventory with test preferences."""
    return ModelCatalog(
        source["llmBackendConfig"], context.config["capabilities"],
        context.config.get("allowed_models"),
        skipped_models=context.config.get("skipped_models", []),
        infer_operations=context.config.get("infer_operations", True),
    )
