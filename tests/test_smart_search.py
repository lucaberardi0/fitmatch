import pytest
from fitmatch.smart_search import LocalHeuristicParser


def test_alphafly_exact_preservation():
    intent = LocalHeuristicParser.parse("Nike alpha fly per la corsa")
    assert intent.brand == "Nike"
    assert intent.category == "running_shoes"
    # Must NOT substitute with pegasus
    assert any("alphafly" in kw.lower() for kw in intent.target_keywords)
    assert not any("pegasus" in kw.lower() for kw in intent.target_keywords)


def test_forerunner_gps_watch_categorization():
    intent = LocalHeuristicParser.parse("Forerunner 165")
    assert intent.brand == "Garmin"
    assert intent.category == "gps_watch"
    assert any("forerunner" in kw.lower() for kw in intent.target_keywords)


def test_substantive_tokens_preserved():
    intent = LocalHeuristicParser.parse("asics novablast 4")
    assert intent.brand == "Asics"
    assert any("novablast" in kw.lower() for kw in intent.target_keywords)


def test_padel_intent_categorization():
    intent = LocalHeuristicParser.parse("Racchetta da padel Bullpadel Hack 04")
    assert intent.brand == "Bullpadel"
    assert intent.category == "padel"
    assert any("hack" in kw.lower() for kw in intent.target_keywords)


def test_cycling_intent_categorization():
    intent = LocalHeuristicParser.parse("rullo smart tacx per bici da corsa sotto 600 euro")
    assert intent.brand == "Tacx"
    assert intent.category == "cycling"
    assert intent.max_price == 600.0


def test_marathon_smart_search_spec_comparisons():
    intent = LocalHeuristicParser.parse("Scarpe da corsa per maratona")
    assert intent.category == "running_shoes"
    assert "racing" in intent.features
    # Check domain narrative summary
    assert "super scarpa da gara in carbonio" in intent.conversational_summary
    # Check multi-brand candidate models expansion
    assert any("adizero" in kw.lower() for kw in intent.target_keywords)
    assert any("vaporfly" in kw.lower() for kw in intent.target_keywords)
    # Check curated sections
    section_titles = [s.title for s in intent.curated_sections]
    assert "Super scarpe da gara" in section_titles
    assert "Adidas Adizero per la maratona" in section_titles
    # Check structured spec comparisons ("Come orientarsi" section)
    assert len(intent.spec_comparisons) >= 2
    adios_pro = next((sc for sc in intent.spec_comparisons if "Adios Pro" in sc.model_name), None)
    assert adios_pro is not None
    assert "Lightstrike Pro" in adios_pro.strengths
    assert "Gara" in adios_pro.ideal_for


