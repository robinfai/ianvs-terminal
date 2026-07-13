#!/usr/bin/env python3
"""
Flutter Guidelines Search Tool
Search the flutter_guidelines.csv for relevant best-practice rules.

Usage:
    python search_guidelines.py --keyword "animation"
    python search_guidelines.py --category "accessibility"
    python search_guidelines.py --severity "critical"
    python search_guidelines.py --keyword "list" --severity "high"
"""

import csv
import argparse
from pathlib import Path

# Colors
BOLD   = "\033[1m"
RED    = "\033[91m"
YELLOW = "\033[93m"
GREEN  = "\033[92m"
CYAN   = "\033[96m"
RESET  = "\033[0m"

SEVERITY_COLOR = {
    "critical": RED,
    "high":     YELLOW,
    "medium":   CYAN,
    "low":      GREEN,
}

SCRIPT_DIR = Path(__file__).parent
CSV_PATH   = SCRIPT_DIR.parent / "data" / "stacks" / "flutter_guidelines.csv"


def load_guidelines() -> list:
    if not CSV_PATH.exists():
        print(f"{RED}ERROR:{RESET} Guidelines file not found at {CSV_PATH}")
        return []
    with open(CSV_PATH, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def search(guidelines: list, keyword: str = None, category: str = None,
           severity: str = None) -> list:
    results = []
    for row in guidelines:
        match = True
        if keyword:
            kw = keyword.lower()
            match = match and (
                kw in row.get('Guideline', '').lower() or
                kw in row.get('Do', '').lower() or
                kw in row.get("Don't", '').lower() or
                kw in row.get('Category', '').lower() or
                kw in row.get('Flutter Example', '').lower()
            )
        if category:
            match = match and category.lower() in row.get('Category', '').lower()
        if severity:
            match = match and severity.lower() in row.get('Severity', '').lower()
        if match:
            results.append(row)
    return results


def print_results(results: list, show_examples: bool = False):
    if not results:
        print(f"{YELLOW}No guidelines matched your query.{RESET}")
        return

    print(f"\n{BOLD}{'━' * 60}{RESET}")
    print(f"{BOLD}🎨 Flutter AI UI — Guidelines Search Results{RESET}")
    print(f"{BOLD}{'━' * 60}{RESET}\n")
    print(f"  Found {len(results)} guideline(s)\n")

    for row in results:
        sev = row.get('Severity', 'LOW')
        color = SEVERITY_COLOR.get(sev.lower(), RESET)
        dont = row.get("Don't", '')
        print(f"{color}[{sev}]{RESET} {BOLD}{row.get('Category', '')}{RESET} — {row.get('Guideline', '')}")
        print(f"  ✅ DO    : {row.get('Do', '')}")
        print(f"  ❌ DON'T : {dont}")
        if show_examples and row.get('Flutter Example'):
            example = row.get('Flutter Example', '')
            print(f"  📝 EXAMPLE: {example}")
        print()

    print(f"{BOLD}{'━' * 60}{RESET}\n")


def list_categories(guidelines: list):
    categories = sorted(set(row.get('Category', '') for row in guidelines if row.get('Category')))
    print(f"\n{BOLD}Available categories:{RESET}")
    for cat in categories:
        count = sum(1 for r in guidelines if r.get('Category', '').lower() == cat.lower())
        print(f"  • {cat} ({count} rules)")
    print()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Flutter AI UI — Guidelines Search")
    parser.add_argument("--keyword",  "-k", help="Search keyword (searches across all fields)")
    parser.add_argument("--category", "-c", help="Filter by category (e.g. Accessibility, Theming, Widgets)")
    parser.add_argument("--severity", "-s", help="Filter by severity: critical, high, medium, low")
    parser.add_argument("--examples", "-e", action="store_true", help="Show Flutter code examples")
    parser.add_argument("--list-categories", "-l", action="store_true", help="List all available categories")
    args = parser.parse_args()

    guidelines = load_guidelines()
    if not guidelines:
        exit(1)

    if args.list_categories:
        list_categories(guidelines)
    elif not any([args.keyword, args.category, args.severity]):
        print(f"{YELLOW}Please provide at least one of: --keyword, --category, --severity{RESET}")
        parser.print_help()
    else:
        results = search(guidelines, args.keyword, args.category, args.severity)
        print_results(results, show_examples=args.examples)
