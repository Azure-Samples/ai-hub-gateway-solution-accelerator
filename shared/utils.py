import json, os, subprocess, time, traceback
import html
import re
import warnings
import sys
from urllib.parse import urlsplit
from contextlib import contextmanager
from contextvars import ContextVar
from collections.abc import Mapping
from typing import Any, Callable, Generator

# Define ANSI escape code constants vor clarity in the print commands below
RESET_FORMATTING = "\x1b[0m"
BOLD_BLUE = "\x1b[1;34m"
BOLD_RED = "\x1b[1;31m"
BOLD_GREEN = "\x1b[1;32m"
BOLD_YELLOW = "\x1b[1;33m"


_OUTPUT_STEPS: ContextVar[tuple[list[str], ...]] = ContextVar("output_steps", default=())
_VERBOSE_OUTPUT: ContextVar[bool] = ContextVar("verbose_output", default=False)
_UNSET_OUTPUT = object()
_OUTPUT_STYLES = {
    "INFO": ("#2563eb", BOLD_BLUE),
    "SUCCESS": ("#15803d", BOLD_GREEN),
    "PASS": ("#15803d", BOLD_GREEN),
    "WARNING": ("#b45309", BOLD_YELLOW),
    "SKIP": ("#b45309", BOLD_YELLOW),
    "FAIL": ("#b91c1c", BOLD_RED),
    "ERROR": ("#b91c1c", BOLD_RED),
    "BLOCKED": ("#b91c1c", BOLD_RED),
}
_DARK_OUTPUT_COLORS = {
    "INFO": "#93c5fd", "SUCCESS": "#86efac", "PASS": "#86efac",
    "WARNING": "#fcd34d", "SKIP": "#fcd34d",
    "FAIL": "#fca5a5", "ERROR": "#fca5a5", "BLOCKED": "#fca5a5",
}
_PANEL_STYLE = (
    "color-scheme:light dark;background:light-dark(#fff,#1f2937);"
    "color:light-dark(#111827,#f9fafb);padding:6px 10px;margin:4px 0;"
    "border-radius:4px;border:1px solid #8884;"
)


def _report_safe(value: Any) -> Any:
    # Import lazily: validationtools also uses these formatters.
    if __package__:
        from .validationtools import redact
    else:
        from validationtools import redact
    return redact(value)


def _notebook_display() -> bool:
    try:
        from IPython import get_ipython
    except ModuleNotFoundError as error:
        if error.name != "IPython":
            raise
        return False
    shell = get_ipython()
    return shell is not None and getattr(shell, "kernel", None) is not None


def _display_preview(value: Any, depth: int = 0) -> Any:
    if depth > 8:
        return "[Nested details omitted from display]"
    if isinstance(value, Mapping):
        return {
            str(key): f"[Image payload omitted; {len(item)} characters]" if str(key) == "b64_json"
            and isinstance(item, str) else _display_preview(item, depth + 1)
            for key, item in value.items()
        }
    if isinstance(value, (list, tuple)):
        shown = [_display_preview(item, depth + 1) for item in value[:20]]
        return shown + ([f"[{len(value) - 20} more entries]"] if len(value) > 20 else [])
    if isinstance(value, str) and len(value) > 4000:
        return value[:4000] + f"\n[Display truncated; {len(value)} characters total]"
    return value


def set_output_verbose(enabled: bool = True) -> None:
    """Opt into detailed payloads and routine sub-command logs for debugging."""
    if not isinstance(enabled, bool):
        raise ValueError("Output verbosity must be a boolean.")
    _VERBOSE_OUTPUT.set(enabled)


def _compact_value(value: Any) -> str:
    if isinstance(value, Mapping):
        limit = 8 if all(not isinstance(item, (Mapping, list, tuple)) for item in value.values()) else 3
        text = ", ".join(f"{key}={_compact_value(item)}" for key, item in list(value.items())[:limit]) \
            + (" ..." if len(value) > limit else "")
    elif isinstance(value, (list, tuple)):
        shown = ", ".join(_compact_value(item) for item in value[:8])
        text = shown + (f" ... ({len(value)} entries)" if len(value) > 8 else "")
    else:
        text = str(value).replace("\n", " ")
    return text[:240] + (" ..." if len(text) > 240 else "")


def _compact_details(value: Any, *, errors: bool = False) -> str:
    if isinstance(value, Mapping):
        return " | ".join(
            ("" if re.fullmatch(r"value_\d+", str(key)) else f"{str(key).replace('_', ' ')}: ")
            + (item.replace("\n", " ") if errors and key in ("details", "reason", "error", "actual")
               and isinstance(item, str) else _compact_value(item))
            for key, item in value.items()
            if item is not None
            and not (isinstance(item, str) and not item)
            and not (isinstance(item, (Mapping, list, tuple)) and not len(item))
        )
    return _compact_value(value)


def format_output(title: str, details: Any = None, *, status: str = "info",
                  part: str = "RESULT", track_status: bool = True,
                  diagnostic: bool = False) -> None:
    """Display escaped, redacted HTML in a notebook, or ANSI output in a terminal."""
    status = status.upper()
    part = part.upper()
    if status not in _OUTPUT_STYLES or part not in ("INFO", "RESULT"):
        raise ValueError("Output requires a known status and INFO or RESULT part.")
    if part == "RESULT" and track_status:
        for events in _OUTPUT_STEPS.get():
            events.append(status)
    if diagnostic and status in ("INFO", "SUCCESS", "PASS") and not _VERBOSE_OUTPUT.get():
        return
    safe_title = str(_report_safe(title))
    has_details = details is not None
    safe_details = _display_preview(_report_safe(details)) if details is not None else {}
    color, ansi = _OUTPUT_STYLES[status]
    text = (safe_details if isinstance(safe_details, str)
            else json.dumps(safe_details, indent=2, default=str, ensure_ascii=False))
    compact = not _VERBOSE_OUTPUT.get()
    summary = _compact_details(safe_details, errors=status in ("ERROR", "FAIL", "BLOCKED"))
    if _notebook_display():
        from IPython.display import HTML, display
        heading = f"{part} | {safe_title}" if part == "INFO" else f"{status} | {safe_title}"
        content = (
            f'<span style="margin-left:10px">{html.escape(summary)}</span>'
            if compact and has_details else
            f'<pre style="white-space:pre-wrap;overflow-wrap:anywhere;margin:6px 0 0">{html.escape(text)}</pre>'
            if has_details else ""
        )
        if compact and has_details and ("..." in summary or len(text) > len(summary) + 100):
            content += (
                '<details style="margin-top:4px"><summary>Details</summary>'
                f'<pre style="white-space:pre-wrap;overflow-wrap:anywhere">{html.escape(text)}</pre></details>'
            )
        display(HTML(
            f'<section style="{_PANEL_STYLE}border-left:4px solid {color}">'
            f'<strong style="color:{color};color:light-dark({color},{_DARK_OUTPUT_COLORS[status]})">'
            f'{html.escape(heading)}</strong>'
            + content
            + "</section>"
        ))
    else:
        encoding = getattr(sys.stdout, "encoding", None) or "utf-8"
        heading = f"{ansi}{part} | {status} | {safe_title}{RESET_FORMATTING}"
        if compact and summary:
            heading += " | " + summary
        print(heading.encode(encoding, errors="backslashreplace").decode(encoding), flush=True)
        if has_details and not compact:
            print(text.encode(encoding, errors="backslashreplace").decode(encoding), flush=True)


def format_command(command: str | list[str], *, title: str = "Command",
                   diagnostic: bool = False, **details: Any) -> None:
    """Show a command and its non-secret coordinates before execution."""
    if isinstance(command, list):
        arguments = command.copy()
        for index, argument in enumerate(arguments[:-1]):
            if re.fullmatch(r"--(?:client-secret|password|api-key|access-token|token|key|secret)", argument, re.I):
                arguments[index + 1] = "[REDACTED]"
        display_command = subprocess.list2cmdline(arguments)
    else:
        display_command = re.sub(
            r"""(?ix)(--(?:client-secret|password|api-key|access-token|token|key|secret)\s+)
            (?:"[^"]*"|'[^']*'|\S+)""",
            r"\1[REDACTED]", command,
        )
    format_output(title, {"command": display_command, **details}, part="INFO", status="INFO",
                  diagnostic=diagnostic)


def format_result(title: str, *, status: str = "success", diagnostic: bool = False, **details: Any) -> None:
    format_output(title, details, status=status, part="RESULT", diagnostic=diagnostic)


def format_table(title: str, rows: list[Mapping[str, Any]], *, status: str = "info") -> None:
    """Render a redacted result table with status-colored rows and a terminal fallback."""
    status = status.upper()
    if status not in _OUTPUT_STYLES:
        raise ValueError("Table requires a known output status.")
    safe_rows = _report_safe(rows)
    if not safe_rows:
        format_output(title, safe_rows, status=status)
        return
    if not _notebook_display():
        format_output(title, status=status)
        columns = list(dict.fromkeys(key for row in safe_rows for key in row))
        encoding = getattr(sys.stdout, "encoding", None) or "utf-8"
        lines = [" | ".join(columns)]
        for row in safe_rows:
            row_status = str(row.get("status", row.get("result", status))).upper()
            _, ansi = _OUTPUT_STYLES.get(row_status, _OUTPUT_STYLES[status])
            lines.append(ansi + " | ".join(_compact_value(row.get(key, "")) for key in columns)
                         + RESET_FORMATTING)
        for line in lines:
            print(line.encode(encoding, errors="backslashreplace").decode(encoding), flush=True)
        return
    from IPython.display import HTML, display
    columns = list(dict.fromkeys(key for row in safe_rows for key in row))
    color, _ = _OUTPUT_STYLES[status]
    heading = html.escape(str(_report_safe(title)))
    header = "".join(f"<th style='text-align:left;padding:6px'>{html.escape(key)}</th>" for key in columns)
    body = []
    for row in safe_rows:
        row_status = str(row.get("status", row.get("result", status))).upper()
        row_color, _ = _OUTPUT_STYLES.get(row_status, _OUTPUT_STYLES[status])
        cells = []
        for column in columns:
            value = _display_preview(row.get(column, ""))
            text = str(value) if isinstance(value, (str, bool, int, float)) else json.dumps(value, default=str)
            cells.append(f"<td style='padding:6px;border-top:1px solid #8884'>{html.escape(text)}</td>")
        dark_color = _DARK_OUTPUT_COLORS.get(row_status, _DARK_OUTPUT_COLORS[status])
        body.append(f"<tr style='color:{row_color};color:light-dark({row_color},{dark_color})'>"
                    + "".join(cells) + "</tr>")
    display(HTML(
        f"<section style='{_PANEL_STYLE}'>"
        f"<strong style='color:{color};color:light-dark({color},{_DARK_OUTPUT_COLORS[status]})'>"
        f"{status} | {heading}</strong>"
        "<div style='max-height:500px;overflow:auto'><table style='border-collapse:collapse'>"
        f"<thead><tr>{header}</tr></thead><tbody>{''.join(body)}</tbody></table></div></section>"
    ))
    for events in _OUTPUT_STEPS.get():
        events.append(status)


def format_chat_message(role: str, text: str, *, turn: int | None = None,
                        status: str = "success", citations: list[Mapping[str, Any]] | None = None,
                        details: Mapping[str, Any] | None = None) -> None:
    """Render a full chat message with escaped text, safe source links and usage."""
    status = status.upper()
    if role not in ("user", "assistant", "system") or status not in _OUTPUT_STYLES:
        raise ValueError("Chat output requires a valid role and status.")
    safe_text = str(_report_safe(text))
    title = f"Turn {turn} | {role.title()}" if turn is not None else role.title()
    safe_details = _report_safe(details or {})
    sources = []
    for citation in _report_safe(citations or []):
        url = citation.get("url")
        if not isinstance(url, str):
            continue
        try:
            parsed = urlsplit(url)
        except ValueError:
            continue
        if parsed.scheme not in ("https", "http") or not parsed.hostname or parsed.username or parsed.password:
            continue
        sources.append((str(citation.get("title") or parsed.hostname), url))
    if _notebook_display():
        from IPython.display import HTML, display
        color, _ = _OUTPUT_STYLES["INFO" if role == "user" else status]
        links = "".join(
            f'<li><a href="{html.escape(url, quote=True)}" target="_blank" rel="noopener noreferrer">'
            f'{html.escape(label)}</a></li>' for label, url in sources
        )
        display(HTML(
            f'<article style="{_PANEL_STYLE}margin-left:{"18px" if role == "user" else "0"};'
            f'border-left:4px solid {color}">'
            f'<strong>{html.escape(title)}</strong>'
            f'<div style="white-space:pre-wrap;overflow-wrap:anywhere;margin-top:6px">{html.escape(safe_text)}</div>'
            + (f'<ul style="margin-bottom:4px">{links}</ul>' if links else "")
            + (f'<small>{html.escape(_compact_details(safe_details))}</small>' if safe_details else "")
            + "</article>"
        ))
        if status in ("WARNING", "ERROR", "FAIL", "BLOCKED"):
            for events in _OUTPUT_STEPS.get():
                events.append(status)
    else:
        format_output(title, {
            "message": safe_text, "sources": [{"title": label, "url": url} for label, url in sources],
            **safe_details,
        }, status="INFO" if role == "user" else status)


def http_call(callback: Callable[..., Any], url: str, **kwargs: Any) -> Any:
    """Log before/after a native requests call without changing its response shape."""
    payload = kwargs.get("json") or kwargs.get("data")
    model = payload.get("model") if isinstance(payload, Mapping) else None
    if model is None:
        model = (kwargs.get("headers") or {}).get("x-ai-model")
    if model is None and isinstance(kwargs.get("files"), Mapping):
        multipart_model = kwargs["files"].get("model")
        if isinstance(multipart_model, tuple) and len(multipart_model) > 1:
            model = multipart_model[1]
    method = getattr(callback, "__name__", "HTTP request").upper()
    format_output("HTTP request", {
        "method": method, "endpoint": url, "model": model,
        "query": kwargs.get("params", {}), "timeout seconds": kwargs.get("timeout"),
    }, part="INFO")
    started = time.perf_counter()
    try:
        response = callback(url, **kwargs)
    except Exception as error:
        format_result("HTTP request failed", status="ERROR", endpoint=url,
                      error_type=type(error).__name__, details=str(error))
        raise
    if kwargs.get("stream"):
        format_http_response(response, elapsed=time.perf_counter() - started,
                             body="Streaming response opened; events have not been consumed. Validate completion below.")
    else:
        format_http_response(response, elapsed=time.perf_counter() - started)
    return response


def format_http_response(response: Any, *, elapsed: float | None = None,
                         body: Any = _UNSET_OUTPUT, parse_error: str | None = None) -> None:
    """Show actual HTTP evidence; feature success is judged by its expected outcome."""
    if body is _UNSET_OUTPUT:
        try:
            body = response.json()
        except ValueError:
            body = response.text
    successful = 200 <= response.status_code < 300
    response_status = "SUCCESS" if successful else "ERROR" if response.status_code >= 500 else "WARNING"
    details = {
        "HTTP status": response.status_code, "elapsed seconds": round(elapsed, 3) if elapsed is not None else None,
        "response": body, "parsing issue": parse_error,
    }
    if not _VERBOSE_OUTPUT.get() and isinstance(body, Mapping):
        if isinstance(body.get("error"), Mapping):
            details["response"] = body["error"]
        elif isinstance(body.get("choices"), list) and body["choices"]:
            first = body["choices"][0]
            if isinstance(first, Mapping):
                message = first.get("message")
                content = message.get("content") if isinstance(message, Mapping) else None
                details["response"] = content or first.get("text") or body
        elif isinstance(body.get("data"), list) and body["data"]:
            first = body["data"][0]
            if isinstance(first, Mapping) and isinstance(first.get("embedding"), list):
                details["response"] = f"{len(body['data'])} embedding(s), {len(first['embedding'])} dimensions"
            elif isinstance(first, Mapping) and ("b64_json" in first or "url" in first):
                details["response"] = f"{len(body['data'])} image(s) returned"
        elif body.get("id") and body.get("status"):
            details["response"] = {"id": body["id"], "status": body["status"]}
        if body.get("usage"):
            details["usage"] = body["usage"]
    else:
        if _VERBOSE_OUTPUT.get():
            details["headers"] = dict(response.headers)
    selected_headers = {key: value for key, value in response.headers.items()
                        if key.lower().startswith("uaig-") or key.lower() in ("retry-after", "x-ms-region")}
    if selected_headers:
        details["routing"] = selected_headers
    format_output("HTTP response", details, status=response_status, track_status=False)
    if not successful:
        for events in _OUTPUT_STEPS.get():
            events.append("HTTP_ERROR" if response.status_code >= 500 else "HTTP_WARNING")


def print_command(command: str = "") -> None:
    format_command(command)


def print_info(message: str) -> None:
    format_output(message, part="INFO")


def print_message(message: str, output: Any = "", duration: str = "") -> None:
    format_result(message, output=output, duration=duration)


def print_ok(message: str, output: Any = "", duration: str = "") -> None:
    format_result(message, output=output, duration=duration)


def print_warning(message: str, output: Any = "", duration: str = "") -> None:
    format_result(message, status="WARNING", output=output, duration=duration)


def print_error(message: str, output: Any = "", duration: str = "") -> None:
    format_result(message, status="ERROR", output=output, duration=duration)


def require_inputs(values: Mapping[str, Any]) -> None:
    """Reject all missing/nested placeholder inputs without echoing their values."""
    missing: list[str] = []

    def visit(label: str, value: Any) -> None:
        if isinstance(value, os.PathLike):
            value = os.fspath(value)
        if isinstance(value, Mapping) and value:
            for key, item in value.items():
                visit(f"{label}.{key}", item)
        elif isinstance(value, (list, tuple)) and value:
            for index, item in enumerate(value):
                visit(f"{label}[{index}]", item)
        elif (
            value is None or value is False or value == "" or value == {} or value == []
            or (isinstance(value, str) and (
                not value.strip() or re.search(
                    r"REPLACE|<[^>]+>|\$\{[^}]+\}|^(?:your[-_ ].*|TODO|CHANGEME|placeholder)$", value, re.I
                )
            ))
        ):
            missing.append(label)

    for label, value in values.items():
        visit(str(label), value)
    if missing:
        raise ValueError(
            "Initialization stopped: required parameters were not supplied: "
            + ", ".join(missing)
            + ". Set these inputs in the configuration cell (or the documented environment/secret store) "
            "and rerun initialization. Disabled optional scenarios do not require their inputs."
        )


def require_capabilities(catalog: Any, model_names: list[str] | None = None) -> None:
    """Require a nonempty eligible plan; inferred operations are valid defaults."""
    names = [name for name in (
        list(dict.fromkeys(entry.name for entry in catalog.entries))
        if model_names is None else model_names
    ) if not catalog.is_skipped(name)]
    if not names:
        raise ValueError("No models selected for validation; review skipped_models and operation overrides.")
    require_inputs({"deployed model catalogue": names})
    missing = [name for name in names if not catalog.operations(name)]
    if missing:
        raise ValueError(
            "Initialization stopped: no operations resolved for " + ", ".join(missing)
            + ". Set VALIDATION_MODEL_CAPABILITIES in the selected azd environment or overrides['capabilities']. "
            "Alternatively enable the default infer_operations behavior."
        )


@contextmanager
def notebook_step(title: str, inputs: Any = None, expected: str | None = None,
                  namespace: Mapping[str, Any] | None = None) -> Generator[None, None, None]:
    """Give every cell a before/after output without hiding its code or exceptions."""
    events: list[str] = []
    token = _OUTPUT_STEPS.set((*_OUTPUT_STEPS.get(), events))
    run = namespace.get("run") if namespace is not None else None
    initial_results = list(getattr(run, "results", ()))
    if isinstance(inputs, Mapping) and not _VERBOSE_OUTPUT.get():
        inputs = {
            key: value for key, value in inputs.items()
            if isinstance(value, (str, int, float, bool, Mapping, list, tuple, os.PathLike))
            and key not in {"run", "apim", "context", "transport", "b"}
        }
    format_output(title, {"inputs": inputs, "expected output": expected} if _VERBOSE_OUTPUT.get()
                  else inputs, part="INFO")
    started = time.perf_counter()
    try:
        with warnings.catch_warnings(record=True) as captured:
            warnings.simplefilter("always")
            try:
                yield
            finally:
                messages = list(dict.fromkeys(str(warning.message) for warning in captured))
                if messages:
                    format_output(title, {"warnings": messages}, status="WARNING")
    except BaseException as error:
        format_output(title, {
            "error type": type(error).__name__, "details": str(error),
            "elapsed seconds": round(time.perf_counter() - started, 3),
        }, status="WARNING" if isinstance(error, (KeyboardInterrupt, SystemExit)) else "ERROR")
        raise
    else:
        current_run = namespace.get("run") if namespace is not None else None
        results = list(getattr(current_run, "results", ()))
        new_results = (results[len(initial_results):] if current_run is run else results)
        statuses = events + [
            "WARNING" if result.status == "BLOCKED" and not result.required else result.status
            for result in new_results
        ]
        issues = any(status in ("FAIL", "ERROR", "BLOCKED") for status in statuses)
        caution = any(status in ("WARNING", "SKIP") for status in statuses)
        if not new_results and "HTTP_ERROR" in statuses:
            issues = True
        if not new_results and "HTTP_WARNING" in statuses:
            caution = True
        status = "ERROR" if issues else "WARNING" if caution else "SUCCESS"
        result_details: dict[str, Any] = {"elapsed seconds": round(time.perf_counter() - started, 3)}
        if new_results:
            passed = sum(result.status == "PASS" for result in new_results)
            result_details["checks"] = f"{passed}/{len(new_results)} passed"
            for outcome in ("FAIL", "SKIP", "BLOCKED"):
                count = sum(result.status == outcome for result in new_results)
                if count:
                    result_details[outcome.lower()] = count
        format_output(title, result_details, status=status)
    finally:
        _OUTPUT_STEPS.reset(token)

def mask_sensitive_values(data, sensitive_keys=None):
    """
    Recursively mask sensitive values in nested dictionaries and lists.
    
    Args:
        data: The data structure to process (dict, list, or primitive)
        sensitive_keys: List of key names to mask (case-insensitive). 
                       Defaults to ['apiKey', 'api_key', 'key', 'secret', 'password']
    
    Returns:
        A copy of the data with sensitive values replaced by '########'
    """
    if sensitive_keys is None:
        sensitive_keys = ['apikey', 'api_key', 'secret', 'password']
    
    sensitive_keys_lower = [k.lower() for k in sensitive_keys]
    
    if isinstance(data, dict):
        return {
            k: '########' if k.lower() in sensitive_keys_lower and isinstance(v, str)
               else mask_sensitive_values(v, sensitive_keys)
            for k, v in data.items()
        }
    elif isinstance(data, list):
        return [mask_sensitive_values(item, sensitive_keys) for item in data]
    else:
        return data

class Output(object):
    def __init__(self, success, text):
        self.success = success
        self.text = text

        try:
            self.json_data = json.loads(text)
        except:
            # stdout may contain non-JSON text (progress indicators, warnings) before/after the JSON.
            # Try to extract the outermost JSON object or array from the text.
            self.json_data = Output._extract_json(text)

    @staticmethod
    def _extract_json(text):
        """Extract the first valid JSON object or array from mixed text."""
        for start_char, end_char in [('{', '}'), ('[', ']')]:
            start = text.find(start_char)
            if start == -1:
                continue
            # Search from the end backwards for the matching closing character
            end = text.rfind(end_char)
            if end > start:
                try:
                    return json.loads(text[start:end + 1])
                except json.JSONDecodeError:
                    continue
        return json.loads("{}")  # return empty dict if no valid JSON found


def azd_env_get(var_name, default=None):
    """Return the value of an `azd` environment variable for the active azd environment.

    Returns `default` when the `azd` CLI is not installed, no environment is selected,
    or the variable is not set. The value is returned as a stripped string; callers
    that expect JSON should `json.loads(...)` it themselves.

    Designed for use in validation notebooks so a single `azd_env_get('AZURE_RESOURCE_GROUP')`
    call works on Windows / macOS / Linux without leaking subprocess plumbing into the notebook.
    """
    try:
        result = subprocess.run(
            ["azd", "env", "get-value", var_name],
            capture_output=True, text=True, check=False, shell=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
        return default
    except FileNotFoundError:
        return default
    except Exception:
        return default


def azd_env_get_json(var_name, default=None):
    """Like `azd_env_get`, but parses the value as JSON. Returns `default` on any failure."""
    raw = azd_env_get(var_name)
    if not raw:
        return default
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return default


def load_azd_env(var_map, verbose=True):
    """Load multiple azd environment variables in one shot.

    `var_map` maps a friendly label to either:
      - a single env-var name (str)            → returns the raw string value
      - a list of fallback env-var names       → returns the first match found
      - a tuple `(names, "json")`              → JSON-decodes the matched value

    Returns a dict keyed by the same labels. Missing values are omitted from the result
    so callers can use `result.get(label, fallback_default)` patterns.

    Example:
        loaded = utils.load_azd_env({
            "resource_group": ["AZURE_RESOURCE_GROUP", "GOVERNANCE_HUB_RESOURCE_GROUP"],
            "location":       ["AZURE_LOCATION", "LOCATION"],
            "llm_backends":   (["LLM_BACKEND_CONFIG", "LLM_BACKENDS_CONFIG"], "json"),
        })
    """
    loaded = {}
    for label, spec in var_map.items():
        names, mode = (spec, "str")
        if isinstance(spec, tuple):
            names, mode = spec
        if isinstance(names, str):
            names = [names]
        value = None
        for n in names:
            v = azd_env_get(n)
            if v:
                value = v
                break
        if value is None:
            if verbose:
                print_warning(f"azd env var not set for '{label}' (looked up: {names})")
            continue
        if mode == "json":
            try:
                value = json.loads(value)
            except json.JSONDecodeError as e:
                if verbose:
                    print_warning(f"azd env var '{label}' is not valid JSON: {e}")
                continue
        loaded[label] = value
    return loaded


def get_current_subscription():
    try:
        output = run("az account show", "Retrieved az account", "Failed to get the current az account")

        if output.success and output.json_data:
            subscription_id = output.json_data['id']
            subscription_name = output.json_data['name']
            print_info(f"Using Subscription ID: {subscription_id} ({subscription_name})")
            return subscription_id
        else:
            print_error("No current subscription found.")
            return None
    except Exception as e:
        print_error(f"Error retrieving current subscription: {e}")
        return None

# Retrieves resources in a resource group
def get_resources(resource_group_name, config):
    if not resource_group_name:
        print_error("Missing resource group name parameter.")
        return

    resources = {}
    try:
        ## retrieve resource group location
        output = run(f"az group show --name {resource_group_name}")

        if output.success:
            print_info(f"Using existing resource group '{resource_group_name}'")
            output = run(f"az group show --name {resource_group_name} -o json", "Retrieved resource group ", "Failed to retrieve resource group")
            if output.success and output.json_data:
                resources['resourceGroupLocation'] = output.json_data["location"]

                ## retrieve resources
                output = run(f'az resource list -g {resource_group_name} -o json', "Listed resources", "Failed to list resources")
                if output.success and output.json_data:
                    for resource in output.json_data:
                        match resource["type"].lower():
                            case "microsoft.operationalinsights/workspaces":
                                resources['logAnalyticsResourceId'] = resource["id"]
                                resources['logAnalyticsResourceName'] = resource["name"]
                            case "microsoft.insights/components":
                                resources['appInsightsResourceId'] = resource["id"]
                                resources['appInsightsResourceName'] = resource["name"]
                                output = run(f'az resource show -g {resource_group_name} -n {resource["name"]} --resource-type "microsoft.insights/components" -o json', "Retrieved App Insights resource", "Failed to retrieve App Insights resource")
                                if output.success and output.json_data:
                                    resources['appInsightsInstrumentationKey'] = output.json_data["properties"]["InstrumentationKey"]
                            case "microsoft.cognitiveservices/accounts":
                                resources['foundryResourceId'] = resource["id"]
                                resources['foundryResourceName'] = resource["name"]
                            case "microsoft.cognitiveservices/accounts/projects":
                                resources['foundryProjectId'] = resource["id"]
                                resources['foundryProjectName'] = resource["name"]
                            case "microsoft.apimanagement/service":
                                resources['apimResourceId'] = resource["id"]
                                resources['apimResourceName'] = resource["name"]
                                resources['apimPrincipalId'] = resource["identity"]["principalId"]
        else:
            return config

    except Exception as e:
        print_error(f"Error retrieving resources: {e}")

    return resources

# Cleans up resources associated with a deployment in a resource group
def cleanup_resources(deployment_name, resource_group_name = None):
    if not deployment_name:
        print_error("Missing deployment name parameter.")
        return

    if not resource_group_name:
        resource_group_name = f"lab-{deployment_name}"

    try:
        print_info(f"🧹 Cleaning up resource group '{resource_group_name}'...")

        # Show the deployment details
        output = run(f"az deployment group show --name {deployment_name} -g {resource_group_name} -o json", "Deployment retrieved", "Failed to retrieve the deployment")

        if output.success and output.json_data:
            provisioning_state = output.json_data.get("properties").get("provisioningState")
            print_info(f"Deployment provisioning state: {provisioning_state}")

            # Delete AI Foundry projects
            output = run(f'az resource list -g {resource_group_name} --resource-type "microsoft.cognitiveservices/accounts/projects"', "Retrieved AI Foundry projects", "Failed to list AI Foundry projects")
            if output.success and output.json_data:
                for resource in output.json_data:
                    print_info(f"Deleting AI Foundry project '{resource['name']}' in resource group '{resource_group_name}'...")
                    output = run(f"az resource delete --ids \"{resource['id']}\"", f"AI Foundry project '{resource['name']}' deleted", f"Failed to delete AI Foundry project '{resource['name']}'")

            # Delete and purge CognitiveService accounts
            output = run(f"az cognitiveservices account list -g {resource_group_name}", f"Listed CognitiveService accounts", f"Failed to list CognitiveService accounts")
            if output.success and output.json_data:
                for resource in output.json_data:
                    print_info(f"Deleting and purging Cognitive Service Account '{resource['name']}' in resource group '{resource_group_name}'...")
                    output = run(f"az cognitiveservices account delete -g {resource_group_name} -n {resource['name']}", f"Cognitive Services '{resource['name']}' deleted", f"Failed to delete Cognitive Services '{resource['name']}'")
                    output = run(f"az cognitiveservices account purge -g {resource_group_name} -n {resource['name']} -l \"{resource['location']}\"", f"Cognitive Services '{resource['name']}' purged", f"Failed to purge Cognitive Services '{resource['name']}'")

            # Delete and purge APIM resources
            output = run(f" az apim list -g {resource_group_name}", f"Listed APIM resources", f"Failed to list APIM resources")
            if output.success and output.json_data:
                for resource in output.json_data:
                    print_info(f"Deleting and purging API Management '{resource['name']}' in resource group '{resource_group_name}'...")
                    output = run(f"az apim delete -n {resource['name']} -g {resource_group_name} -y", f"API Management '{resource['name']}' deleted", f"Failed to delete API Management '{resource['name']}'")
                    output = run(f"az apim deletedservice purge --service-name {resource['name']} --location \"{resource['location']}\"", f"API Management '{resource['name']}' purged", f"Failed to purge API Management '{resource['name']}'")

            # Delete and purge Key Vault resources
            output = run(f"az keyvault list -g {resource_group_name}", f"Listed Key Vault resources", f"Failed to list Key Vault resources")
            if output.success and output.json_data:
                for resource in output.json_data:
                    print_info(f"Deleting and purging Key Vault '{resource['name']}' in resource group '{resource_group_name}'...")
                    output = run(f"az keyvault delete -n {resource['name']} -g {resource_group_name}", f"Key Vault '{resource['name']}' deleted", f"Failed to delete Key Vault '{resource['name']}'")
                    output = run(f"az keyvault purge -n {resource['name']} --location \"{resource['location']}\"", f"Key Vault '{resource['name']}' purged", f"Failed to purge Key Vault '{resource['name']}'")

            # Delete the resource group last
            print_message(f"🧹 Deleting resource group '{resource_group_name}'...")
            output = run(f"az group delete --name {resource_group_name} -y", f"Resource group '{resource_group_name}' deleted", f"Failed to delete resource group '{resource_group_name}'")

            print_message("🧹 Cleanup completed.")

    except Exception as e:
        print(f"An error occurred during cleanup: {e}")
        traceback.print_exc()

def create_resource_group(resource_group_name, resource_group_location = None):
    if not resource_group_name:
        print_error('Please specify the resource group name.')
    else:
        output = run(f"az group show --name {resource_group_name}")

        if output.success:
            print_info(f"Using existing resource group '{resource_group_name}'")
        else:
            if not resource_group_location:
                print_error('Please specify the resource group location.')
            else:
                print_info(f"Resource group {resource_group_name} does not yet exist. Creating the resource group now...")

                output = run(f"az group create --name {resource_group_name} --location {resource_group_location} --tags source=ai-gateway",
                    f"Resource group '{resource_group_name}' created",
                    f"Failed to create the resource group '{resource_group_name}'")

# Deletes a specific resource based on its type
def delete_resource(resource, resource_group_name):
    resource_name = resource.get("name")
    resource_type = resource.get("type")
    resource_location = resource.get("location")

    print(f"🗑 Deleting {resource_type} '{resource_name}' in resource group '{resource_group_name}'...")

    # API Management
    if resource_type == "Microsoft.ApiManagement/service":
        output = run(f"az apim delete -n {resource_name} -g {resource_group_name} -y", f"API Management '{resource_name}' deleted", f"Failed to delete API Management '{resource_name}'")

        output = run(f"az apim deletedservice purge --service-name {resource_name} --location \"{resource_location}\"", f"API Management '{resource_name}' purged", f"Failed to purge API Management '{resource_name}'")

    # Cognitive Services
    elif resource_type == "Microsoft.CognitiveServices/accounts":
        output = run(f"az cognitiveservices account delete -g {resource_group_name} -n {resource_name}", f"Cognitive Services '{resource_name}' deleted", f"Failed to delete Cognitive Services '{resource_name}'")

        output = run(f"az cognitiveservices account purge -g {resource_group_name} -n {resource_name} -l \"{resource_location}\"", f"Cognitive Services '{resource_name}' purged", f"Failed to purge Cognitive Services '{resource_name}'")

    # Key Vault
    elif resource_type == "Microsoft.KeyVault/vaults":
        output = run(f"az keyvault delete -n {resource_name} -g {resource_group_name}", f"Key Vault '{resource_name}' deleted", f"Failed to delete Key Vault '{resource_name}'")

def get_deployment_output(output, output_property, output_label = '', secure = False) -> str:
    try:
        deployment_output = output.json_data['properties']['outputs'][output_property]['value']

        if output_label:
            if secure:
                print_info(f"{output_label}: ****{deployment_output[-4:]}")
            else:
                print_info(f"{output_label}: {deployment_output}")

        return str(deployment_output)
    except Exception as e:
        error = f"Failed to retrieve output property: '{output_property}'\nError: {e}"
        print_error(error)
        raise Exception(error)

def print_response(response):
    format_http_response(response)

def print_response_code(response):
    if 200 <= response.status_code < 300:
        status = "SUCCESS"
    else:
        status = "ERROR" if response.status_code >= 500 else "WARNING"
        for events in _OUTPUT_STEPS.get():
            events.append("HTTP_ERROR" if response.status_code >= 500 else "HTTP_WARNING")
    format_output("HTTP response status", {
        "HTTP status": response.status_code, "reason": response.reason,
    }, status=status, track_status=False)

# Simple: print full error body (JSON if available, else raw text)
def print_full_http_error(response):
    try:
        data = response.json()
        print_error("Request failed. Full JSON body:", json.dumps(data, indent=2))
        # If ARM-style error present, surface message too
        if isinstance(data, dict) and isinstance(data.get("error"), dict):
            code = data["error"].get("code", "")
            msg = data["error"].get("message", "")
            if msg or code:
                print_error(f"Service error:", f"{code} - {msg}")
    except ValueError:
        print_error("Request failed. Full text body:", response.text or "")

def run(command, ok_message = '', error_message = '', print_output = False, print_command_to_run = True):
    if print_command_to_run:
        print_command(command)

    start_time = time.time()

    try:
        completed_process = subprocess.run(
            command,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        output_text = completed_process.stdout or ""
        stderr_text = completed_process.stderr or ""
        success = completed_process.returncode == 0
    except subprocess.CalledProcessError as e:
        output_text = e.output.decode("utf-8", errors="replace") if isinstance(e.output, (bytes, bytearray)) else (e.output or "")
        stderr_text = e.stderr.decode("utf-8", errors="replace") if isinstance(e.stderr, (bytes, bytearray)) else (e.stderr or "")
        success = False

    # Combine stdout and stderr for error reporting, but keep stdout clean for JSON parsing
    combined_text = output_text + ("\n" + stderr_text if stderr_text else "")

    minutes, seconds = divmod(time.time() - start_time, 60)

    print_message = print_ok if success else print_error

    if (ok_message or error_message):
        print_message(ok_message if success else error_message, combined_text if not success or print_output  else "", f"[{int(minutes)}m:{int(seconds)}s]")
    else:
        format_result(
            "Command executed successfully" if success else "Command failed",
            status="SUCCESS" if success else "ERROR",
            elapsed_seconds=round(time.time() - start_time, 3),
            details=combined_text if not success or print_output else "",
        )

    return Output(success, output_text)

def create_bicep_params(policy_xml_filepath, parameters_filepath, bicep_parameters, replacements_list):
    # Read the specified policy XML file
    with open(policy_xml_filepath, 'r') as policy_xml_file:
        policy_template_xml = policy_xml_file.read()

    # Replace the placeholders in the policy XML with the actual values from the replacements_lists array
    for key, value in replacements_list:
        policy_template_xml = policy_template_xml.replace(key, str(value))

    # Set or update the policyXml parameter in the bicep parameters file
    bicep_parameters['parameters'].setdefault('policyXml', {})
    bicep_parameters['parameters']['policyXml']['value'] = policy_template_xml

    # Write the updated bicep parameters to the specified parameters file
    with open(parameters_filepath, 'w') as bicep_parameters_file:
        bicep_parameters_file.write(json.dumps(bicep_parameters))

    print(f"📝 Updated the policy XML in the bicep parameters file '{parameters_filepath}'")

    return bicep_parameters

def update_api_policy(subscription_id, resource_group_name, apim_service_name, api_id, policy_xml):
    import requests
    # We first need to obtain an access token for the REST API
    output = run(f"az account get-access-token --resource https://management.azure.com/",
        f"Successfully obtained access token", f"Failed to obtain access token")

    if output.success and output.json_data:
        access_token = output.json_data['accessToken']

        print("Updating the API policy...")
        # https://learn.microsoft.com/en-us/rest/api/apimanagement/api-policy/create-or-update?view=rest-apimanagement-2024-06-01-preview
        url = f"https://management.azure.com/subscriptions/{subscription_id}/resourceGroups/{resource_group_name}/providers/Microsoft.ApiManagement/service/{apim_service_name}/apis/{api_id}/policies/policy?api-version=2024-06-01-preview"
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {access_token}"
        }

        body = {
            "properties": {
                "format": "rawxml",
                "value": policy_xml
            }
        }

        response = requests.put(url, headers = headers, json = body)
        if 200 <= response.status_code < 300:
            print_response_code(response)
        else:
            print_response_code(response)
            print_full_http_error(response)

def update_api_operation_policy(subscription_id, resource_group_name, apim_service_name, api_id, operation_id, policy_xml):
    import requests
    # We first need to obtain an access token for the REST API
    output = run(f"az account get-access-token --resource https://management.azure.com/",
        f"Successfully obtained access token", f"Failed to obtain access token")

    if output.success and output.json_data:
        access_token = output.json_data['accessToken']

        print("Updating the API policy...")
        # https://learn.microsoft.com/en-us/rest/api/apimanagement/api-policy/create-or-update?view=rest-apimanagement-2024-06-01-preview
        url = f"https://management.azure.com/subscriptions/{subscription_id}/resourceGroups/{resource_group_name}/providers/Microsoft.ApiManagement/service/{apim_service_name}/apis/{api_id}/operations/{operation_id}/policies/policy?api-version=2024-06-01-preview"
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {access_token}"
        }

        body = {
            "properties": {
                "format": "rawxml",
                "value": policy_xml
            }
        }

        response = requests.put(url, headers = headers, json = body)
        print_response_code(response)

def get_debug_credentials(apim_service_id, api_id, expire_after = 'PT1H') -> str | None:
    request = {
        "credentialsExpireAfter": expire_after,
        "apiId": f"{apim_service_id}/apis/{api_id}",
        "purposes": ["tracing"]
    }
    output = run(f"az rest --method post --uri {apim_service_id}/gateways/managed/listDebugCredentials?api-version=2023-05-01-preview --body \"{str(request)}\"",
            "Retrieved APIM debug credentials", "Failed to get the APIM debug credentials")
    return output.json_data['token'] if output.success and output.json_data else None
        
def get_trace(apim_service_id, trace_id) -> str | None:
    request = {
        "traceId": trace_id
    }
    output = run(f"az rest --method post --uri {apim_service_id}/gateways/managed/listTrace?api-version=2023-05-01-preview --body \"{str(request)}\"",
            "Retrieved trace details", "Failed to get the trace details")
    return output.json_data if output.success and output.json_data else None
