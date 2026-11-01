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
