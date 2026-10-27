"""Reusable Foundry agents and bounded SDK-only HR conversation execution."""

from __future__ import annotations

import json
import hashlib
import math
import re
import time
from collections.abc import Mapping, Sequence
from email.utils import parsedate_to_datetime
from typing import Any, NoReturn
from uuid import uuid4

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import AgentDefinition, AgentVersionDetails
from azure.core.exceptions import ResourceNotFoundError
from openai import APIError, APIStatusError

if __package__:
    from . import utils
    from .validationtools import ValidationError, ValidationRun, redact
else:
    import utils
    from validationtools import ValidationError, ValidationRun, redact


def ensure_agent_version(project: AIProjectClient, agent_name: str,
                         definition: AgentDefinition) -> tuple[AgentVersionDetails, bool]:
    """Reuse the latest definition; publish changed definitions under one name."""
    desired = definition.as_dict()
    fingerprint = hashlib.sha256(
        json.dumps(desired, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    try:
        latest = project.agents.get(agent_name=agent_name).versions.latest
    except ResourceNotFoundError:
        latest = None
    if latest is not None and (
        (latest.metadata or {}).get("validation_definition_sha256") == fingerprint
        or latest.definition.as_dict() == desired
    ):
        utils.format_result("Reused Foundry agent version", agent=agent_name, version=latest.version)
        return latest, False
    agent = project.agents.create_version(
        agent_name=agent_name, definition=definition,
        metadata={"validation_definition_sha256": fingerprint},
    )
    utils.format_result("Published Foundry agent version", agent=agent_name, version=agent.version)
    return agent, True


def _seconds(value: Any) -> float | None:
    try:
        seconds = float(value)
    except (TypeError, ValueError, OverflowError):
        return None
    return seconds if math.isfinite(seconds) and seconds >= 0 else None


def _relative_seconds(value: Any) -> float | None:
    numeric = _seconds(value)
    if numeric is not None:
        return numeric
    text = str(value).strip().lower()
    parts = re.findall(r"(\d+(?:\.\d+)?)(ms|s|m|h)", text)
    if not parts or "".join(number + unit for number, unit in parts) != text:
        return None
    seconds = sum(float(number) * {"ms": .001, "s": 1, "m": 60, "h": 3600}[unit]
                  for number, unit in parts)
    return seconds if math.isfinite(seconds) else None


def retry_delay(headers: Mapping[str, Any] | None, now: float | None = None) -> float | None:
    """Return the longest valid server delay in seconds, or None without a hint.

    Retry-After accepts seconds or an HTTP date; retry-after-ms is milliseconds.
    x-ratelimit-reset-tokens accepts relative seconds, including SDK-style 1m30s.
    Conflicting valid hints are honored conservatively rather than retrying early.
    """
    values = {str(key).lower(): value for key, value in (headers or {}).items()}
    delays = []
    retry_after = values.get("retry-after")
    if retry_after is not None:
        seconds = _seconds(retry_after)
        if seconds is None:
            try:
                date = parsedate_to_datetime(str(retry_after))
                seconds = max(0.0, date.timestamp() - (time.time() if now is None else now))
            except (TypeError, ValueError, OverflowError):
                seconds = None
        if seconds is not None and math.isfinite(seconds):
            delays.append(seconds)
    milliseconds = _seconds(values.get("retry-after-ms"))
    if milliseconds is not None:
        delays.append(milliseconds / 1000)
    reset = _relative_seconds(values.get("x-ratelimit-reset-tokens"))
    if reset is not None:
        delays.append(reset)
    return max(delays) if delays else None


def _mapping(value: Any, label: str) -> dict[str, Any]:
    if isinstance(value, Mapping):
        return dict(value)
    dump = getattr(value, "model_dump", None)
    if callable(dump):
        data = dump()
        if isinstance(data, dict):
            return data
    raise ValidationError(f"{label} did not return an SDK object or dictionary.")


def _error_nodes(value: Any):
    """Inspect structured errors, including JSON embedded in an SDK error message."""
    yield value
    if isinstance(value, Mapping):
        for item in value.values():
            yield from _error_nodes(item)
    elif isinstance(value, (list, tuple)):
        for item in value:
            yield from _error_nodes(item)
    elif isinstance(value, str) and value.lstrip().startswith(("{", "[")):
        try:
            nested = json.loads(value)
        except json.JSONDecodeError:
            return
        yield from _error_nodes(nested)


def _message_retry_delay(error: Any) -> float | None:
    part = (r"\d+(?:\.\d+)?\s*(?:milliseconds?|msecs?|ms|seconds?|secs?|s|"
            r"minutes?|mins?|m|hours?|hrs?|h)(?![a-z])")
    pattern = rf"\b(?:retry|try again)\s+(?:after|in)\s+((?:{part}\s*)+)"
    delays = []
    for node in _error_nodes(error):
        if not isinstance(node, str):
            continue
        for duration in re.findall(pattern, node, re.I):
            seconds = 0.0
            for number, unit in re.findall(r"(\d+(?:\.\d+)?)\s*([a-z]+)", duration, re.I):
                unit = unit.lower()
                factor = .001 if unit.startswith(("ms", "milli")) else {
                    "s": 1, "m": 60, "h": 3600,
                }[unit[0]]
                seconds += float(number) * factor
            if math.isfinite(seconds):
                delays.append(seconds)
    return max(delays) if delays else None


def _failure_kind(error: Any, status_code: int | None = None) -> str:
    nodes = list(_error_nodes(error))
    text = " ".join(str(node) for node in nodes if isinstance(node, (str, int)))
    normalized = re.sub(r"[^a-z0-9]", "", text.lower())
    if ("insufficientquota" in normalized or "quotaexceeded" in normalized
            or "quotaexhausted" in normalized or "billinghardlimit" in normalized
            or re.search(r"(?:exhausted|exceeded|out of|insufficient).{0,40}quota"
                         r"|quota.{0,40}(?:exhausted|exceeded|depleted)", text, re.I)):
        return "quota"
    statuses = [node.get(key) for node in nodes if isinstance(node, Mapping)
                for key in ("status", "status_code", "statusCode")]
    if status_code == 429 or (
        status_code is None and (
            any(str(status) == "429" for status in statuses)
            or "ratelimitexceeded" in normalized
            or re.search(r"(?:status(?:_code)?|http)\D{0,12}429\b", text, re.I)
        )
    ):
        return "throttle"
    return "other"


def _error_headers(error: Any) -> dict[str, Any]:
    headers = {}
    for node in _error_nodes(error):
        if isinstance(node, Mapping):
            for key, value in node.items():
                if str(key).lower() in {
                    "retry-after", "retry-after-ms", "x-ratelimit-reset-tokens",
                }:
                    headers[str(key).lower()] = value
    return headers


def _record_failure(run: ValidationRun, case: str, message: str, *,
                    turn: int | None = None, **evidence: Any) -> None:
    safe_message, safe_evidence = redact(message), redact(evidence)
    run.check(case, False, expected="A completed Foundry SDK response with assistant text",
              actual=safe_message, **safe_evidence)
    if turn is not None:
        utils.format_chat_message("assistant", safe_message, turn=turn, status="error",
                                  details=safe_evidence)


def _fail(run: ValidationRun, case: str, message: str, *,
          turn: int | None = None, **evidence: Any) -> NoReturn:
    _record_failure(run, case, message, turn=turn, **evidence)
    raise ValidationError(redact(message))


def _sdk_error(error: APIError) -> dict[str, Any]:
    evidence = {"error_type": type(error).__name__, "message": str(error),
                "body": getattr(error, "body", None)}
    if isinstance(error, APIStatusError):
        evidence["status_code"] = error.status_code
    return evidence


def _output(data: dict[str, Any]) -> tuple[str, dict[str, Any], list[dict], list[dict]]:
    response_id = data.get("id")
    if not isinstance(response_id, str) or not response_id.strip():
        raise ValidationError("Foundry response is missing a response ID.")
    output = data.get("output")
    if not isinstance(output, list) or not output:
        raise ValidationError("Foundry response is missing output items.")
    texts, calls, citations = [], [], []
    seen_urls = set()

    def cite(value: Any) -> None:
        if not isinstance(value, Mapping):
            return
        url = value.get("url")
        if isinstance(url, str) and url.strip() and url not in seen_urls:
            title = value.get("title")
            citations.append({"title": title if isinstance(title, str) else "", "url": url})
            seen_urls.add(url)

    for item in output:
        if not isinstance(item, Mapping):
            continue
        if item.get("type") == "web_search_call":
            calls.append(dict(item))
        if item.get("type") != "message" or item.get("role") != "assistant":
            continue
        content = item.get("content")
        if not isinstance(content, list):
            continue
        for part in content:
            if not isinstance(part, Mapping) or part.get("type") != "output_text":
                continue
            text = part.get("text")
            if isinstance(text, str) and text.strip():
                texts.append(text)
                annotations = part.get("annotations")
                if isinstance(annotations, list):
                    for annotation in annotations:
                        if isinstance(annotation, Mapping) and annotation.get("type") == "url_citation":
                            cite(annotation.get("url_citation", annotation))
    if not texts:
        raise ValidationError("Foundry response has no nonempty assistant output_text; "
                              "refusals and tool calls alone are not successful replies.")
    for call in calls:
        action = call.get("action")
        sources = action.get("sources", []) if isinstance(action, Mapping) else []
        if isinstance(sources, list):
            for source in sources:
                cite(source)
    usage = data.get("usage")
    return "\n".join(texts), _mapping(usage, "Response usage") if usage is not None else {}, calls, citations


def run_hr_conversation(client: Any, agent_name: str, agent_version: str,
                        prompts: Sequence[str], run: ValidationRun, *,
                        max_wait_seconds: float = 120,
                        fallback_wait_seconds: float = 60,
                        conversation_id: str | None = None,
                        transcript: list[dict] | None = None) -> list[dict]:
    """Run exactly 10 turns, retrying only responses.create once after a throttle.

    The caller must obtain the SDK client with project.get_openai_client(max_retries=0).
    The existing agent is referenced by name/version; no model or raw HTTP substitute
    is used. Failures record a required FAIL before aborting the remaining turns.
    Explicit relative retry delays in error messages are honored alongside headers;
    the longest server hint wins, and a hint exceeding the wait cap aborts the run.
    Supply an existing conversation ID to retain cleanup ownership on failure.
    An optional empty transcript list is populated incrementally and returned.
    Returned records and displayed SDK evidence are credential-redacted.
    """
    invalid = None
    if (not isinstance(prompts, Sequence) or isinstance(prompts, (str, bytes))
            or len(prompts) != 10
            or any(not isinstance(prompt, str) or not prompt.strip() for prompt in prompts)):
        invalid = "Provide exactly 10 nonempty scripted user prompts."
    elif any(not isinstance(value, str) or not value.strip()
             for value in (agent_name, agent_version)):
        invalid = "Provide the existing Foundry agent name and version as nonempty strings."
    elif any(isinstance(value, bool) or not isinstance(value, (int, float))
             or not math.isfinite(value) or value <= 0
             for value in (max_wait_seconds, fallback_wait_seconds)):
        invalid = "max_wait_seconds and fallback_wait_seconds must be finite positive seconds."
    elif getattr(client, "max_retries", None) != 0:
        invalid = "Disable invisible SDK retries: use project.get_openai_client(max_retries=0)."
    elif conversation_id is not None and (
        not isinstance(conversation_id, str) or not conversation_id.strip()
    ):
        invalid = "conversation_id must be a nonempty SDK conversation ID when supplied."
    elif transcript is not None and (not isinstance(transcript, list) or transcript):
        invalid = "transcript must be an empty list when supplied; completed turns are never replayed."
    if invalid:
        _fail(run, "hr/configuration", invalid)

    try:
        if conversation_id is None:
            conversation = _mapping(client.conversations.create(), "Conversation creation")
            conversation_id = conversation.get("id")
            if not isinstance(conversation_id, str) or not conversation_id.strip():
                raise ValidationError("Foundry SDK conversation creation returned no conversation ID.")
    except APIError as error:
        _fail(run, "hr/conversation", "Foundry SDK conversation creation failed; no retries.",
              sdk_error=_sdk_error(error))
    except ValidationError as error:
        _fail(run, "hr/conversation", str(error))
    except Exception as error:
        _record_failure(run, "hr/conversation", "Unexpected SDK conversation creation error; "
                        "no retries.", error_type=type(error).__name__, details=str(error))
        raise

    if transcript is None:
        transcript = []
    for turn, prompt in enumerate(prompts, start=1):
        case = f"hr/turn-{turn}"
        idempotency_key = f"hr-turn-{turn}-{uuid4().hex}"
        attempts = []
        utils.format_chat_message("user", redact(prompt), turn=turn)
        try:
            client.conversations.items.create(
                conversation_id=conversation_id,
                items=[{"type": "message", "role": "user", "content": prompt}],
            )
        except APIError as error:
            _fail(run, case, "Appending the user message failed; it will not be repeated. "
                  "Start a new conversation after resolving the SDK error.",
                  turn=turn, sdk_error=_sdk_error(error), retries=0)
        except Exception as error:
            _record_failure(run, case, "Unexpected user-message SDK error; no retries.",
                            turn=turn, error_type=type(error).__name__, details=str(error), retries=0)
            raise

        for attempt in range(2):
            headers, status_code, failure = {}, None, None
            try:
                response = client.responses.create(
                    conversation=conversation_id,
                    extra_body={"agent_reference": {
                        "name": agent_name, "type": "agent_reference", "version": agent_version,
                    }},
                    extra_headers={"Idempotency-Key": idempotency_key},
                )
            except APIStatusError as error:
                failure = _sdk_error(error)
                status_code = error.status_code
                headers = dict(error.response.headers)
            except APIError as error:
                _fail(run, case, "Foundry response SDK request failed; only rate limits are retried.",
                      turn=turn, sdk_error=_sdk_error(error), retries=attempt, attempts=attempts)
            except Exception as error:
                _record_failure(run, case, "Unexpected Foundry response SDK error; no retries.",
                                turn=turn, error_type=type(error).__name__, details=str(error),
                                retries=attempt, attempts=attempts)
                raise
            else:
                try:
                    data = _mapping(response, "Foundry response")
                except ValidationError as error:
                    _fail(run, case, str(error), turn=turn, retries=attempt, attempts=attempts)
                if data.get("status") != "completed" or data.get("error") is not None:
                    failure = data
                    headers = _error_headers(data)
                else:
                    try:
                        assistant, usage, calls, citations = _output(data)
                    except ValidationError as error:
                        _fail(run, case, str(error), turn=turn, sdk_response=data,
                              retries=attempt, attempts=attempts)
                    record = redact({
                        "turn": turn, "user": prompt, "assistant": assistant,
                        "conversation_id": conversation_id, "response_id": data["id"], "usage": usage,
                        "web_search_calls": calls, "citations": citations, "retries": attempt,
                    })
                    transcript.append(record)
                    evidence = redact({"conversation_id": conversation_id, "sdk_response": data,
                                       "usage": usage, "web_search_calls": calls,
                                       "retries": attempt, "attempts": attempts})
                    utils.format_chat_message("assistant", record["assistant"], turn=turn,
                                              status="success", citations=record["citations"],
                                              details=evidence)
                    if attempt:
                        utils.format_output(
                            f"HR turn {turn} succeeded after one rate-limit retry",
                            {"response_id": record["response_id"], "retries": 1},
                            status="success",
                        )
                    run.check(case, True, expected="Completed Foundry SDK assistant reply",
                              actual=record["response_id"], **evidence)
                    break

            kind = _failure_kind(failure, status_code)
            attempts.append(redact({"attempt": attempt + 1, "sdk_error": failure}))
            if kind == "quota":
                _fail(run, case, "Foundry quota is exhausted or insufficient; no retry. "
                      "Increase/restore quota or billing capacity before starting a new conversation.",
                      turn=turn, sdk_error=failure, retries=attempt, attempts=attempts)
            if kind != "throttle":
                _fail(run, case, "Foundry response failed or is not completed; this is not a "
                      "retryable token rate limit. Resolve the SDK error before rerunning.",
                      turn=turn, sdk_error=failure, retries=attempt, attempts=attempts)
            if attempt:
                _fail(run, case, "Foundry rate limit persists after the single permitted retry. "
                      "Wait for capacity or increase the token limit before starting a new run.",
                      turn=turn, sdk_error=failure, retries=1, attempts=attempts)

            delay = retry_delay(headers)
            message_delay = _message_retry_delay(failure)
            if message_delay is not None:
                delay = max(delay if delay is not None else 0, message_delay)
            fallback = delay is None
            if fallback:
                delay = fallback_wait_seconds
                utils.format_chat_message(
                    "assistant", f"Token rate limit: no usable reset hint was returned. "
                    f"Using the configured fallback wait of {delay:g} seconds.",
                    turn=turn, status="warning", details=redact({"sdk_error": failure}),
                )
            if delay > max_wait_seconds:
                _fail(run, case, f"Rate-limit wait of {delay:g} seconds exceeds max_wait_seconds="
                      f"{max_wait_seconds:g}; refusing to retry prematurely. Increase the wait cap "
                      "or wait for capacity before starting a new conversation.",
                      turn=turn, sdk_error=failure, retries=0, attempts=attempts,
                      required_wait_seconds=delay)
            attempts[-1].update(wait_seconds=delay, fallback=fallback)
            utils.format_chat_message(
                "assistant", f"Token rate limit: sleeping {delay:g} seconds, then retrying "
                "responses.create once. The user message will not be appended again.",
                turn=turn, status="warning",
                details=redact({"sdk_error": failure, "wait_seconds": delay, "retry": "1 of 1"}),
            )
            time.sleep(delay)
    return transcript
