"""Audit paired, frozen-baseline AI matches and retain one reproducible report."""
from __future__ import annotations

import argparse
import collections
import copy
import hashlib
import json
import pathlib
import statistics

ROOT = pathlib.Path(__file__).resolve().parents[1]

def baseline_identity(value: dict) -> dict:
    result = copy.deepcopy(value)
    for record in result["files"].values():
        record.pop("canonical_lf_sha256", None)
    return result


def summarize(paths: list[pathlib.Path], expected_games: int = 100, minimum_wins: int = 70) -> dict:
    reports = [json.loads(path.read_text(encoding="utf-8")) for path in paths]
    if not reports:
        raise ValueError("No benchmark reports supplied")
    first = reports[0]
    games: list[dict] = []
    for report in reports:
        if report.get("baseline_control") or report.get("opening_only"):
            raise ValueError("Control games and opening-only replays are not candidate strength matches")
        for key in ("baseline", "hashes", "mirror_factions", "seed_base", "max_turns", "max_commands"):
            left = baseline_identity(report[key]) if key == "baseline" else report[key]
            right = baseline_identity(first[key]) if key == "baseline" else first[key]
            if left != right:
                raise ValueError(f"Mixed benchmark versions or conditions: {key}")
        if report["illegal"]:
            raise ValueError("A benchmark reported an illegal action, RNG mutation or conservation failure")
        if len(report["games"]) != 2 * report["pairs"]:
            raise ValueError("A shard has not completed its planned matches")
        counts = collections.Counter(game["outcome"] for game in report["games"])
        for label, key in (("win", "wins"), ("loss", "losses"), ("draw", "draws"), ("unfinished", "unfinished")):
            if counts[label] != report[key]:
                raise ValueError(f"Shard outcome totals disagree with its games: {key}")
        games.extend(report["games"])
    if not first["mirror_factions"]:
        raise ValueError("Strength acceptance requires equal-faction paired games")
    keys = [(game["seed"], game["challenger"]) for game in games]
    if len(set(keys)) != len(keys) or len(games) != expected_games:
        raise ValueError(f"Expected {expected_games} unique games, received {len(games)}")
    pairs: dict[int, list[dict]] = collections.defaultdict(list)
    for game in games:
        pairs[game["seed"]].append(game)
        if game["factions"] != [game["faction"], game["faction"]]:
            raise ValueError("A mirror fixture has different factions")
    if any(sorted(game["challenger"] for game in pair) != [0, 1] for pair in pairs.values()):
        raise ValueError("Every seed must swap challenger and baseline seats")
    if sorted(pairs) != list(range(first["seed_base"], first["seed_base"] + expected_games // 2)):
        raise ValueError("Acceptance must use the complete consecutive seed range")
    if {game["faction"] for game in games} != {f"I{number:02}" for number in range(1, 13)}:
        raise ValueError("Acceptance must cover all twelve current factions")
    for name, digest in first["hashes"].items():
        if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest:
            raise ValueError(f"Candidate source changed since the benchmark: {name}")
    for name, hashes in first["baseline"]["files"].items():
        path = ROOT / "tests" / "ai_baseline" / name
        content = path.read_bytes()
        if (hashlib.sha256(content).hexdigest() != hashes["frozen_sha256"]
                and hashlib.sha256(content.replace(b"\r\n", b"\n")).hexdigest() != hashes.get("canonical_lf_sha256")):
            raise ValueError(f"Frozen baseline changed: {name}")

    outcomes = collections.Counter(game["outcome"] for game in games)
    factions: dict[str, dict] = {}
    initiatives: dict[str, dict] = {}
    actions: collections.Counter = collections.Counter()
    baseline_actions: collections.Counter = collections.Counter()
    actor_ids: set[str] = set()
    attack_leaders: set[str] = set()
    resource_deployment_games = 0
    resource_activation_games = 0
    resource_card_activations = 0
    resource_card_activation_games = 0
    baseline_resource_card_activations = 0
    complete_traces = all(len(game["trace"]) < 160 for game in games)
    victory_kinds: collections.Counter = collections.Counter()
    victory_cards: collections.Counter = collections.Counter()
    durations: list[int] = []
    decision_maxima: list[int] = []
    for game in games:
        for target, key in ((factions, game["faction"]), (initiatives, "first" if game["first"] == game["challenger"] else "second")):
            target.setdefault(key, {"games": 0, "wins": 0, "losses": 0, "draws": 0, "unfinished": 0})
            target[key]["games"] += 1
            target[key][{"win": "wins", "loss": "losses", "draw": "draws", "unfinished": "unfinished"}[game["outcome"]]] += 1
        actions.update(game["counts"][game["challenger"]])
        baseline_actions.update(game["counts"][1 - game["challenger"]])
        durations.append(game["elapsed_ms"][game["challenger"]])
        decision_maxima.append(game["max_ms"][game["challenger"]])
        actor_ids.update(entry["src"] for entry in game["trace"] if entry["player"] == game["challenger"] and entry["src"])
        attack_leaders.update(entry["src"] for entry in game["trace"] if entry["player"] == game["challenger"] and entry["type"] == "attack")
        resource_deployment_games += bool(game["counts"][game["challenger"]].get("deploy", 0))
        resource_activation_games += bool(game["counts"][game["challenger"]].get("resource", 0))
        # Russia/Australia also use the "resource" command type. With complete
        # main traces, remove non-E sources rather than calling those card uses.
        if complete_traces:
            uses = []
            for p in (game["challenger"], 1 - game["challenger"]):
                non_cards = sum(entry["type"] == "resource" and not entry["src"].startswith("E") for entry in game["trace"] if entry["player"] == p)
                uses.append(game["counts"][p].get("resource", 0) - non_cards)
            resource_card_activations += uses[0]
            resource_card_activation_games += bool(uses[0])
            baseline_resource_card_activations += uses[1]
        if game["outcome"] == "win":
            victory_kinds[game["victory"].get("kind", "unknown")] += 1
            if game["victory"].get("card"):
                victory_cards[game["victory"]["card"]] += 1
    return {
        "accepted": outcomes["win"] >= minimum_wins and not outcomes["unfinished"],
        "criterion": {"games": expected_games, "minimum_wins": minimum_wins, "unfinished_count_as_wins": False},
        "conditions": {key: first[key] for key in ("mirror_factions", "seed_base", "max_turns", "max_commands")},
        "baseline": first["baseline"], "candidate_hashes": first["hashes"],
        "candidate_canonical_lf_hashes": {name: hashlib.sha256((ROOT / name).read_bytes().replace(b"\r\n", b"\n")).hexdigest() for name in first["hashes"]},
        "source_reports": [str(path.relative_to(ROOT)) for path in paths],
        "games": len(games), "seed_pairs": len(pairs),
        "wins": outcomes["win"], "losses": outcomes["loss"], "draws": outcomes["draw"], "unfinished": outcomes["unfinished"],
        "win_rate": outcomes["win"] / len(games), "illegal": 0,
        "factions": dict(sorted(factions.items())), "initiative": initiatives,
        "candidate_actions": dict(sorted(actions.items())), "baseline_actions": dict(sorted(baseline_actions.items())),
        "distinct_public_actors": sorted(actor_ids),
        "behavior": {
            "games_with_resource_deployment": resource_deployment_games,
            "games_with_resource_command": resource_activation_games,
            "resource_card_activations": resource_card_activations if complete_traces else None,
            "games_with_resource_card_activation": resource_card_activation_games if complete_traces else None,
            "baseline_resource_card_activations": baseline_resource_card_activations if complete_traces else None,
            "distinct_recorded_attack_leaders": sorted(attack_leaders),
            "all_recorded_main_traces_below_cap": complete_traces,
            "winning_reasons": dict(sorted(victory_kinds.items())),
            "winning_cards": dict(sorted(victory_cards.items())),
        },
        "timing": {"median_candidate_ms_per_game": statistics.median(durations), "max_candidate_decision_ms": max(decision_maxima)},
        "results": [{key: game[key] for key in ("seed", "faction", "challenger", "first", "outcome", "turns", "steps", "counts", "elapsed_ms", "max_ms", "victory")} for game in sorted(games, key=lambda game: (game["seed"], game["challenger"]))],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", type=pathlib.Path, nargs="+")
    parser.add_argument("--games", type=int, default=100)
    parser.add_argument("--wins", type=int, default=70)
    parser.add_argument("--output", type=pathlib.Path)
    args = parser.parse_args()
    try:
        result = summarize([path.resolve() for path in args.reports], args.games, args.wins)
    except ValueError as error:
        parser.error(str(error))
    if args.output:
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: result[key] for key in ("accepted", "games", "wins", "losses", "draws", "unfinished", "win_rate", "illegal")}, ensure_ascii=False))
    return 0 if result["accepted"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
