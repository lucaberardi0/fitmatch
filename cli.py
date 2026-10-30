#!/usr/bin/env python3
import sys
import argparse
import json
from fitmatch.service import ComparisonService

# ANSI color codes
RESET = "\033[0m"
BOLD = "\033[1m"
GREEN = "\033[92m"
CYAN = "\033[96m"
YELLOW = "\033[93m"
RED = "\033[91m"
DIM = "\033[2m"
MAGENTA = "\033[95m"


def print_banner():
    banner = f"""{BOLD}{CYAN}
  ╔═══════════════════════════════════════════════════════╗
  ║       🏃 FITMATCH — Sports Gear Price Comparator       ║
  ║         Multistore Scraping & AI Matching MVP         ║
  ╚═══════════════════════════════════════════════════════╝{RESET}
"""
    print(banner)


def format_search_results(res, max_groups: int = 15):
    print(f"{BOLD}Ricerca:{RESET} '{res.query}'")
    print(f"{DIM}Negozi scansionati:{RESET} {', '.join(res.stores_queried)}")
    print(f"{DIM}Offerte trovate:{RESET} {BOLD}{res.total_offers_found}{RESET} in {BOLD}{res.execution_time_seconds}s{RESET}\n")

    if not res.matched_products:
        print(f"{YELLOW}Nessun prodotto trovato per questa ricerca.{RESET}")
        return

    print(f"{BOLD}{'PRODOTTO':<48} {'MIGLIOR PREZZO':<18} {'NEGOZIO':<16} {'CONFRONTO'}{RESET}")
    print("─" * 100)

    # Highlight multi-store matches first
    multi_store = [g for g in res.matched_products if len(g.offers) > 1]
    single_store = [g for g in res.matched_products if len(g.offers) == 1]

    if multi_store:
        print(f"\n{BOLD}{GREEN}★ CONFRONTI MULTI-STORE (Prezzi a confronto):{RESET}")
        for idx, group in enumerate(multi_store[:max_groups], 1):
            best = group.best_offer
            name = (group.canonical_name[:45] + "..") if len(group.canonical_name) > 47 else group.canonical_name
            savings_info = ""
            if group.cross_store_savings and group.cross_store_savings > 0:
                savings_info = f"{GREEN}Risparmi fino a €{group.cross_store_savings:.2f}{RESET}"

            print(f"\n{BOLD}{idx}. {name}{RESET}")
            if group.brand:
                print(f"   {DIM}Brand:{RESET} {group.brand}")
            print(f"   {BOLD}Offerte disponibili ({len(group.offers)} negozi):{RESET}")

            for offer in group.offers:
                is_best = (offer.price == group.best_price)
                badge = f" {BOLD}{GREEN}✓ PIÙ ECONOMICO{RESET}" if is_best else ""
                discount = f" {YELLOW}(-{offer.discount_pct:.0f}%){RESET}" if offer.discount_pct else ""
                print(f"     • {offer.store_name:<16}: {BOLD}€{offer.price:>6.2f}{RESET}{discount}{badge}")
                print(f"       {DIM}Link: {offer.url}{RESET}")

    if single_store:
        print(f"\n{BOLD}{CYAN}ALTRE OFFERTE TROVATE:{RESET}")
        for idx, group in enumerate(single_store[:10], 1):
            best = group.best_offer
            name = (group.canonical_name[:45] + "..") if len(group.canonical_name) > 47 else group.canonical_name
            discount = f" {YELLOW}(-{best.discount_pct:.0f}%){RESET}" if best.discount_pct else ""
            print(f"  {idx:2d}. {name:<46} {BOLD}€{best.price:>6.2f}{RESET}{discount}  [{best.store_name}]")
            print(f"      {DIM}{best.url}{RESET}")

    print("\n" + "─" * 100)


def main():
    parser = argparse.ArgumentParser(description="FitMatch Price Comparison CLI")
    subparsers = parser.add_subparsers(dest="command", help="Comando da eseguire")

    # Search command
    search_parser = subparsers.add_parser("search", help="Cerca e confronta un prodotto tra tutti i negozi")
    search_parser.add_argument("query", type=str, help="Termine di ricerca (es. 'nike pegasus', 'asics nimbus')")
    search_parser.add_argument("--limit", type=int, default=8, help="Numero max di prodotti per negozio (default: 8)")
    search_parser.add_argument("--json", action="store_true", help="Output in formato JSON")
    search_parser.add_argument("--cache", action="store_true", help="Usa cache locale se disponibile")

    # Demo command
    demo_parser = subparsers.add_parser("demo", help="Esegue una ricerca di prova per verificare tutti i negozi")

    args = parser.parse_args()

    if not args.command:
        print_banner()
        parser.print_help()
        sys.exit(0)

    service = ComparisonService()

    if args.command == "demo":
        print_banner()
        query = "nike pegasus"
        print(f"{CYAN}Avvio scraping demo simultaneo su Cisalfa, Maxi Sport, Mister Running e Nencini Sport...{RESET}\n")
        results = service.search_and_compare(query=query, limit_per_store=6)
        format_search_results(results)

    elif args.command == "search":
        if not args.json:
            print_banner()
            print(f"{CYAN}Ricerca in corso per '{args.query}' su tutti i negozi...{RESET}")

        results = service.search_and_compare(
            query=args.query,
            limit_per_store=args.limit,
            use_cache=args.cache
        )

        if args.json:
            print(results.model_dump_json(indent=2))
        else:
            format_search_results(results)


if __name__ == "__main__":
    main()
