#!/usr/bin/env python3
import argparse
import csv
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CASES = ROOT / "tools" / "prompt_lookup_benchmark_cases.json"


def run(command, *, env=None, cwd=ROOT, check=True):
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if check and result.returncode != 0:
        tail = "\n".join(result.stdout.splitlines()[-80:])
        raise RuntimeError(f"Command failed: {' '.join(command)}\n{tail}")
    return result


def build_app(configuration):
    run([
        "xcodebuild",
        "build",
        "-project",
        "Voxt.xcodeproj",
        "-scheme",
        "Voxt",
        "-configuration",
        configuration,
        "-destination",
        "platform=macOS",
        "CODE_SIGNING_ALLOWED=NO",
    ])


def resolve_app_binary(configuration):
    result = run([
        "xcodebuild",
        "-showBuildSettings",
        "-json",
        "-project",
        "Voxt.xcodeproj",
        "-scheme",
        "Voxt",
        "-configuration",
        configuration,
        "-destination",
        "platform=macOS",
        "CODE_SIGNING_ALLOWED=NO",
    ])
    json_start = result.stdout.find("[")
    if json_start < 0:
        raise RuntimeError("xcodebuild did not return JSON build settings.")
    settings_sets = json.loads(result.stdout[json_start:])
    settings = None
    for candidate in settings_sets:
        if candidate.get("target") == "Voxt":
            settings = candidate.get("buildSettings", {})
            break
    if settings is None:
        settings = settings_sets[0].get("buildSettings", {})
    executable_path = settings.get("EXECUTABLE_PATH")
    target_build_dir = settings.get("TARGET_BUILD_DIR")
    if not executable_path or not target_build_dir:
        raise RuntimeError("Unable to resolve built app executable path from xcodebuild settings.")
    return Path(target_build_dir) / executable_path


def parse_metric(output, name):
    matches = re.findall(rf"{re.escape(name)}=([^\s]+)", output)
    if not matches:
        return None
    value = matches[-1]
    if value == "n/a":
        return None
    if value.isdigit():
        return int(value)
    try:
        return float(value)
    except ValueError:
        return value


def parse_output_block(output):
    marker = "[VOXT_SMOKE][output]\n"
    index = output.rfind(marker)
    if index < 0:
        return None
    return output[index + len(marker):].rstrip("\n")


def parse_smoke_output(output):
    metric = {
        "avgElapsedMs": parse_metric(output, "avgElapsedMs"),
        "hotAvgElapsedMs": parse_metric(output, "hotAvgElapsedMs"),
        "avgPrefillMs": parse_metric(output, "avgPrefillMs"),
        "hotAvgPrefillMs": parse_metric(output, "hotAvgPrefillMs"),
        "avgGenerationMs": parse_metric(output, "avgGenerationMs"),
        "hotAvgGenerationMs": parse_metric(output, "hotAvgGenerationMs"),
        "avgPromptTokens": parse_metric(output, "avgPromptTokens"),
        "avgCompletionTokens": parse_metric(output, "avgCompletionTokens"),
        "avgPromptLookupDraftTokens": parse_metric(output, "avgPromptLookupDraftTokens"),
        "avgPromptLookupProposedTokens": parse_metric(output, "avgPromptLookupProposedTokens"),
        "avgPromptLookupAcceptedTokens": parse_metric(output, "avgPromptLookupAcceptedTokens"),
        "avgPromptLookupAcceptanceRatio": parse_metric(output, "avgPromptLookupAcceptanceRatio"),
        "promptLookupFallback": parse_metric(output, "promptLookupFallback"),
        "finalOutput": parse_output_block(output),
    }
    elapsed = metric["hotAvgElapsedMs"] or metric["avgElapsedMs"]
    metric["elapsedMs"] = elapsed
    return metric


def run_smoke(binary, case, *, repo, iterations, prompt_lookup, prefill_step):
    env = os.environ.copy()
    env.update({
        "VOXT_LLM_SMOKE_TASK": "enhancement",
        "VOXT_LLM_SMOKE_ENHANCEMENT_TEXT": case["text"],
        "VOXT_LLM_SMOKE_LOCAL_REPO": repo,
        "VOXT_LLM_SMOKE_ITERATIONS": str(iterations),
        "VOXT_LLM_SMOKE_PREWARM": "1",
        "VOXT_LLM_SMOKE_PROMPT_LOOKUP": "1" if prompt_lookup else "0",
    })
    if prefill_step is not None:
        env["VOXT_LLM_SMOKE_PREFILL_STEP"] = str(prefill_step)
    result = run([str(binary)], env=env, check=False)
    if result.returncode != 0:
        tail = "\n".join(result.stdout.splitlines()[-80:])
        raise RuntimeError(f"Smoke run failed for {case['id']} prompt_lookup={prompt_lookup}\n{tail}")
    return parse_smoke_output(result.stdout)


def load_cases(path, limit):
    with path.open("r", encoding="utf-8") as handle:
        cases = json.load(handle)
    if limit is not None:
        cases = cases[:limit]
    for case in cases:
        if not case.get("id") or not case.get("text"):
            raise RuntimeError(f"Invalid benchmark case: {case}")
    return cases


def filter_cases_by_category(cases, categories):
    if not categories:
        return cases
    requested = {category.strip() for category in categories if category.strip()}
    return [case for case in cases if case.get("category") in requested]


def percent_delta(baseline, candidate):
    if not baseline or not candidate:
        return None
    return ((baseline - candidate) / baseline) * 100.0


def main():
    parser = argparse.ArgumentParser(description="Benchmark Voxt custom LLM prompt lookup decoding.")
    parser.add_argument("--cases", type=Path, default=DEFAULT_CASES)
    parser.add_argument("--repo", default="mlx-community/gemma-4-e2b-it-4bit")
    parser.add_argument("--configuration", default="Debug")
    parser.add_argument("--iterations", type=int, default=2)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--category", action="append")
    parser.add_argument("--prefill-step", type=int)
    parser.add_argument("--app-binary", type=Path)
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--csv", type=Path)
    args = parser.parse_args()

    cases = filter_cases_by_category(
        load_cases(args.cases, args.limit),
        args.category,
    )
    if not cases:
        raise RuntimeError("No benchmark cases matched the requested filters.")
    if args.app_binary:
        binary = args.app_binary
    else:
        if not args.no_build:
            build_app(args.configuration)
        binary = resolve_app_binary(args.configuration)
    if not binary.exists():
        raise RuntimeError(f"Built app binary does not exist: {binary}")

    csv_path = args.csv or (ROOT / "tmp" / f"prompt_lookup_benchmark_{int(time.time())}.csv")
    csv_path.parent.mkdir(parents=True, exist_ok=True)

    rows = []
    print(f"binary={binary}")
    print(f"repo={args.repo} cases={len(cases)} iterations={args.iterations}")
    print("case,category,chars,off_ms,on_ms,speedup_pct,output_match,on_draft_tokens,on_proposed_tokens,on_accepted_tokens,on_acceptance_ratio,on_fallback")

    for case in cases:
        off = run_smoke(
            binary,
            case,
            repo=args.repo,
            iterations=args.iterations,
            prompt_lookup=False,
            prefill_step=args.prefill_step,
        )
        on = run_smoke(
            binary,
            case,
            repo=args.repo,
            iterations=args.iterations,
            prompt_lookup=True,
            prefill_step=args.prefill_step,
        )
        speedup = percent_delta(off["elapsedMs"], on["elapsedMs"])
        output_match = off["finalOutput"] == on["finalOutput"]
        row = {
            "id": case["id"],
            "origin": case.get("origin", ""),
            "category": case.get("category", ""),
            "chars": len(case["text"]),
            "off_elapsed_ms": off["elapsedMs"],
            "on_elapsed_ms": on["elapsedMs"],
            "speedup_pct": None if speedup is None else round(speedup, 2),
            "output_match": output_match,
            "off_prefill_ms": off["hotAvgPrefillMs"] or off["avgPrefillMs"],
            "on_prefill_ms": on["hotAvgPrefillMs"] or on["avgPrefillMs"],
            "off_generation_ms": off["hotAvgGenerationMs"] or off["avgGenerationMs"],
            "on_generation_ms": on["hotAvgGenerationMs"] or on["avgGenerationMs"],
            "on_draft_tokens": on["avgPromptLookupDraftTokens"],
            "on_proposed_tokens": on["avgPromptLookupProposedTokens"],
            "on_accepted_tokens": on["avgPromptLookupAcceptedTokens"],
            "on_acceptance_ratio": on["avgPromptLookupAcceptanceRatio"],
            "on_fallback": on["promptLookupFallback"] or "",
        }
        rows.append(row)
        speedup_text = "n/a" if speedup is None else f"{speedup:.2f}"
        print(
            f"{row['id']},{row['category']},{row['chars']},{row['off_elapsed_ms']},"
            f"{row['on_elapsed_ms']},{speedup_text},{str(output_match).lower()},{row['on_draft_tokens']},"
            f"{row['on_proposed_tokens']},{row['on_accepted_tokens']},"
            f"{row['on_acceptance_ratio']},{row['on_fallback']}"
        )

    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    valid = [row for row in rows if row["off_elapsed_ms"] and row["on_elapsed_ms"]]
    if valid:
        avg_off = sum(row["off_elapsed_ms"] for row in valid) / len(valid)
        avg_on = sum(row["on_elapsed_ms"] for row in valid) / len(valid)
        avg_speedup = percent_delta(avg_off, avg_on)
        print(f"summary_avg_off_ms={avg_off:.1f}")
        print(f"summary_avg_on_ms={avg_on:.1f}")
        print(f"summary_speedup_pct={avg_speedup:.2f}")
        categories = sorted({row["category"] for row in valid if row.get("category")})
        for category in categories:
            category_rows = [row for row in valid if row.get("category") == category]
            category_avg_off = sum(row["off_elapsed_ms"] for row in category_rows) / len(category_rows)
            category_avg_on = sum(row["on_elapsed_ms"] for row in category_rows) / len(category_rows)
            category_speedup = percent_delta(category_avg_off, category_avg_on)
            output_matches = sum(1 for row in category_rows if row["output_match"])
            print(
                f"summary_category={category} cases={len(category_rows)} output_match={output_matches}/{len(category_rows)} "
                f"avg_off_ms={category_avg_off:.1f} avg_on_ms={category_avg_on:.1f} speedup_pct={category_speedup:.2f}"
            )
    print(f"csv={csv_path}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception as error:
        print(f"error={error}", file=sys.stderr)
        sys.exit(1)
