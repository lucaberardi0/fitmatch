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

