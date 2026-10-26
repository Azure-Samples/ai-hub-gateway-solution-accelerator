"""Small contract adapters shared by the PII, JWT, publish, image and affinity labs.

These helpers do not deploy resources or discover credentials implicitly. Definitions,
parameter previews, deployments and feature requests remain visible in the notebooks.
"""

import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape


def policy_xml(source):
    """Escape APIM C# attributes and body/trace text without changing structure."""
    source = re.sub(
        r'([\w:-]+)="(.*?)"(?=\s*(?:/?>|[\w:-]+="))',
        lambda match: match[1] + '="' + escape(
            match[2], {'"': "&quot;"}
        ) + '"',
        source, flags=re.DOTALL,
    )
    source = re.sub(
        r"(<(set-body|message|metadata)(?:\s[^>]*?)?(?<!/)>)(.*?)(</\2>)",
        lambda match: match[1] + escape(match[3]) + match[4],
        source, flags=re.DOTALL,
    )
    ET.fromstring(source)
    return source


def completion_text(data):
    """Return usable completion text, or empty text for a malformed success body."""
    if not isinstance(data, dict):
        return ""
    choices = data.get("choices")
    if not isinstance(choices, list) or not choices or not isinstance(choices[0], dict):
        return ""
    message = choices[0].get("message")
    content = message.get("content") if isinstance(message, dict) else None
    return content if isinstance(content, str) else ""


def access_parameters(context, apim, contract, policy, *, code="LLM",
                      api_names=None, key_vault=None, service_options=None):
    """Build the unchanged access-contract template's parameter shape."""
    coordinates = {
        "subscriptionId": context.config["subscription_id"],
        "resourceGroupName": context.config["resource_group"],
        "name": apim.apim_resource_name,
    }
    use_vault = bool(contract.get("use_keyvault", False))
    if use_vault:
        required = ("subscriptionId", "resourceGroupName", "name")
        if not isinstance(key_vault, dict) or any(
            not isinstance(key_vault.get(field), str)
            or not key_vault[field].strip()
            or "REPLACE" in key_vault[field].upper()
            or key_vault[field].lower() == "placeholder"
            for field in required
        ):
            raise ValueError("Enabled Key Vault integration requires explicit vault coordinates.")
    service = {
        "code": code,
        "endpointSecretName": contract.get("endpoint_secret", ""),
        "apiKeySecretName": contract["apikey_secret"],
        "policyXml": policy,
        **(service_options or {}),
    }
    return {
        "apim": coordinates,
        "keyVault": key_vault or coordinates,
        "useTargetAzureKeyVault": use_vault,
        "useCase": {
            "businessUnit": contract["business_unit"],
            "useCaseName": contract["use_case_name"],
            "environment": contract["environment"],
        },
        "apiNameMapping": {
            code: api_names if api_names is not None else [
                "universal-llm-api", "azure-openai-api", "unified-ai-api",
            ],
        },
        "services": [service],
        "productTerms": contract.get("description", ""),
        "useTargetFoundry": False,
    }


def contract_identity(outputs, preexisting_products, owned_products):
    """Use authoritative output IDs; only record a product absent before this run."""
    products = outputs.get("products", {}).get("value", [])
    subscriptions = outputs.get("subscriptions", {}).get("value", [])
    if len(products) != 1 or len(subscriptions) != 1:
        raise ValueError("Expected one product and one subscription in contract outputs.")
    product_id = products[0]["productId"]
    subscription = subscriptions[0]
    if subscription.get("productId") != product_id or not subscription.get("name"):
        raise ValueError("Contract product/subscription outputs are inconsistent.")
    if product_id not in preexisting_products:
        owned_products.add(product_id)
    return product_id, subscription["name"]


def cleanup_products(apim, owned_products, *, enabled=False):
    """Preview or remove only products positively recorded as newly created."""
    candidates = sorted(owned_products)
    print(f"Current run's owned products: {candidates}; cleanup enabled: {enabled}")
    if enabled:
        for product_id in candidates:
            apim.client.product.delete(
                resource_group_name=apim.resource_group_name,
                service_name=apim.apim_resource_name,
                product_id=product_id,
                if_match="*",
                delete_subscriptions=True,
            )
            owned_products.remove(product_id)


def save_manifest(run_dir, context, apim, owned_products):
    """Persist only noncredential coordinates, artifacts and established ownership."""
    run_dir = Path(run_dir)
    manifest = {
        "scenario": run_dir.parent.name,
        "run_id": run_dir.name,
        "environment": context.config.get("environment"),
        "resource_group": context.config["resource_group"],
        "subscription_id": context.config["subscription_id"],
        "apim_name": apim.apim_resource_name,
        "models": context.catalog.report(),
        "artifacts": [str(path.relative_to(run_dir)) for path in run_dir.rglob("*.bicepparam")],
        "owned_products": sorted(owned_products),
        "cleanup_enabled_by_default": False,
        "shared_backend_changes_retained": True,
    }
    path = run_dir / "manifest.json"
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Sanitized run manifest:", path)
    return path
