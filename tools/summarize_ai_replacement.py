"""Pair old-vs-old losers with their already-recorded new-vs-old matches."""
from __future__ import annotations

import argparse
import collections
import json
import pathlib

from summarize_ai_benchmark import ROOT, baseline_identity, summarize


def compare(strength_paths, control_paths, opening_path, replay_paths):
    strength = summarize(strength_paths)
    source = json.loads(strength_paths[0].read_text(encoding="utf-8"))
    original = {(game["seed"], game["challenger"]): game for path in strength_paths for game in json.loads(path.read_text(encoding="utf-8"))["games"]}
    seeds = sorted({seed for seed, _ in original})

    def compatible(report):
        for key in ("hashes", "mirror_factions", "seed_base", "max_turns", "max_commands"):
            if report[key] != source[key]:
                raise ValueError(f"Replacement experiment changed a fixed condition: {key}")
        if baseline_identity(report["baseline"]) != baseline_identity(source["baseline"]):
            raise ValueError("Replacement experiment changed the old policy")
        if report["illegal"]:
            raise ValueError("A control or replay had an illegal action or live RNG mutation")

    def finished_report(report, games_per_seed):
        compatible(report)
        if len(report["games"]) != report["pairs"] * games_per_seed:
            raise ValueError("A control or replay shard is incomplete")
        outcomes = collections.Counter(game["outcome"] for game in report["games"])
        for label, key in (("win", "wins"), ("loss", "losses"), ("draw", "draws"), ("unfinished", "unfinished")):
            if outcomes[label] != report[key]:
                raise ValueError(f"Control/replay totals disagree with its games: {key}")

    controls = {}
    for path in control_paths:
        report = json.loads(path.read_text(encoding="utf-8"))
        finished_report(report, 1)
        if not report.get("baseline_control") or report.get("opening_only"):
            raise ValueError("A control must be a complete old-vs-old match")
        for game in report["games"]:
            if game["seed"] in controls or game["challenger"] != 0:
                raise ValueError("Duplicate or invalid control seed")
            controls[game["seed"]] = game
    if sorted(controls) != seeds:
        raise ValueError("Old-vs-old controls must cover the full original seed range")

    openings_report = json.loads(opening_path.read_text(encoding="utf-8"))
    finished_report(openings_report, 2)
    if not openings_report.get("opening_only") or openings_report.get("baseline_control"):
        raise ValueError("Opening attestation requires both candidate seats")
    openings = {(g["seed"], g["challenger"]): g for g in openings_report["games"]}
    if len(openings) != len(openings_report["games"]) or set(openings) != set(original):
        raise ValueError("Opening replay range does not match the strength experiment")

    # A fixed sample replays both seats in full, rather than selecting only wins.
    expected_replays = {(seed, p) for seed in (seeds[0], seeds[min(11, len(seeds)-1)], seeds[-1]) for p in (0, 1)}
    replayed = set()
    for path in replay_paths:
        report = json.loads(path.read_text(encoding="utf-8"))
        finished_report(report, 2)
        if report.get("baseline_control") or report.get("opening_only"):
            raise ValueError("Full replays must use new-vs-old policies")
        for game in report["games"]:
            key = game["seed"], game["challenger"]
            if key in replayed or key not in expected_replays:
                raise ValueError("Duplicate or unexpected deterministic replay")
            replayed.add(key)
            for field in ("faction", "factions", "first", "outcome", "winner", "turns", "steps", "counts", "victory"):
                if game[field] != original[key][field]:
                    raise ValueError(f"Full replay failed to reproduce {key}: {field}")
            if game["opening_hash"] != openings[key]["opening_hash"]:
                raise ValueError("Full-game opening disagrees with opening-only replay")
    if replayed != expected_replays:
        raise ValueError("All six predetermined full replays must finish")

    trials = []
    excluded = []
    initiative = collections.defaultdict(collections.Counter)
    for seed, control in sorted(controls.items()):
        for p in (0, 1):
            key = seed, p
            if control["factions"] != [control["faction"], control["faction"]] or control["factions"] != original[key]["factions"]:
                raise ValueError("Control and replacement factions differ")
            if not control["opening_hash"] or control["opening_hash"] != openings[key]["opening_hash"]:
                raise ValueError("Control and replacement initial hands, decks, board or RNG differ")
            if control["first"] != openings[key]["first"] or control["first"] != original[key]["first"]:
                raise ValueError("A replacement changed the first player")
        if control["winner"] not in (0, 1) or control["outcome"] not in ("win", "loss"):
            excluded.append({"seed": seed, "outcome": control["outcome"]})
            continue
        loser = 1 - control["winner"]
        game = original[seed, loser]
        outcome = game["outcome"]
        lane = "first" if game["first"] == loser else "second"
        initiative[lane][outcome] += 1
        trials.append({
            "seed": seed, "faction": control["faction"], "original_winner_seat": control["winner"],
            "replaced_seat": loser, "replacement_initiative": lane, "opening_sha256": control["opening_hash"],
            "control_turns": control["turns"], "replacement_outcome": outcome,
            "replacement_turns": game["turns"], "replacement_victory": game["victory"],
        })
    outcomes = collections.Counter(t["replacement_outcome"] for t in trials)
    return {
        "protocol": "Play old-vs-old once per fixed seed; replace only its losing seat; reuse the matching frozen new-vs-old match, without retuning or selecting seeds.",
        "controls": len(controls), "eligible_losing_seats": len(trials), "excluded_controls": excluded,
        "reversed": outcomes["win"], "still_lost": outcomes["loss"], "draws": outcomes["draw"], "unfinished": outcomes["unfinished"],
        "reversal_rate": outcomes["win"] / len(trials) if trials else None,
        "initiative": {key: dict(value) for key, value in sorted(initiative.items())},
        "all_opening_fingerprints_equal": True, "full_replays_verified": len(replayed),
        "full_replay_seeds": sorted({seed for seed, _ in replayed}), "illegal": 0,
        "conditions": strength["conditions"], "baseline": strength["baseline"],
        "candidate_canonical_lf_hashes": strength["candidate_canonical_lf_hashes"],
        "replacement_matches_reused_from_strength_benchmark": True,
        "source_controls": [str(path.relative_to(ROOT)) for path in control_paths],
        "source_openings": str(opening_path.relative_to(ROOT)),
        "source_full_replays": [str(path.relative_to(ROOT)) for path in replay_paths],
        "trials": trials,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strength", type=pathlib.Path, nargs="+", required=True)
    parser.add_argument("--controls", type=pathlib.Path, nargs="+", required=True)
    parser.add_argument("--openings", type=pathlib.Path, required=True)
    parser.add_argument("--replays", type=pathlib.Path, nargs="+", required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    try:
        result = compare([p.resolve() for p in args.strength], [p.resolve() for p in args.controls], args.openings.resolve(), [p.resolve() for p in args.replays])
    except ValueError as error:
        parser.error(str(error))
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: result[key] for key in ("controls", "eligible_losing_seats", "reversed", "still_lost", "draws", "unfinished", "reversal_rate", "all_opening_fingerprints_equal", "full_replays_verified", "illegal")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
