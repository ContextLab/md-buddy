"""Summarise a CSV of reaction times."""
import csv
import statistics
from pathlib import Path


def load_times(path: Path) -> list[float]:
    with path.open() as f:
        return [float(row["rt"]) for row in csv.DictReader(f) if row["rt"]]


def main() -> None:
    times = load_times(Path("data/rt.csv"))
    print(f"n={len(times)}  mean={statistics.mean(times):.3f}s  sd={statistics.stdev(times):.3f}s")


if __name__ == "__main__":
    main()
