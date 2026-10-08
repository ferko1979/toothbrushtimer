import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from brushdetect.onboarding import Onboarding, profile_picker  # noqa: E402
from brushdetect.profiles import feedback_for  # noqa: E402


def run(flow, answers):
    asked = []
    for a in answers:
        q = flow.next_question()
        asked.append(q)
        flow.answer(a)
    return asked


def test_alone():
    f = Onboarding()
    run(f, ["alone"])
    assert f.next_question() is None
    assert [p.id for p in f.profiles()] == ["me"]


def test_family_with_reader_and_non_reader():
    f = Onboarding()
    asked = run(f, ["family",
                    "Bence", 4, "no", "dino", "yes",   # 4 years: reading question asked, default "no"
                    "Lili", 10, "unicorn", "no"])      # 10 years: no reading question
    ids = [q.id for q in asked]
    assert ids == ["mode", "child_name", "child_age", "child_reads", "child_avatar", "more",
                   "child_name", "child_age", "child_avatar", "more"]
    reads_q = asked[3]
    assert reads_q.default == "no" and "Bence" in reads_q.text
    avatar_q_bence, avatar_q_lili = asked[4], asked[8]
    assert avatar_q_bence.picture_only and avatar_q_bence.text == ""
    assert not avatar_q_lili.picture_only and "Lili" in avatar_q_lili.text
    assert "dino" not in avatar_q_lili.options  # siblings get different avatars
    assert f.next_question() is None

    profiles = f.profiles()
    bence, lili = profiles[1], profiles[2]
    assert (bence.child, bence.can_read, bence.avatar, bence.age) == (True, False, "dino", 4)
    assert (lili.can_read, lili.avatar) == (True, "unicorn")

    picker = profile_picker(profiles)
    assert picker[1].label is None and picker[1].avatar == "dino"  # picture only
    assert picker[2].label == "Lili"


def test_six_year_old_is_asked_without_default():
    f = Onboarding()
    asked = run(f, ["family", "Máté", 6, "yes", "lion", "no"])
    assert asked[3].id == "child_reads" and asked[3].default is None
    assert f.profiles()[1].can_read


def test_invalid_answers():
    f = Onboarding()
    with pytest.raises(ValueError):
        f.answer("maybe")
    f.answer("family")
    with pytest.raises(ValueError):
        f.answer("  ")
    f.answer("Bence")
    with pytest.raises(ValueError):
        f.answer(42)
    f.answer(5)
    f.answer("no")
    with pytest.raises(ValueError):
        f.answer("dragon")


def test_feedback_for_non_reader_is_spoken_with_icons():
    f = Onboarding()
    run(f, ["family", "Bence", 4, "no", "dino", "no"])
    me, bence = f.profiles()
    fb = feedback_for(bence, 130)
    assert fb.speak and fb.icons == "⭐⭐⭐🏅"
    assert feedback_for(bence, 30).icons == "⭐"
    adult = feedback_for(me, 130)
    assert not adult.speak and "elérted" in adult.text
