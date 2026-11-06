#!/usr/bin/env python3
import sys
import argparse
import json
from datetime import datetime
from fitmatch.service import ComparisonService
from fitmatch.db import Database
from fitmatch.crawler import CategoryCrawler
from fitmatch.ai_advisor import AIShoppingAdvisor
from fitmatch.scheduler import SyncScheduler

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

    # Crawl / Spider command
    crawl_parser = subparsers.add_parser("crawl", help="Scansione approfondita di specifici negozi o dell'intero catalogo")
    crawl_parser.add_argument("--store", type=str, default=None, help="Negozio da scansionare (cisalfa, maxisport, deporvillage, decathlon, alltricks, misterrunning, nencini, top4running, runningwarehouse)")
    crawl_parser.add_argument("--limit", type=int, default=300, help="Numero max di articoli da indicizzare per negozio (default: 300)")

    # Worker / Autonomous Daemon command
    worker_parser = subparsers.add_parser("worker", help="Avvia il demone autonomo di scraping e monitoraggio prezzi")
    worker_parser.add_argument("--refresh-hours", type=float, default=2.0, help="Intervallo monitoraggio prezzi in ore (default: 2.0)")
    worker_parser.add_argument("--discovery-hours", type=float, default=24.0, help="Intervallo scoperta catalogo in ore (default: 24.0)")
    worker_parser.add_argument("--immediate", action="store_true", help="Esegui subito il primo ciclo di scansione")

    # Scheduler command
    sched_parser = subparsers.add_parser("scheduler", help="Visualizza lo stato dello scheduler o lancia cicli manuali")
    sched_parser.add_argument("--status", action="store_true", help="Mostra lo stato e i tempi delle prossime esecuzioni")
    sched_parser.add_argument("--discovery", action="store_true", help="Esegui subito un ciclo di scoperta catalogo")
    sched_parser.add_argument("--refresh", action="store_true", help="Esegui subito un ciclo di aggiornamento prezzi")
    sched_parser.add_argument("--enrich", action="store_true", help="Esegui subito un ciclo di arricchimento taglie")

    # Sessions command (History & audit trail)
    sess_parser = subparsers.add_parser("sessions", help="Mostra lo storico persistente delle sessioni di sync e scraping salvate nel database")
    sess_parser.add_argument("--limit", type=int, default=15, help="Numero max di sessioni da mostrare (default: 15)")
    sess_parser.add_argument("--type", type=str, default=None, help="Filtra per tipo: discovery, price_refresh, size_enrichment, manual_crawl")
    sess_parser.add_argument("--status", type=str, default=None, help="Filtra per stato: completed, running, failed")
    sess_parser.add_argument("--id", type=str, default=None, help="Dettaglio completo di una singola sessione per ID")

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

    elif args.command == "crawl":
        print_banner()
        crawler = CategoryCrawler(db=db)
        if args.store:
            print(f"{CYAN}Avvio scansione approfondita per lo store '{args.store}' (Target: {args.limit} articoli)...{RESET}")
            try:
                count = crawler.crawl_store(args.store, max_items=args.limit)
                print(f"{BOLD}{GREEN}✓ Scansione completata: {count} prodotti indicizzati da {args.store}!{RESET}")
            except Exception as e:
                print(f"{RED}Errore durante la scansione: {e}{RESET}")
        else:
            print(f"{CYAN}Avvio scansione approfondita di tutti i 9 negozi (Target: {args.limit} per negozio)...{RESET}")
            res = crawler.run_full_sync(limit_per_store=args.limit)
            print(f"\n{BOLD}{GREEN}✓ Scansione completata in {res['duration_seconds']}s! Totale indicizzati: {res['total_crawled']}{RESET}")
            for store, count in res["crawled_by_store"].items():
                print(f"  • {store:<18}: {BOLD}{count:>4d} capi{RESET}")

    elif args.command == "worker":
        import time
        print_banner()
        print(f"{BOLD}{GREEN}Avvio del Demone Autonomo FitMatch Scheduler 24/7...{RESET}")
        print(f"• Monitor Prezzi: ogni {BOLD}{args.refresh_hours} ore{RESET}")
        print(f"• Scoperta Catalogo: ogni {BOLD}{args.discovery_hours} ore{RESET}")
        print(f"• Esecuzione immediata: {BOLD}{'SI' if args.immediate else 'NO'}{RESET}\n")
        print(f"{DIM}Premi Ctrl+C per arrestare il demone in qualsiasi momento.{RESET}\n")

        sched = SyncScheduler.get_instance(db=db)
        sched.start(
            refresh_interval_seconds=int(args.refresh_hours * 3600),
            discovery_interval_seconds=int(args.discovery_hours * 3600),
            run_immediately=args.immediate
        )

        try:
            while True:
                time.sleep(10)
                st = sched.get_status()
                task = st.get("current_task", "idle")
                cycles = st.get("total_cycles_completed", 0)
                print(f"[{datetime.now().strftime('%H:%M:%S')}] Stato demone: {BOLD}{task.upper()}{RESET} | Cicli completati: {BOLD}{cycles}{RESET} | Next refresh: {st['refresh']['next_run'] or 'N/A'}")
        except KeyboardInterrupt:
            print(f"\n{YELLOW}Arresto del demone in corso...{RESET}")
            sched.stop()
            print(f"{GREEN}Demone arrestato correttamente.{RESET}")

    elif args.command == "scheduler":
        print_banner()
        sched = SyncScheduler.get_instance(db=db)
        if args.discovery:
            print(f"{CYAN}Avvio immediato scoperta catalogo...{RESET}")
            res = sched.trigger_discovery_now(limit_per_store=200)
            print(f"{BOLD}{GREEN}{res.get('message')}{RESET}")
        elif args.refresh:
            print(f"{CYAN}Avvio immediato aggiornamento prezzi...{RESET}")
            res = sched.trigger_refresh_now(limit=50)
            print(f"{BOLD}{GREEN}{res.get('message')}{RESET}")
        elif args.enrich:
            print(f"{CYAN}Avvio immediato arricchimento taglie...{RESET}")
            res = sched.trigger_enrichment_now(limit_per_store=50)
            print(f"{BOLD}{GREEN}{res.get('message')}{RESET}")
        else:
            st = sched.get_status()
            print(f"{BOLD}STATO SCHEDULER AUTONOMO:{RESET}")
            print(f"• Attivo:               {BOLD}{'SI' if st['is_running'] else 'NO'}{RESET}")
            print(f"• Task in esecuzione:   {BOLD}{st['current_task'].upper()}{RESET}")
            print(f"• Cicli completati:     {BOLD}{st['total_cycles_completed']}{RESET}\n")
            print(f"{BOLD}1. SCOPERTA CATALOGO (Discovery):{RESET}")
            print(f"  - Intervallo:         Ogni {st['discovery']['interval_hours']} ore")
            print(f"  - Ultima esecuzione:  {st['discovery']['last_run'] or 'Mai'}")
            print(f"  - Prossima:           {st['discovery']['next_run'] or 'Non programmata'}")
            print(f"\n{BOLD}2. MONITOR PREZZI & STOCK (Refresh):{RESET}")
            print(f"  - Intervallo:         Ogni {st['refresh']['interval_hours']} ore")
            print(f"  - Ultima esecuzione:  {st['refresh']['last_run'] or 'Mai'}")
            print(f"  - Prossima:           {st['refresh']['next_run'] or 'Non programmata'}\n")

            recent = st.get("recent_sessions", [])
            if recent:
                print(f"{BOLD}ULTIME SESSIONI SALVATE NEL DATABASE:{RESET}")
                for s in recent[:3]:
                    s_id = str(s.get("id"))[:8]
                    s_type = s.get("session_type", "n/a")
                    s_status = s.get("status", "n/a")
                    s_dur = f"{float(s.get('duration_seconds') or 0):.1f}s"
                    s_items = s.get("total_items_processed", 0)
                    print(f"  • [{s_id}] {s_type:<14} | Stato: {s_status:<9} | Durata: {s_dur:<6} | Articoli: {s_items}")
                print()

    elif args.command == "sessions":
        print_banner()
        if args.id:
            session = db.get_sync_session(args.id)
            if not session:
                print(f"{RED}Sessione '{args.id}' non trovata nel database.{RESET}")
                return
            print(f"{BOLD}DETTAGLIO SESSIONE DI SINCRONIZZAZIONE:{RESET}")
            print(f"• ID Sessione:       {BOLD}{session.get('id')}{RESET}")
            print(f"• Tipo:              {CYAN}{session.get('session_type')}{RESET}")
            print(f"• Trigger:           {session.get('trigger_source')}")
            print(f"• Stato:             {GREEN if session.get('status') == 'completed' else RED}{session.get('status')}{RESET}")
            print(f"• Iniziata:          {session.get('started_at')}")
            print(f"• Completata:        {session.get('completed_at') or 'In corso'}")
            print(f"• Durata:            {session.get('duration_seconds')} secondi")
            print(f"• Articoli trovati:  {BOLD}{session.get('total_items_processed', 0)}{RESET}")
            print(f"• Prezzi aggiornati: {session.get('total_items_updated', 0)}")
            print(f"• Cali di prezzo:    {BOLD}{GREEN}{session.get('total_price_drops', 0)}{RESET}")

            if session.get("error_message"):
                print(f"• Errore riscontrato: {RED}{session.get('error_message')}{RESET}")

            stats = session.get("store_stats") or {}
            if stats:
                print(f"\n{BOLD}Ripartizione per store:{RESET}")
                for k, v in stats.items():
                    print(f"  - {k:<20}: {v}")

            logs = session.get("crawl_logs") or []
            if logs:
                print(f"\n{BOLD}Log dettagliati crawler store:{RESET}")
                for l in logs:
                    print(f"  • {l.get('store_id'):<18}: {l.get('items_found')} articoli in {l.get('duration_seconds')}s")
            print()
        else:
            sessions = db.get_sync_sessions(limit=args.limit, session_type=args.type, status=args.status)
            if not sessions:
                print(f"{YELLOW}Nessuna sessione trovata nel database.{RESET}")
                return

            print(f"{BOLD}STORICO SESSIONI DI SINCRONIZZAZIONE ({len(sessions)} registrate):{RESET}\n")
            header = f"{'ID':<10} {'TIPO':<16} {'STATO':<11} {'AVVIATA':<20} {'DURATA':<8} {'ARTICOLI':<10} {'SCONTI'}"
            print(f"{BOLD}{header}{RESET}")
            print("─" * 90)

            for s in sessions:
                s_id = str(s.get("id"))[:8]
                s_type = s.get("session_type", "n/a")
                st_color = GREEN if s.get("status") == "completed" else (YELLOW if s.get("status") == "running" else RED)
                s_status = f"{st_color}{s.get('status', 'n/a'):<11}{RESET}"
                started = str(s.get("started_at") or "")[:19]
                dur = f"{float(s.get('duration_seconds') or 0):.1f}s"
                items = str(s.get("total_items_processed", 0))
                drops = str(s.get("total_price_drops", 0))
                print(f"{s_id:<10} {s_type:<16} {s_status} {started:<20} {dur:<8} {items:<10} {drops}")

            print("\n" + "─" * 90)
            print(f"{DIM}Per vedere i dettagli di una sessione: python3 cli.py sessions --id <UUID>{RESET}\n")


if __name__ == "__main__":
    main()
