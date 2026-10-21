"""Offline Foundry SDK conversation and bounded, visible rate-limit regressions."""

import copy
import importlib
import io
import json
import sys
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from typing import get_type_hints
from unittest.mock import Mock, patch

import openai

from shared import foundrychat
from shared.validationtools import ValidationError, ValidationRun


PROMPTS = [f"HR question {turn}" for turn in range(1, 11)]


class SDKValue:
    def __init__(self, value):
        self.value = value

    def model_dump(self):
        return copy.deepcopy(self.value)


def reply(turn=1, *, cited=True):
    annotations = ([{"type": "url_citation", "title": "Official HR evidence",
                     "url": f"https://example.org/hr/{turn}", "start_index": 0, "end_index": 8}]
                   if cited else [])
    output = [
        {"type": "message", "role": "assistant", "content": [
            {"type": "output_text", "text": f"HR answer {turn}", "annotations": annotations},
        ]},
    ]
    if cited:
        output.insert(0, {"type": "web_search_call", "id": f"search-{turn}", "status": "completed",
                         "action": {"type": "search", "query": f"HR evidence {turn}", "sources": [
                             {"type": "url", "url": f"https://example.org/hr/{turn}"},
                             {"type": "url", "url": f"https://example.org/source/{turn}"},
                         ]}})
    return {"id": f"response-{turn}", "status": "completed", "output": output,
            "error": None, "usage": {"input_tokens": turn, "output_tokens": 8, "total_tokens": turn + 8}}


def client_with(responses=None):
    return SimpleNamespace(
        max_retries=0,
        conversations=SimpleNamespace(
            create=Mock(return_value=SDKValue({"id": "conversation-hr"})),
            items=SimpleNamespace(create=Mock(return_value=SDKValue({"data": []}))),
        ),
        responses=SimpleNamespace(create=Mock(
            side_effect=responses if responses is not None else
            [SDKValue(reply(turn)) for turn in range(1, 11)],
        )),
    )


def status_error(status=429, *, headers=None, body=None):
    # Construct actual OpenAI exceptions with the transport used by the installed SDK.
    transport = sdk_transport()
    response = transport.Response(
        status, headers=headers or {}, request=transport.Request("POST", "https://example.org/responses"),
    )
    return openai.APIStatusError(
        f"SDK status {status}", response=response,
        body=body if body is not None else {"error": {"code": "rate_limit_exceeded",
                                                     "message": "Token rate limit exceeded"}},
    )


def sdk_transport():
    response_class = get_type_hints(openai.APIStatusError.__init__)["response"]
    return importlib.import_module(response_class.__module__.split(".")[0])


class RetryDelayTests(unittest.TestCase):
    def test_numeric_seconds_case_insensitive_and_fractional(self):
        self.assertEqual(foundrychat.retry_delay({"Retry-After": "12.5"}), 12.5)
        self.assertEqual(foundrychat.retry_delay({"retry-after": "0"}), 0)

    def test_http_date_and_past_date(self):
        now = datetime(2026, 10, 20, 8, tzinfo=timezone.utc).timestamp()
        self.assertEqual(foundrychat.retry_delay(
            {"Retry-After": "Tue, 20 Oct 2026 08:01:30 GMT"}, now=now), 90)
        self.assertEqual(foundrychat.retry_delay(
            {"Retry-After": "Tue, 20 Oct 2026 07:00:00 GMT"}, now=now), 0)

    def test_http_date_uses_patchable_clock(self):
        with patch.object(foundrychat.time, "time", return_value=0):
            self.assertEqual(foundrychat.retry_delay(
                {"Retry-After": "Thu, 01 Jan 1970 00:00:45 GMT"}), 45)

    def test_milliseconds(self):
        self.assertEqual(foundrychat.retry_delay({"Retry-After-Ms": "1250"}), 1.25)

    def test_relative_token_reset_seconds_and_duration(self):
        for value, expected in [("30", 30), ("1.5s", 1.5), ("250ms", .25),
                                ("1m30s", 90), ("1h2m3s", 3723)]:
            with self.subTest(value=value):
                self.assertEqual(foundrychat.retry_delay(
                    {"X-RateLimit-Reset-Tokens": value}), expected)

    def test_conflicting_hints_do_not_allow_premature_retry(self):
        self.assertEqual(foundrychat.retry_delay({
            "Retry-After": "2", "retry-after-ms": "3000", "x-ratelimit-reset-tokens": "4s",
        }), 4)

    def test_missing_invalid_negative_and_nonfinite_hints(self):
        for value in [None, "", "bad date", "-1", "NaN", "inf", "-2s", "2 days", "1s junk"]:
            with self.subTest(value=value):
                self.assertIsNone(foundrychat.retry_delay({
                    "retry-after": value, "retry-after-ms": value,
                    "x-ratelimit-reset-tokens": value,
                }))
        self.assertIsNone(foundrychat.retry_delay(None))
        self.assertIsNone(foundrychat.retry_delay({}))

    def test_invalid_primary_hint_does_not_hide_valid_secondary(self):
        self.assertEqual(foundrychat.retry_delay({
            "retry-after": "invalid", "retry-after-ms": "2000",
        }), 2)


class FoundryConversationTests(unittest.TestCase):
    def setUp(self):
        self.run = ValidationRun("offline HR Foundry")
        self.chat = self.enterContext(patch.object(
            foundrychat.utils, "format_chat_message", create=True,
        ))
        self.sleep = self.enterContext(patch.object(foundrychat.time, "sleep"))
        self.enterContext(redirect_stdout(io.StringIO()))

    def execute(self, client=None, **options):
        self.client = client or client_with()
        return foundrychat.run_hr_conversation(
            self.client, "existing-hr-agent", "7", PROMPTS, self.run, **options,
        )

    def assert_failed(self, case="hr/turn-1"):
        self.assertEqual(self.run.results[-1].case, case)
        self.assertEqual(self.run.results[-1].status, "FAIL")

    def test_exact_10_turn_sdk_protocol_and_actual_evidence(self):
        records = self.execute()
        self.assertEqual(len(records), 10)
        self.client.conversations.create.assert_called_once_with()
        self.assertEqual(self.client.conversations.items.create.call_count, 10)
        self.assertEqual(self.client.responses.create.call_count, 10)
        self.assertEqual(len(self.run.results), 10)
        self.assertTrue(all(row.status == "PASS" for row in self.run.results))
        self.sleep.assert_not_called()
        keys = []
        for turn, record in enumerate(records, start=1):
            self.assertEqual(record, {
                "turn": turn, "user": PROMPTS[turn - 1], "assistant": f"HR answer {turn}",
                "conversation_id": "conversation-hr", "response_id": f"response-{turn}",
                "usage": reply(turn)["usage"],
                "web_search_calls": [reply(turn)["output"][0]],
                "citations": [
                    {"title": "Official HR evidence", "url": f"https://example.org/hr/{turn}"},
                    {"title": "", "url": f"https://example.org/source/{turn}"},
                ], "retries": 0,
            })
            append = self.client.conversations.items.create.call_args_list[turn - 1].kwargs
            self.assertEqual(append, {
                "conversation_id": "conversation-hr",
                "items": [{"type": "message", "role": "user", "content": PROMPTS[turn - 1]}],
            })
            request = self.client.responses.create.call_args_list[turn - 1].kwargs
            self.assertEqual(request["conversation"], "conversation-hr")
            self.assertEqual(request["extra_body"], {"agent_reference": {
                "name": "existing-hr-agent", "type": "agent_reference", "version": "7",
            }})
            self.assertNotIn("input", request)
            self.assertNotIn("model", request)
            keys.append(request["extra_headers"]["Idempotency-Key"])
            rendered = self.chat.call_args_list[turn * 2 - 1]
            self.assertEqual(rendered.args, ("assistant", f"HR answer {turn}"))
            self.assertEqual(rendered.kwargs["details"]["sdk_response"], reply(turn))
            self.assertEqual(rendered.kwargs["citations"], record["citations"])
            self.assertEqual(self.run.results[turn - 1].case, f"hr/turn-{turn}")
        self.assertEqual(len(set(keys)), 10)

    def test_plain_dictionary_sdk_results_are_supported(self):
        client = client_with([reply(turn) for turn in range(1, 11)])
        client.conversations.create.return_value = {"id": "conversation-hr"}
        self.assertEqual(len(self.execute(client)), 10)

    def test_real_sdk_429_retries_response_only_with_stable_key(self):
        client = client_with([status_error(headers={"Retry-After": "3"}),
                              *[SDKValue(reply(turn)) for turn in range(1, 11)]])
        records = self.execute(client)
        self.assertEqual(client.responses.create.call_count, 11)
        self.assertEqual(client.conversations.items.create.call_count, 10)
        self.assertEqual(client.responses.create.call_args_list[0],
                         client.responses.create.call_args_list[1])
        self.sleep.assert_called_once_with(3)
        self.assertEqual(records[0]["retries"], 1)
        self.assertTrue(all(record["retries"] == 0 for record in records[1:]))
        warnings = [call for call in self.chat.call_args_list
                    if call.kwargs.get("status") == "warning"]
        self.assertEqual(len(warnings), 1)
        self.assertIn("sleeping 3 seconds", warnings[0].args[1])
        self.assertEqual(self.run.results[0].evidence["attempts"][0]["wait_seconds"], 3)

    def test_middle_turn_retry_never_repeats_successful_turns(self):
        client = client_with([
            *[reply(turn) for turn in range(1, 8)],
            status_error(headers={"retry-after-ms": "500"}),
            *[reply(turn) for turn in range(8, 11)],
        ])
        records = self.execute(client)
        self.assertEqual([row["response_id"] for row in records],
                         [f"response-{turn}" for turn in range(1, 11)])
        self.assertEqual(records[7]["retries"], 1)
        self.assertEqual(client.conversations.items.create.call_count, 10)
        self.sleep.assert_called_once_with(.5)

    def test_exception_date_milliseconds_and_token_reset_are_honored(self):
        for headers, delay in [
            ({"Retry-After": "Thu, 01 Jan 1970 00:00:45 GMT"}, 45),
            ({"retry-after-ms": "2000"}, 2),
            ({"x-ratelimit-reset-tokens": "1m10s"}, 70),
        ]:
            with self.subTest(headers=headers):
                self.run = ValidationRun("header delay")
                self.sleep.reset_mock()
                with patch.object(foundrychat.time, "time", return_value=0):
                    records = self.execute(client_with([
                        status_error(headers=headers),
                        *[reply(turn) for turn in range(1, 11)],
                    ]))
                self.sleep.assert_called_once_with(delay)
                self.assertEqual(records[0]["retries"], 1)

    def test_failed_sdk_response_code_is_retryable(self):
        failed = {"id": "failed", "status": "failed", "error": {
            "code": "rate_limit_exceeded", "message": "Token limit reached",
        }}
        records = self.execute(client_with([SDKValue(failed),
                                           *[reply(turn) for turn in range(1, 11)]]))
        self.sleep.assert_called_once_with(60)
        self.assertEqual(records[0]["retries"], 1)
        self.assertTrue(any("no usable reset hint" in call.args[1]
                            for call in self.chat.call_args_list))

    def test_failed_response_message_retry_after_is_honored(self):
        failed = {"status": "failed", "error": {
            "code": "rate_limit_exceeded", "message": "Retry after 20 seconds",
        }}
        records = self.execute(client_with([SDKValue(failed),
                                           *[reply(turn) for turn in range(1, 11)]]))
        self.sleep.assert_called_once_with(20)
        self.assertEqual(records[0]["retries"], 1)
        self.assertFalse(any("fallback wait" in call.args[1]
                             for call in self.chat.call_args_list))

    def test_message_retry_hint_above_cap_never_retries_prematurely(self):
        client = client_with([{"status": "failed", "error": {
            "code": "rate_limit_exceeded", "message": "Retry after 180 seconds",
        }}, *[reply(turn) for turn in range(1, 11)]])
        with self.assertRaisesRegex(ValidationError, "refusing to retry prematurely"):
            self.execute(client)
        self.assert_failed()
        self.sleep.assert_not_called()
        self.assertEqual(client.responses.create.call_count, 1)

    def test_message_delays_support_relative_units_compounds_and_nested_json(self):
        for message, expected in [
            ("Please retry after 1500 milliseconds.", 1.5),
            ("Please retry after 1 minute 20 seconds.", 80),
            ("Please try again in 1m30s.", 90),
            (json.dumps({"error": {"message": "Retry after 25 seconds"}}), 25),
        ]:
            with self.subTest(message=message):
                self.run = ValidationRun("message reset")
                self.sleep.reset_mock()
                failed = {"status": "failed", "error": {
                    "code": "rate_limit_exceeded", "message": message,
                }}
                self.execute(client_with([failed, *[reply(turn) for turn in range(1, 11)]]))
                self.sleep.assert_called_once_with(expected)

    def test_message_and_http_hints_use_the_longer_server_wait(self):
        for header, message, expected in [("40", "Retry after 20 seconds", 40),
                                          ("5", "Retry after 20 seconds", 20)]:
            with self.subTest(header=header, message=message):
                self.run = ValidationRun("combined reset")
                self.sleep.reset_mock()
                error = status_error(headers={"retry-after": header}, body={
                    "error": {"code": "rate_limit_exceeded", "message": message},
                })
                self.execute(client_with([error, *[reply(turn) for turn in range(1, 11)]]))
                self.sleep.assert_called_once_with(expected)

    def test_failed_response_nested_json_status_and_headers(self):
        failed = {"status": "failed", "error": {"code": "server_error", "message": json.dumps({
            "error": {"status": 429, "message": "Token limit",
                      "headers": {"retry-after-ms": "1750"}},
        })}}
        records = self.execute(client_with([failed, *[reply(turn) for turn in range(1, 11)]]))
        self.sleep.assert_called_once_with(1.75)
        self.assertEqual(records[0]["retries"], 1)

    def test_failed_response_message_with_status_429(self):
        failed = {"status": "failed", "error": {"message": "Upstream HTTP status: 429"}}
        self.execute(client_with([failed, *[reply(turn) for turn in range(1, 11)]]),
                     fallback_wait_seconds=4)
        self.sleep.assert_called_once_with(4)

    def test_exception_without_reset_warns_and_uses_configured_fallback(self):
        self.execute(client_with([status_error(), *[reply(turn) for turn in range(1, 11)]]),
                     fallback_wait_seconds=5)
        self.sleep.assert_called_once_with(5)
        self.assertTrue(any("fallback wait of 5 seconds" in call.args[1]
                            and call.kwargs.get("status") == "warning"
                            for call in self.chat.call_args_list))

    def test_reset_above_max_fails_instead_of_sleeping_or_retrying(self):
        client = client_with([status_error(headers={"retry-after": "121"})])
        with self.assertRaisesRegex(ValidationError, "refusing to retry prematurely"):
            self.execute(client)
        self.assert_failed()
        self.sleep.assert_not_called()
        self.assertEqual(client.responses.create.call_count, 1)
        self.assertEqual(client.conversations.items.create.call_count, 1)
        self.assertEqual(self.run.results[-1].evidence["required_wait_seconds"], 121)

    def test_fallback_above_configured_max_does_not_retry(self):
        with self.assertRaisesRegex(ValidationError, "exceeds max_wait_seconds=30"):
            self.execute(client_with([status_error()]), max_wait_seconds=30)
        self.sleep.assert_not_called()
        self.assert_failed()

    def test_wait_exactly_at_cap_is_allowed(self):
        self.execute(client_with([status_error(headers={"retry-after": "120"}),
                                  *[reply(turn) for turn in range(1, 11)]]))
        self.sleep.assert_called_once_with(120)

    def test_configured_higher_cap_honors_full_server_wait(self):
        self.execute(client_with([status_error(headers={"retry-after": "180"}),
                                  *[reply(turn) for turn in range(1, 11)]]),
                     max_wait_seconds=200)
        self.sleep.assert_called_once_with(180)

    def test_repeated_429_stops_after_one_retry_and_one_user_append(self):
        client = client_with([status_error(headers={"retry-after": "1"}), status_error()])
        with self.assertRaisesRegex(ValidationError, "single permitted retry"):
            self.execute(client)
        self.assert_failed()
        self.assertEqual(client.responses.create.call_count, 2)
        self.assertEqual(client.conversations.items.create.call_count, 1)
        self.assertEqual(client.responses.create.call_args_list[0],
                         client.responses.create.call_args_list[1])
        self.sleep.assert_called_once_with(1)
        self.assertEqual(len(self.run.results), 1)
        self.assertEqual(self.run.results[0].evidence["retries"], 1)

    def test_repeated_failed_response_stops_after_one_retry(self):
        failed = {"status": "failed", "error": {"code": "rate_limit_exceeded"}}
        client = client_with([failed, failed])
        with self.assertRaisesRegex(ValidationError, "single permitted retry"):
            self.execute(client)
        self.assertEqual(client.responses.create.call_count, 2)
        self.assertEqual(client.conversations.items.create.call_count, 1)
        self.sleep.assert_called_once_with(60)
        self.assert_failed()

    def test_quota_403_and_429_are_terminal_even_with_retry_header(self):
        for status, code, message in [
            (403, "quota_exceeded", "Quota exhausted"),
            (429, "insufficient_quota", "Please check billing"),
            (429, "rate_limit_exceeded", "You exceeded your current quota"),
        ]:
            with self.subTest(status=status, code=code):
                self.run = ValidationRun("quota")
                client = client_with([status_error(status, headers={"retry-after": "1"}, body={
                    "error": {"code": code, "message": message},
                })])
                with self.assertRaisesRegex(ValidationError, "quota.*no retry"):
                    self.execute(client)
                self.assert_failed()
                self.sleep.assert_not_called()
                self.assertEqual(client.responses.create.call_count, 1)

    def test_failed_response_insufficient_quota_is_terminal(self):
        client = client_with([{"status": "failed", "error": {"code": "insufficient_quota"}}])
        with self.assertRaisesRegex(ValidationError, "quota.*no retry"):
            self.execute(client)
        self.sleep.assert_not_called()
        self.assert_failed()

    def test_quota_on_retry_stops_without_additional_sleep(self):
        client = client_with([
            status_error(headers={"retry-after": "1"}),
            status_error(body={"error": {"code": "insufficient_quota"}}),
        ])
        with self.assertRaisesRegex(ValidationError, "quota.*no retry"):
            self.execute(client)
        self.assertEqual(client.responses.create.call_count, 2)
        self.sleep.assert_called_once_with(1)
        self.assert_failed()

    def test_failed_response_nested_quota_is_terminal(self):
        client = client_with([{"status": "failed", "error": {"message": json.dumps({
            "status": 403, "error": {"code": "insufficient_quota"},
        })}}])
        with self.assertRaisesRegex(ValidationError, "quota.*no retry"):
            self.execute(client)
        self.sleep.assert_not_called()
        self.assert_failed()

    def test_other_http_errors_never_retry_even_if_body_mentions_rate_limit(self):
        for status in [400, 401, 403, 404, 500, 503]:
            with self.subTest(status=status):
                self.run = ValidationRun("terminal")
                client = client_with([status_error(status)])
                with self.assertRaisesRegex(ValidationError, "not a retryable"):
                    self.execute(client)
                self.assert_failed()
                self.assertEqual(client.responses.create.call_count, 1)
        self.sleep.assert_not_called()

    def test_connection_error_never_retries(self):
        transport = sdk_transport()
        error = openai.APIConnectionError(request=transport.Request("POST", "https://example.org"))
        client = client_with([error])
        with self.assertRaisesRegex(ValidationError, "only rate limits are retried"):
            self.execute(client)
        self.assert_failed()
        self.sleep.assert_not_called()
        self.assertEqual(client.responses.create.call_count, 1)

    def test_unexpected_exception_is_logged_and_reraised(self):
        client = client_with([RuntimeError("unexpected SDK bug")])
        with self.assertRaisesRegex(RuntimeError, "unexpected SDK bug"):
            self.execute(client)
        self.assert_failed()
        self.assertEqual(self.run.results[-1].evidence["error_type"], "RuntimeError")
        self.sleep.assert_not_called()

    def test_user_append_error_is_never_retried(self):
        client = client_with()
        client.conversations.items.create.side_effect = status_error(headers={"retry-after": "1"})
        with self.assertRaisesRegex(ValidationError, "will not be repeated"):
            self.execute(client)
        client.responses.create.assert_not_called()
        client.conversations.items.create.assert_called_once()
        self.sleep.assert_not_called()
        self.assert_failed()

    def test_unknown_user_append_error_is_logged_and_reraised(self):
        client = client_with()
        client.conversations.items.create.side_effect = RuntimeError("append SDK bug")
        with self.assertRaisesRegex(RuntimeError, "append SDK bug"):
            self.execute(client)
        client.responses.create.assert_not_called()
        self.assert_failed()

    def test_conversation_creation_error_is_never_retried(self):
        client = client_with()
        client.conversations.create.side_effect = status_error()
        with self.assertRaisesRegex(ValidationError, "conversation creation failed"):
            self.execute(client)
        client.conversations.create.assert_called_once()
        client.responses.create.assert_not_called()
        client.conversations.items.create.assert_not_called()
        self.assert_failed("hr/conversation")

    def test_missing_conversation_id_fails_before_messages(self):
        client = client_with()
        client.conversations.create.return_value = {}
        with self.assertRaisesRegex(ValidationError, "no conversation ID"):
            self.execute(client)
        self.assert_failed("hr/conversation")
        client.conversations.items.create.assert_not_called()

    def test_unknown_conversation_error_is_logged_and_reraised(self):
        client = client_with()
        client.conversations.create.side_effect = RuntimeError("conversation SDK bug")
        with self.assertRaisesRegex(RuntimeError, "conversation SDK bug"):
            self.execute(client)
        self.assert_failed("hr/conversation")
        client.conversations.items.create.assert_not_called()

    def test_malformed_or_noncompleted_success_is_explicit_failure(self):
        cases = [
            None, [], {}, {**reply(), "id": None}, {**reply(), "output": None},
            {**reply(), "output": []}, {**reply(), "status": "incomplete",
                                      "incomplete_details": {"reason": "max_output_tokens"}},
            {**reply(), "status": "in_progress"}, {**reply(), "status": None},
            {**reply(), "usage": "invalid"}, {**reply(), "error": {"code": "server_error"}},
            {"status": "failed", "error": {"code": "server_error", "message": "broken"}},
        ]
        for response in cases:
            with self.subTest(response=response):
                self.run = ValidationRun("malformed")
                client = client_with([response])
                with self.assertRaises(ValidationError):
                    self.execute(client)
                self.assert_failed()
                self.assertEqual(client.responses.create.call_count, 1)
        self.sleep.assert_not_called()

    def test_tool_call_refusal_empty_text_or_user_message_is_not_assistant_success(self):
        outputs = [
            [{"type": "web_search_call", "status": "completed"}],
            [{"type": "message", "role": "assistant", "content": [
                {"type": "refusal", "refusal": "No"}]}],
            [{"type": "message", "role": "assistant", "content": [
                {"type": "output_text", "text": "  ", "annotations": []}]}],
            [{"type": "message", "role": "user", "content": [
                {"type": "output_text", "text": "Not an answer"}]}],
        ]
        for output in outputs:
            with self.subTest(output=output):
                self.run = ValidationRun("no output")
                with self.assertRaisesRegex(ValidationError, "no nonempty assistant"):
                    self.execute(client_with([{**reply(), "output": output}]))
                self.assert_failed()

    def test_uncited_reply_is_not_given_fabricated_web_evidence(self):
        records = self.execute(client_with([reply(turn, cited=False) for turn in range(1, 11)]))
        self.assertTrue(all(not row["citations"] and not row["web_search_calls"] for row in records))

    def test_multiple_output_text_parts_and_annotated_citations_are_preserved(self):
        data = reply(cited=False)
        data["output"][0]["content"].extend([
            {"type": "output_text", "text": "Second paragraph", "annotations": [
                {"type": "url_citation", "title": "Actual title", "url": "https://example.org/real"},
                {"type": "url_citation", "title": "Duplicate", "url": "https://example.org/real"},
                {"type": "file_citation", "file_id": "not-a-web-source"},
            ]},
        ])
        records = self.execute(client_with([data, *[reply(turn) for turn in range(2, 11)]]))
        self.assertEqual(records[0]["assistant"], "HR answer 1\nSecond paragraph")
        self.assertEqual(records[0]["citations"], [
            {"title": "Actual title", "url": "https://example.org/real"},
        ])

    def test_error_payloads_and_nested_messages_are_redacted_before_display(self):
        error = status_error(403, body={"error": {
            "code": "quota_exceeded", "api_key": "never-print-this-key",
            "message": "Authorization: Bearer never-print-this-bearer",
        }})
        with self.assertRaises(ValidationError):
            self.execute(client_with([error]))
        evidence = str(self.run.results[-1].evidence)
        rendered = str(self.chat.call_args_list)
        for secret in ["never-print-this-key", "never-print-this-bearer"]:
            self.assertNotIn(secret, evidence)
            self.assertNotIn(secret, rendered)
        self.assertIn("[REDACTED]", evidence)

    def test_success_sdk_result_and_chat_are_redacted_without_altering_sdk_input(self):
        data = reply()
        data["api_key"] = "do-not-display"
        data["output"][1]["content"][0]["text"] = "Bearer hidden-token"
        records = self.execute(client_with([data, *[reply(turn) for turn in range(2, 11)]]))
        self.assertEqual(records[0]["assistant"], "Bearer [REDACTED]")
        self.assertNotIn("do-not-display", str(self.chat.call_args_list))
        self.assertNotIn("hidden-token", str(self.run.results[0].evidence))

    def test_invalid_prompt_count_content_or_type_fails_before_cloud_calls(self):
        for prompts in [[], PROMPTS[:-1], PROMPTS + ["extra"], "not a sequence of prompts",
                        iter(PROMPTS), [*PROMPTS[:-1], ""], [*PROMPTS[:-1], " "],
                        [*PROMPTS[:-1], 4]]:
            with self.subTest(prompts=prompts):
                run, client = ValidationRun("input"), client_with()
                with self.assertRaisesRegex(ValidationError, "exactly 10"):
                    foundrychat.run_hr_conversation(client, "agent", "1", prompts, run)
                client.conversations.create.assert_not_called()
                self.assertEqual(run.results[-1].status, "FAIL")

    def test_invalid_waits_are_rejected_before_cloud_calls(self):
        for name in ["max_wait_seconds", "fallback_wait_seconds"]:
            for value in [0, -1, float("nan"), float("inf"), True, "60", None]:
                with self.subTest(name=name, value=value):
                    self.run = ValidationRun("wait")
                    client = client_with()
                    with self.assertRaisesRegex(ValidationError, "finite positive"):
                        self.execute(client, **{name: value})
                    client.conversations.create.assert_not_called()
                    self.assert_failed("hr/configuration")

    def test_agent_identity_is_required(self):
        for name, version in [("", "1"), ("agent", ""), ("agent", 1), (None, "1")]:
            with self.subTest(name=name, version=version):
                run, client = ValidationRun("agent"), client_with()
                with self.assertRaisesRegex(ValidationError, "agent name and version"):
                    foundrychat.run_hr_conversation(client, name, version, PROMPTS, run)
                client.conversations.create.assert_not_called()

    def test_invisible_sdk_retries_are_rejected(self):
        for retry_count in [None, 1, 2]:
            with self.subTest(retry_count=retry_count):
                self.run = ValidationRun("SDK retry")
                client = client_with()
                client.max_retries = retry_count
                with self.assertRaisesRegex(ValidationError, "max_retries=0"):
                    self.execute(client)
                client.conversations.create.assert_not_called()
                self.assert_failed("hr/configuration")

    def test_later_failure_leaves_prior_passes_and_aborts_remaining_turns(self):
        client = client_with([reply(1), reply(2), status_error(500)])
        with self.assertRaises(ValidationError):
            self.execute(client)
        self.assertEqual([(row.case, row.status) for row in self.run.results], [
            ("hr/turn-1", "PASS"), ("hr/turn-2", "PASS"), ("hr/turn-3", "FAIL"),
        ])
        self.assertEqual(client.conversations.items.create.call_count, 3)
        self.assertEqual(client.responses.create.call_count, 3)

    def test_supplied_conversation_and_transcript_preserve_cleanup_ownership(self):
        transcript = []
        client = client_with()
        records = self.execute(client, conversation_id="owned-conversation", transcript=transcript)
        client.conversations.create.assert_not_called()
        self.assertIs(records, transcript)
        self.assertEqual(len(transcript), 10)
        self.assertTrue(all(row["conversation_id"] == "owned-conversation" for row in transcript))
        self.assertEqual(client.responses.create.call_args.kwargs["conversation"], "owned-conversation")

    def test_supplied_transcript_retains_completed_turns_after_failure(self):
        transcript = []
        client = client_with([reply(1), reply(2), status_error(500)])
        with self.assertRaises(ValidationError):
            self.execute(client, conversation_id="owned-conversation", transcript=transcript)
        client.conversations.create.assert_not_called()
        self.assertEqual([row["turn"] for row in transcript], [1, 2])
        self.assertTrue(all(row["conversation_id"] == "owned-conversation" for row in transcript))
        self.assert_failed("hr/turn-3")

    def test_invalid_supplied_conversation_id_is_rejected(self):
        for conversation_id in ["", " ", 5]:
            with self.subTest(conversation_id=conversation_id):
                self.run = ValidationRun("conversation input")
                with self.assertRaisesRegex(ValidationError, "conversation_id must"):
                    self.execute(conversation_id=conversation_id)
                self.client.conversations.create.assert_not_called()
                self.assert_failed("hr/configuration")

    def test_nonempty_transcript_is_not_replayed(self):
        for transcript in [[{"turn": 1}], {}, ()]:
            with self.subTest(transcript=transcript):
                self.run = ValidationRun("transcript input")
                with self.assertRaisesRegex(ValidationError, "empty list"):
                    self.execute(transcript=transcript)
                self.client.conversations.create.assert_not_called()
                self.assert_failed("hr/configuration")

    def test_standalone_shared_import(self):
        shared_path = str(Path(__file__).resolve().parents[2] / "shared")
        with patch.object(sys, "path", [shared_path, *sys.path]):
            standalone = importlib.import_module("foundrychat")
            self.assertTrue(callable(standalone.run_hr_conversation))
            self.assertEqual(standalone.retry_delay({"retry-after": "2"}), 2)


if __name__ == "__main__":
    unittest.main()
