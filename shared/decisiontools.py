"""Native Decision request/response evidence for the validation notebook."""

import json
import math
import re
from copy import deepcopy
from pathlib import Path
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET
from xml.sax.saxutils import quoteattr

if __package__:
    from . import utils
else:
    import utils

if __package__:
    from .validationtools import ModelCatalog, infer_model_operations
else:
    from validationtools import ModelCatalog, infer_model_operations


ROUTES = {
    "decisions": ("/v1/decisions", "/openai/v1/decisions"),
    "systemone": ("/providers/microsoft/v1/systemone",),
}
DEFAULT_DECISION_MODELS = {"decisions": "gpt-6-luna", "systemone": "decision-1"}


def live_decision_catalog(contract, backends, config):
    """Use gateway registrations for selection, never an azd onboarding snapshot."""
    if not isinstance(contract, dict) or not isinstance(contract.get("backends"), list):
        raise ValueError("The live gateway contract must contain a backends array.")
    inventory = {item["name"].casefold() for item in backends}
    definitions = deepcopy(contract["backends"])
    definitions = [item for item in definitions if item["backendId"].casefold() in inventory]
    for backend in definitions:
        for model in backend["supportedModels"]:
            name = model["name"]
            operation = (
                "decisions" if backend["backendType"] in ("ai-foundry", "azure-openai")
                and name.casefold() == DEFAULT_DECISION_MODELS["decisions"]
                else "systemone" if backend["backendType"] == "azure-decision"
                and name.casefold() == DEFAULT_DECISION_MODELS["systemone"] else None
            )
            if operation is not None:
                operations = model.get("operations")
                if operations is None:
                    operations = infer_model_operations(name) if operation == "decisions" else []
                model["operations"] = list(dict.fromkeys([*operations, operation]))
    return ModelCatalog(
        definitions, config.get("capabilities", {}), config.get("allowed_models"),
        skipped_models=config.get("skipped_models", []),
        infer_operations=config.get("infer_operations", True),
    )


def load_local_backend_additions(path, source):
    """Load explicitly configured, target-bound additions; retain adopted records."""
    config = json.loads(Path(path).read_text(encoding="utf-8"))
    target = config.get("apim") if isinstance(config, dict) else None
    if not isinstance(target, dict) or any(
        not isinstance(target.get(key), str)
        or target[key].casefold() != source["apim"][key].casefold()
        for key in ("subscriptionId", "resourceGroupName", "name")
    ):
        raise ValueError("The local Decision backend configuration targets a different APIM service.")
    additions = config.get("backends")
    if not isinstance(additions, list):
        raise ValueError("Local Decision backend additions must contain a backends array.")
    current = {item["backendId"]: item for item in source["llmBackendConfig"]}
    pending = []
    seen = set()
    for backend in additions:
        if not isinstance(backend, dict) or not isinstance(backend.get("backendId"), str) or not backend["backendId"]:
            raise ValueError("Each local Decision backend requires a backendId.")
        name = backend["backendId"]
        if name in seen:
            raise ValueError(f"Local Decision backend additions duplicate {name!r}.")
        seen.add(name)
        if name in current:
            if current[name] != backend:
                raise ValueError(f"Local backend {name!r} differs from the complete source; reconcile it explicitly.")
        else:
            pending.append(deepcopy(backend))
    utils.print_info(f"Loaded target-verified local Decision backend definitions: {sorted(seen)}")
    return pending


def validate_llm_backend_inventory(parameters, contract, backends, pools):
    """Require routing-owned backends without adopting independent APIM services."""
    source_ids = {item["backendId"].casefold(): item["backendId"]
                  for item in parameters["llmBackendConfig"]}
    required = {item["backendId"].casefold(): item["backendId"]
                for item in contract["backends"]}
    contract_pools = {item["poolName"].casefold() for item in contract["pools"]}
    for backend in backends:
        description = backend.get("description") or ""
        if description.casefold().startswith("llm backend:") or backend.get("supportedModels"):
            required[backend["name"].casefold()] = backend["name"]
    for pool in pools:
        description = pool.get("description") or ""
        if (pool["name"].casefold() not in contract_pools
                and not description.casefold().startswith("backend pool for model:")):
            continue
        for service in pool.get("services", []):
            reference = service.get("id")
            match = re.fullmatch(
                r"(?:/subscriptions/[^/]+/resourceGroups/[^/]+/providers/"
                r"Microsoft\.ApiManagement/service/[^/]+)?/backends/([^/]+)",
                reference if isinstance(reference, str) else "", re.IGNORECASE,
            )
            if match is None:
                raise ValueError(f"LLM pool {pool['name']!r} has an invalid backend reference.")
            name = match.group(1)
            required[name.casefold()] = name
    missing = sorted(required[key] for key in required.keys() - source_ids.keys())
    if missing:
        raise ValueError(
            f"The complete source omitted live LLM backends: {missing}. "
            "Supply their full original onboarding configuration before deploying; "
            "backend inventory alone cannot reconstruct credentials or model metadata."
        )
    independent = sorted(item["name"] for item in backends if item["name"].casefold() not in required)
    if independent:
        utils.print_info(
            f"Leaving independent APIM backends outside the LLM routing contract unchanged: {independent}"
        )
    return {source_ids[key] for key in required}


def preserve_live_contract(source, live, *, verified_apim_resource_id=None):
    """Reject predecessor drift and retain live, nonsecret global routing settings."""
    if not isinstance(live, dict) or not isinstance(live.get("backends"), list):
        raise ValueError("A live backend-contract projection is required before onboarding.")
    desired = deepcopy(source)
    target = live.get("apim")
    missing_target = target == {}
    keys = ("subscriptionId", "resourceGroupName", "name")
    if missing_target:
        identity = re.fullmatch(
            r"/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/"
            r"Microsoft\.ApiManagement/service/([^/]+)/?",
            verified_apim_resource_id if isinstance(verified_apim_resource_id, str) else "",
            re.IGNORECASE,
        )
        if identity is None:
            raise ValueError(
                "The live contract has no APIM coordinates. An authenticated APIM "
                "service resource ID is required to verify this legacy contract."
            )
        target = dict(zip(keys, identity.groups()))
    if not isinstance(target, dict) or any(
        not isinstance(target.get(key), str) or not target[key].strip() for key in keys
    ):
        raise ValueError("The live contract has missing or malformed APIM coordinates.")
    if not isinstance(desired.get("apim"), dict) or any(
        not isinstance(desired["apim"].get(key), str)
        or desired["apim"][key].casefold() != target[key].casefold()
        for key in keys
    ):
        raise ValueError("The live contract targets a different APIM service.")
    if missing_target:
        utils.print_warning(
            "The live contract omits APIM coordinates; its target was verified against "
            "the authenticated APIM service resource ID. Backend onboarding will repair the metadata."
        )
    indexed = {backend["backendId"]: backend for backend in desired["llmBackendConfig"]}
    for predecessor in live["backends"]:
        current = indexed.get(predecessor["backendId"])
        if current is None:
            raise ValueError(f"Complete source omitted live backend {predecessor['backendId']}.")
        if {k: v for k, v in current.items() if k != "supportedModels"} != {
            k: v for k, v in predecessor.items() if k != "supportedModels"
        }:
            raise ValueError("Source changes a live backend; reconcile its full contract first.")
        models = {model["name"]: model for model in current["supportedModels"]}
        for model in predecessor["supportedModels"]:
            current_model = models.get(model["name"])
            if current_model == model:
                continue
            operations = current_model.get("operations") if current_model else None
            capability_addition = (
                current["backendType"] in ("ai-foundry", "azure-openai")
                and isinstance(operations, list) and all(isinstance(op, str) for op in operations)
                and "decisions" in operations
                and set(model.get("operations") or []) <= set(operations)
                and {k: v for k, v in current_model.items() if k != "operations"}
                == {k: v for k, v in model.items() if k != "operations"}
            )
            if not capability_addition:
                raise ValueError("Source omitted or changed a predecessor model.")
    if desired["modelAliases"] != live.get("modelAliases"):
        raise ValueError("Source aliases differ from the live contract; reconcile the complete source.")
    for section, enabled, defaults in (
        ("circuitBreaker", "configureCircuitBreaker", "circuitBreakerDefaults"),
        ("sessionAffinity", "configureSessionAffinity", "sessionAffinityDefaults"),
    ):
        value = live.get(section)
        if not isinstance(value, dict) or not isinstance(value.get("enabled"), bool) or not isinstance(value.get("defaults"), dict):
            raise ValueError(f"Live contract has no complete {section} settings.")
        for key, actual in ((enabled, value["enabled"]), (defaults, value["defaults"])):
            if key in desired and desired[key] != actual:
                raise ValueError(f"Source would change shared routing setting {key}.")
            desired[key] = deepcopy(actual)
    for backend in desired["llmBackendConfig"]:
        if backend["backendType"] == "azure-decision":
            endpoint = urlsplit(backend["endpoint"])
            if (endpoint.scheme != "https" or not endpoint.hostname
                    or not endpoint.hostname.endswith(".services.ai.azure.com")
                    or endpoint.username or endpoint.password or endpoint.port
                    or endpoint.path not in ("", "/") or endpoint.query or endpoint.fragment):
                raise ValueError("azure-decision requires an HTTPS Foundry services root, without a provider path.")
    return desired


def build_product_policy_xml(contract):
    models = contract["allowed_models"]
    if not models or any(not isinstance(model, str) or not model.strip() or "," in model for model in models):
        raise ValueError("Decision grants require nonempty, comma-free deployment names.")
    for key in ("requests_per_minute", "request_quota", "quota_period_seconds"):
        value = contract[key]
        if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
            raise ValueError(f"{key} must be a positive integer.")
    if contract["quota_period_seconds"] < 300:
        raise ValueError("APIM request quota renewal periods must be at least 300 seconds.")
    scope = contract.get("counter_scope", "")
    if not isinstance(scope, str) or any(not (c.isascii() and (c.isalnum() or c in "-_")) for c in scope):
        raise ValueError("Counter scope must contain only ASCII letters, digits, hyphens or underscores.")
    counter = '@(context.Subscription.Id' + (f' + ":{scope}"' if scope else "") + ')'
    xml = f"""<policies>
  <inbound>
    <base />
    <include-fragment fragment-id="set-llm-requested-model" />
    <set-variable name="allowedModels" value={quoteattr(",".join(models))} />
    <include-fragment fragment-id="validate-model-access" />
    <rate-limit-by-key calls="{contract['requests_per_minute']}" renewal-period="60" counter-key={quoteattr(counter)} />
    <quota-by-key calls="{contract['request_quota']}" renewal-period="{contract['quota_period_seconds']}" counter-key={quoteattr(counter)} />
    <set-variable name="enableResponseHeaders" value="@(true)" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>"""
    ET.fromstring(xml)
    return xml


def decision_payload(operation, model, *, json_state=False, image_url=None):
    if operation not in ROUTES:
        raise ValueError(f"Unknown Decision operation: {operation}")
    if not isinstance(model, str) or not model.strip():
        raise ValueError("Decision requests require a nonempty model deployment name.")
    if image_url is not None and operation != "decisions":
        raise ValueError("Image input is only documented for OpenAI Decisions.")
    state = "The checkout API returns 500 for every customer."
    if operation == "systemone":
        return {
            "model": model,
            "state": {"ticket": state} if json_state else state,
            "questions": {
                "outage": {"type": "noul", "instructions": "Is the service failing?"},
                "team": {"type": "choice", "instructions": "Which team should handle this?",
                         "criteria": {"engineering": "Errors and outages", "billing": "Invoices"}},
                "severity": {"type": "score", "instructions": "How severe is the issue?",
                             "criteria": ["Cosmetic", "Degraded", "Blocked"]},
            },
        }
    questions = [
        {"name": "outage", "type": "predicate", "instructions": "Is the service failing?"},
        {"name": "team", "type": "choice", "instructions": "Which team should handle this?",
         "choices": [{"value": "engineering", "description": "Errors and outages"},
                     {"value": "billing", "description": "Invoices"}]},
        {"name": "severity", "type": "score", "instructions": "How severe is the issue?",
         "levels": [
             {"label": "Cosmetic", "description": "No loss of functionality."},
             {"label": "Degraded", "description": "Some requests fail but a workaround exists."},
             {"label": "Blocked", "description": "All requests fail with no workaround."},
         ]},
    ]
    evidence = state
    if image_url:
        evidence = [{"role": "user", "content": [
            {"type": "input_text", "text": state},
            {"type": "input_image", "image_url": image_url},
        ]}]
    return {"model": model, "input": evidence, "questions": questions}


def decision_inference_errors(result, payload, operation):
    """Diagnose HTTP failures before interpreting the native success schema."""
    if result.error:
        return [f"Decision request failed: {result.error}"]
    if result.status_code != 200:
        body = result.json_body
        error = body.get("error") if isinstance(body, dict) else None
        message = error.get("message") if isinstance(error, dict) else error
        if not isinstance(message, str) or not message:
            message = body.get("message") if isinstance(body, dict) else None
        message = message or result.json_error or "Backend returned an unsuccessful response."
        region = result.headers.get("x-ms-region", "not reported")
        return [
            f"Backend HTTP {result.status_code} (region: {region}): {message} "
            f"Request model: {payload.get('model')!r}."
        ]
    if result.json_error:
        return [result.json_error]
    return decision_response_errors(result.json_body, payload, operation)


def decision_response_errors(body, payload, operation):
    """Return concrete failures; a refusal is not a successful classification."""
    if operation not in ROUTES:
        raise ValueError(f"Unknown Decision operation: {operation}")
    if not isinstance(body, dict):
        return ["Response must be a JSON object."]
    errors = []
    if not isinstance(body.get("model"), str) or not body["model"]:
        errors.append("Response has no model identity.")
    usage = body.get("usage")
    if not isinstance(usage, dict) or not usage:
        errors.append("Response has no actual token usage.")
    elif any(isinstance(v, bool) or not isinstance(v, int) or v < 0
             for k, v in usage.items() if k.endswith("_tokens")):
        errors.append("Usage token counts must be nonnegative integers.")
    elif any(key not in usage for key in ("input_tokens", "output_tokens")):
        errors.append("Response usage has no input_tokens/output_tokens.")
    elif operation == "decisions" and "total_tokens" not in usage:
        errors.append("Response usage has no total_tokens.")
    questions = payload["questions"]
    answers = body.get("answers")
    if operation == "systemone":
        if not isinstance(answers, dict) or set(answers) != set(questions):
            return errors + ["Microsoft answers must be keyed by every requested question name."]
        pairs = [(name, question, answers[name]) for name, question in questions.items()]
    else:
        if not isinstance(answers, list) or len(answers) != len(questions):
            return errors + ["OpenAI must return one ordered answer per question."]
        pairs = [(q["name"], q, a) for q, a in zip(questions, answers)]

    def finite(value, low, high):
        return (not isinstance(value, bool) and isinstance(value, (int, float))
                and math.isfinite(value) and low <= value <= high)

    for name, question, answer in pairs:
        if not isinstance(answer, dict):
            errors.append(f"{name}: answer must be an object.")
            continue
        if operation == "decisions" and answer.get("name") != name:
            errors.append(f"{name}: answer name/order mismatch.")
        if answer.get("type") == "refusal":
            errors.append(f"{name}: provider refused the question.")
            continue
        kind = question["type"]
        if answer.get("type") != kind:
            errors.append(f"{name}: answer type differs from {kind}.")
            continue
        probability_field = "noul" if kind == "noul" else "probability"
        if kind in ("predicate", "noul") and not finite(answer.get(probability_field), 0, 1):
            errors.append(f"{name}: invalid probability.")
        if kind == "choice":
            choices = (set(question["criteria"]) if operation == "systemone"
                       else {choice["value"] for choice in question["choices"]})
            if answer.get("choice") not in choices:
                errors.append(f"{name}: choice is outside supplied options.")
        if kind == "score":
            levels = question["criteria"] if operation == "systemone" else question["levels"]
            if not finite(answer.get("score"), 0, len(levels) - 1):
                errors.append(f"{name}: score is outside the configured level-index range.")
        if ("confidence" in answer or operation == "decisions" and kind in ("choice", "score")) and not finite(answer.get("confidence"), 0, 1):
            errors.append(f"{name}: invalid confidence.")
        if kind in ("choice", "score"):
            probabilities = answer.get("probabilities")
            values = (list(probabilities.values()) if isinstance(probabilities, dict)
                      else [p.get("probability") if isinstance(p, dict) else None for p in probabilities]
                      if isinstance(probabilities, list) else [])
            expected = len(question.get("criteria", question.get("choices", question.get("levels", []))))
            if len(values) != expected or not all(finite(p, 0, 1) for p in values):
                errors.append(f"{name}: invalid per-option probabilities.")
            if operation == "decisions":
                expected_values = (choices if kind == "choice" else set(range(len(levels))))
                actual_values = ([p.get("value") for p in probabilities if isinstance(p, dict)]
                                 if isinstance(probabilities, list) else [])
                if (len(actual_values) != expected or any(
                    not isinstance(value, (str, bool, int)) for value in actual_values
                ) or set(actual_values) != expected_values):
                    errors.append(f"{name}: OpenAI probability entries must identify every configured option.")
    return errors
