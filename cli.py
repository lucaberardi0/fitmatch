#!/usr/bin/env python3
import sys
import argparse
import json
from fitmatch.service import ComparisonService
from fitmatch.db import Database
from fitmatch.crawler import CategoryCrawler
from fitmatch.ai_advisor import AIShoppingAdvisor

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
                sizes_info = f" {DIM}(Taglie: {', '.join(offer.available_sizes[:6])}{'..' if len(offer.available_sizes) > 6 else ''}){RESET}" if offer.available_sizes else ""
                print(f"     • {offer.store_name:<16}: {BOLD}€{offer.price:>6.2f}{RESET}{discount}{badge}{sizes_info}")
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
    search_parser.add_argument("--size", type=str, default=None, help="Filtra solo offerte con la taglia disponibile (es. '43', '42.5', 'M')")
    search_parser.add_argument("--limit", type=int, default=8, help="Numero max di prodotti per negozio (default: 8)")
    search_parser.add_argument("--json", action="store_true", help="Output in formato JSON")
    search_parser.add_argument("--cache", action="store_true", help="Usa cache locale se disponibile")

    # Demo command
    demo_parser = subparsers.add_parser("demo", help="Esegue una ricerca di prova per verificare tutti i negozi")

    # Index / Crawl command
    index_parser = subparsers.add_parser("index", help="Esegue il crawler di categoria per popolare il database locale")
    index_parser.add_argument("--limit", type=int, default=100, help="Numero max di articoli da indicizzare per negozio (default: 100)")

    # Stats command
    stats_parser = subparsers.add_parser("stats", help="Visualizza le statistiche del catalogo indicizzato")

    # Catalog search command
    cat_parser = subparsers.add_parser("catalog", help="Cerca istantaneamente nel catalogo indicizzato offline")
    cat_parser.add_argument("query", type=str, nargs="?", default="", help="Filtro di ricerca (es. 'nike', 'asics', 'donna')")

    # AI Ask command
    ask_parser = subparsers.add_parser("ask", help="Interroga l'Assistente AI con esigenze in linguaggio naturale")
    ask_parser.add_argument("prompt", type=str, help="Esigenza dell'utente (es. 'peso 85kg corro su asfalto cerco scarpa comoda sotto i 140€')")

    args = parser.parse_args()

    if not args.command:
        print_banner()
        parser.print_help()
        sys.exit(0)

    service = ComparisonService()
    db = Database()

    if args.command == "demo":
        print_banner()
        query = "nike pegasus"
        print(f"{CYAN}Avvio scraping demo simultaneo su Cisalfa, Maxi Sport, Mister Running e Nencini Sport...{RESET}\n")
        results = service.search_and_compare(query=query, limit_per_store=6)
        format_search_results(results)

    elif args.command == "index":
        print_banner()
        print(f"{CYAN}Avvio indicizzazione categorie running su tutti i 6 negozi (Target: {args.limit} per negozio)...{RESET}\n")
        crawler = CategoryCrawler(db=db)
        sync_res = crawler.run_full_sync(limit_per_store=args.limit)
        print(f"\n{BOLD}{GREEN}✓ Indicizzazione completata con successo in {sync_res['duration_seconds']}s!{RESET}")
        print(f"Totale offerte indicizzate nel database: {BOLD}{sync_res['total_crawled']}{RESET}\n")
        stats = sync_res["catalog_stats"]
        print(f"• Prodotti unici nel catalogo: {BOLD}{stats['total_products']}{RESET}")
        print(f"• Prodotti presenti su più negozi: {BOLD}{GREEN}{stats['multi_store_products']}{RESET}")
        print(f"• Marchi rilevati: {BOLD}{stats['brands_count']}{RESET}\n")
        print("Ripartizione per negozio:")
        for s in stats["store_breakdown"]:
            avg_disc = f" (Sconto medio: -{s['avg_discount']:.1f}%)" if s['avg_discount'] else ""
            print(f"  - {s['store_name']:<18}: {BOLD}{s['count']:>4d} offerte{RESET}{avg_disc}")

    elif args.command == "stats":
        print_banner()
        stats = db.get_stats()
        print(f"{BOLD}STATISTICHE CATALOGO INDICIZZATO:{RESET}")
        print(f"• Prodotti unici nel database: {BOLD}{stats['total_products']}{RESET}")
        print(f"• Offerte totali salvate:      {BOLD}{stats['total_offers']}{RESET}")
        print(f"• Prodotti multi-negozio:      {BOLD}{GREEN}{stats['multi_store_products']}{RESET}")
        print(f"• Brand sportivi censiti:      {BOLD}{stats['brands_count']}{RESET}\n")

        print(f"{BOLD}OFFERTE PER STORE:{RESET}")
        for s in stats["store_breakdown"]:
            avg_disc = f" (Sconto medio: -{s['avg_discount']:.1f}%)" if s['avg_discount'] else ""
            print(f"  • {s['store_name']:<18}: {BOLD}{s['count']:>4d} capi{RESET} | Prezzo medio: €{s['avg_price']:.2f}{avg_disc}")

        if stats["top_savings"]:
            print(f"\n{BOLD}{GREEN}TOP 5 RISPARMI IDENTIFICATI NEL DATABASE:{RESET}")
            for idx, item in enumerate(stats["top_savings"], 1):
                print(f"  {idx}. {BOLD}{item['canonical_name']}{RESET} ({item['brand']})")
                print(f"     Da {BOLD}€{item['min_price']:.2f}{RESET} a {BOLD}€{item['max_price']:.2f}{RESET} | Risparmio potenziale: {BOLD}{GREEN}€{item['savings']:.2f}{RESET} ({item['store_count']} negozi)")

    elif args.command == "catalog":
        print_banner()
        print(f"{CYAN}Ricerca istantanea nel database indicizzato per: '{args.query}'...{RESET}\n")
        items = db.search_indexed(args.query, limit=20)
        if not items:
            print(f"{YELLOW}Nessun prodotto trovato nel catalogo locale. Esegui prima 'python3 cli.py index'.{RESET}")
            return
        print(f"Trovati {BOLD}{len(items)}{RESET} prodotti nel database locale:\n")
        for idx, item in enumerate(items, 1):
            savings_str = f" {GREEN}(Risparmi fino a €{item['max_price'] - item['best_price']:.2f}){RESET}" if len(item['offers']) > 1 and item['max_price'] > item['best_price'] else ""
            print(f"{BOLD}{idx}. {item['canonical_name']}{RESET} [{item['brand'] or 'N/A'}]")
            print(f"   Prezzo migliore: {BOLD}€{item['best_price']:.2f}{RESET}{savings_str} - {len(item['offers'])} offerte disponibili")
            for o in item["offers"]:
                disc = f" (-{o['discount_pct']:.0f}%)" if o['discount_pct'] else ""
                print(f"     • {o['store_name']:<16}: €{o['current_price']:>6.2f}{disc}  {DIM}{o['product_url'][:70]}...{RESET}")
            print()

    elif args.command == "ask":
        print_banner()
        print(f"{BOLD}💬 Richiesta Utente:{RESET} \"{args.prompt}\"")
        print(f"{CYAN}Elaborazione profilo biomeccanico e ricerca delle offerte migliori...{RESET}\n")

        advisor = AIShoppingAdvisor(service=service, db=db)
        advice = advisor.advise(args.prompt)
        p = advice["user_profile"]

        print(f"{BOLD}🧠 ANALISI IA & PROFILAZIONE:{RESET}")
        print(f"  • Categoria raccomandata: {BOLD}{CYAN}{advice['category_name']}{RESET}")
        print(f"  • Genere rilevato:        {p['gender']}")
        if p["weight_kg"]:
            print(f"  • Peso runner:            {p['weight_kg']} kg")
        print(f"  • Terreno d'uso:          {p['surface'].capitalize()}")
        if p["max_price"]:
            print(f"  • Vincolo di budget:      {GREEN}Max €{p['max_price']:.2f}{RESET}")

        print(f"\n{BOLD}💡 MOTIVAZIONE TECNICA:{RESET}")
        print(f"  {advice['biomechanical_reasoning']}\n")

        if not advice["recommendations"]:
            print(f"{YELLOW}Nessun modello trovato che rispetti rigorosamente tutti i filtri di budget.{RESET}")
            return

        print(f"{BOLD}{GREEN}★ I MODELLI RACCOMANDATI AL PREZZO PIÙ BASSO:{RESET}")
        print("─" * 100)
        for idx, rec in enumerate(advice["recommendations"], 1):
            disc_str = f" {YELLOW}(-{rec['discount_pct']:.0f}%){RESET}" if rec['discount_pct'] else ""
            print(f"\n{BOLD}{idx}. {rec['product_name']}{RESET} [{rec['brand'] or 'N/A'}]")
            print(f"   Miglior prezzo attuale: {BOLD}{GREEN}€{rec['best_price']:.2f}{RESET}{disc_str} su {BOLD}{rec['best_store']}{RESET}")
            if rec['cross_store_savings'] and rec['cross_store_savings'] > 0:
                print(f"   {GREEN}✓ Risparmi fino a €{rec['cross_store_savings']:.2f} rispetto ad altri store!{RESET}")
            print(f"   Tutte le opzioni a confronto:")
            for o in rec["all_offers"]:
                print(f"     • {o['store']:<16}: €{o['price']:>6.2f} -> {DIM}{o['url']}{RESET}")
        print("\n" + "─" * 100)

    elif args.command == "search":
        size_str = f" [Taglia: {args.size}]" if args.size else ""
        if not args.json:
            print_banner()
            print(f"{CYAN}Ricerca in corso per '{args.query}'{size_str} su tutti i negozi...{RESET}")

        results = service.search_and_compare(
            query=args.query,
            size=args.size,
            limit_per_store=args.limit,
            use_cache=args.cache
        )

        if args.json:
            print(results.model_dump_json(indent=2))
        else:
            format_search_results(results)


if __name__ == "__main__":
    main()
