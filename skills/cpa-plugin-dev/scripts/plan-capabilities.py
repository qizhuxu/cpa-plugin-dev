#!/usr/bin/env python3
"""Turn a chosen capability list into the phase-1 deliverables.

Usage:
    plan-capabilities.py <capability> [<capability> ...] [--id <plugin-id>]

This is the phase-1 to phase-2 handoff. Given the capability keys you decided
on, it prints:

  * the exact capabilities object to return from plugin.register
  * every method the dispatch must handle, so nothing is declared but left
    unimplemented
  * a plugins.configs block for the CPA config
  * warnings for modifier keys used without their base capability

Run with no arguments to list the available capabilities.

check-capabilities.py validates the result after the code is written; this
script produces the plan before any code exists.
"""
from __future__ import annotations

import sys

# key -> (methods the dispatch must handle, description)
CAPABILITIES = {
    "model_registrar": (("ModelRegister",), "register static model metadata"),
    "model_provider": (("ModelStatic", "ModelForAuth"), "serve static and per-auth models"),
    "auth_provider": (("AuthIdentifier", "AuthParse", "AuthLoginStart",
                       "AuthLoginPoll", "AuthRefresh"),
                      "parse, log in, poll and refresh credentials"),
    "frontend_auth_provider": (("FrontendAuthIdentifier", "FrontendAuthAuthenticate"),
                               "authenticate client requests before proxying"),
    "frontend_auth_provider_exclusive": ((), "modifier: become the only request auth"),
    "scheduler": (("SchedulerPick",), "choose an auth candidate"),
    "scheduler_across_priorities": ((), "modifier: see candidates across priority tiers"),
    "model_router": (("ModelRoute",), "route requests before provider selection"),
    "executor": (("ExecutorIdentifier", "ExecutorExecute", "ExecutorExecuteStream",
                  "ExecutorCountTokens", "ExecutorHTTPRequest"),
                 "execute upstream requests"),
    "request_translator": (("RequestTranslate",), "canonical request to provider payload"),
    "request_normalizer": (("RequestNormalize",), "normalize incoming requests"),
    "request_interceptor": (("RequestInterceptBefore", "RequestInterceptAfter"),
                            "rewrite requests around credential selection"),
    "request_lifecycle_plugin": (("RequestComplete",), "receive terminal request events"),
    "response_translator": (("ResponseTranslate",), "canonical response to client payload"),
    "response_before_translator": (("ResponseNormalizeBefore",), "normalize before translation"),
    "response_after_translator": (("ResponseNormalizeAfter",), "normalize after translation"),
    "response_interceptor": (("ResponseInterceptAfter",), "rewrite non-streaming responses"),
    "response_stream_interceptor": (("ResponseInterceptStreamChunk",), "rewrite stream chunks"),
    "websocket_response_observer": (("WebSocketResponseEvent",),
                                    "observe upstream websocket events"),
    "thinking_applier": (("ThinkingIdentifier", "ThinkingApply"), "apply thinking configuration"),
    "usage_plugin": (("UsageHandle",), "receive usage records"),
    "command_line_plugin": (("CommandLineRegister", "CommandLineExecute"), "own CLI flags"),
    "management_api": (("ManagementRegister", "ManagementHandle"),
                       "management routes and resource pages"),
    "quota_provider": (("QuotaIdentifier", "QuotaDescribe", "QuotaFetch", "QuotaReset"),
                       "surface credential quota"),
}

MODIFIERS = ("executor_model_scope", "executor_input_formats", "executor_output_formats")
VALID = set(CAPABILITIES) | set(MODIFIERS)

ENTRY = ("executor", "scheduler", "model_router", "auth_provider", "frontend_auth_provider")
PROCESSING = ("request_translator", "request_normalizer", "response_translator",
              "response_before_translator", "response_after_translator",
              "response_interceptor", "response_stream_interceptor")

NL = chr(10)


def usage():
    print(__doc__)
    print("available capabilities:")
    for key in sorted(CAPABILITIES):
        methods, desc = CAPABILITIES[key]
        tag = "modifier" if not methods else "%d method" % len(methods)
        print("  %-34s %-9s %s" % (key, tag, desc))
    print()
    print("modifier keys, emitted automatically when executor is selected:")
    for key in MODIFIERS:
        print("  " + key)
    return 0


def main(argv):
    args = list(argv[1:])
    plugin_id = "my-plugin"
    if "--id" in args:
        i = args.index("--id")
        if i + 1 >= len(args):
            print("error: --id needs a value", file=sys.stderr)
            return 2
        plugin_id = args[i + 1]
        del args[i:i + 2]

    if not args:
        return usage()

    unknown = [a for a in args if a not in VALID]
    if unknown:
        print("error: unknown capability key(s): %s" % ", ".join(unknown), file=sys.stderr)
        print("       run with no arguments to list the valid keys", file=sys.stderr)
        return 2

    selected = sorted(a for a in args if a in CAPABILITIES)
    notes = []

    if "frontend_auth_provider_exclusive" in selected and "frontend_auth_provider" not in selected:
        notes.append("frontend_auth_provider_exclusive requires frontend_auth_provider")
    if "scheduler_across_priorities" in selected and "scheduler" not in selected:
        notes.append("scheduler_across_priorities requires scheduler")
    if "executor" in selected and not any(k in args for k in MODIFIERS):
        notes.append("executor selected; the three modifier keys are emitted below with defaults")

    only_entry = [k for k in selected if k in ENTRY]
    if only_entry and not any(k in selected for k in PROCESSING):
        notes.append("only entry capabilities selected. Entry capabilities take part in "
                     "routing decisions, so a failure affects more traffic. Prefer a "
                     "processing capability whenever it can express the requirement.")

    print("1) capabilities object for the plugin.register response")
    print()
    print('  "capabilities": {')
    body = ['    "%s": true' % key for key in selected]
    if "executor" in selected:
        body.append('    "executor_model_scope": "both"')
        body.append('    "executor_input_formats": ["chat-completions"]')
        body.append('    "executor_output_formats": ["chat-completions"]')
    print((",\n" if False else ("," + NL)).join(body))
    print("  }")
    print()

    methods = []
    for key in selected:
        methods.extend(CAPABILITIES[key][0])
    print("2) methods the dispatch must handle (%d)" % (len(methods) + 3))
    print()
    for m in methods:
        print("    pluginabi.Method%s" % m)
    print("    pluginabi.MethodPluginRegister")
    print("    pluginabi.MethodPluginReconfigure")
    print("    default branch -> unknown_method error envelope")
    print()

    print("3) plugins.configs block")
    print()
    print("plugins:")
    print("  enabled: true")
    print('  dir: "plugins"')
    print("  configs:")
    print("    %s:" % plugin_id)
    print("      enabled: true")
    print("      priority: %d" % (10 if only_entry else 1))
    print('      mode: "safe"        # replace with your own fields')
    print()

    print("4) verify before moving on")
    print()
    print("    scripts/check-capabilities.py <plugin-dir>    declaration vs dispatch")
    print("    scripts/verify-plugin.sh %s    registered and effective_enabled" % plugin_id)
    print()

    if notes:
        print("attention:")
        for n in notes:
            print("  - " + n)
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
