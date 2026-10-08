"""First-run questions: alone or for the kids too? Then one round per child.

The app shows Question objects one by one and feeds the answers back, so the
same flow drives the iOS and Android UIs:

    flow = Onboarding()
    q = flow.next_question()
    while q:
        flow.answer(<value from the UI>)
        q = flow.next_question()
    profiles = flow.profiles()

Reading check: under 6 we assume the child cannot read yet but still confirm
it with a yes/no question (default "no"); 6-8 year olds are always asked;
from 9 we assume they can read. Non-readers get a picture-only UI: big avatar
grid to pick themselves, icons instead of text, feedback read aloud.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .avatars import AVATARS, avatar_label
from .profiles import Profile

ASSUME_NON_READER_UNDER = 6
ASSUME_READER_FROM = 9


@dataclass(frozen=True)
class Question:
    id: str
    text: str
    kind: str  # "choice", "text", "number", "avatar"
    options: tuple = ()
    default: object = None
    picture_only: bool = False  # render images without text (child who cannot read)


@dataclass
class _Child:
    name: str = ""
    age: int | None = None
    can_read: bool | None = None
    avatar: str | None = None


@dataclass
class Onboarding:
    adult_name: str = "Én"
    _mode: str | None = None  # "alone" or "family"
    _children: list[_Child] = field(default_factory=list)
    _more: bool = True
    _done: bool = False

    # -- question sequence ------------------------------------------------
    def next_question(self) -> Question | None:
        if self._mode is None:
            return Question("mode", "Egyedül használod az appot, vagy a gyerekeid fogmosását is mérnéd?",
                            "choice", (("alone", "Csak magamnak"), ("family", "A gyerekeimnek is")))
        if self._mode == "alone" or self._done:
            return None
        c = self._children[-1] if self._children else None
        if c is None or (c.avatar is not None and self._more is None):
            return Question("more", "Szeretnél még egy gyereket hozzáadni?", "choice",
                            (("yes", "Igen"), ("no", "Nem, kész")))
        if not c.name:
            return Question("child_name", "Hogy hívják a gyermeked?", "text")
        if c.age is None:
            return Question("child_age", f"Hány éves {c.name}?", "number")
        if c.can_read is None:
            return Question("child_reads", f"Tud már {c.name} önállóan olvasni?", "choice",
                            (("yes", "Igen"), ("no", "Még nem")),
                            default="no" if c.age < ASSUME_NON_READER_UNDER else None)
        if c.avatar is None:
            taken = {k.avatar for k in self._children if k is not c}
            opts = tuple(a for a in AVATARS if a not in taken)
            text = (f"{c.name}, válaszd ki a képedet! Erről fogod megismerni magad."
                    if c.can_read else "")  # non-readers: only pictures (parent reads it aloud / TTS)
            return Question("child_avatar", text, "avatar", opts, picture_only=not c.can_read)
        return None

    def answer(self, value) -> None:
        q = self.next_question()
        if q is None:
            raise RuntimeError("onboarding already finished")
        if q.id == "mode":
            if value not in ("alone", "family"):
                raise ValueError(value)
            self._mode = value
            if value == "family":
                self._children.append(_Child())
        elif q.id == "more":
            if value == "yes":
                self._children.append(_Child())
                self._more = True
            else:
                self._done = True
        else:
            c = self._children[-1]
            if q.id == "child_name":
                if not str(value).strip():
                    raise ValueError("empty name")
                c.name = str(value).strip()
            elif q.id == "child_age":
                age = int(value)
                if not 1 <= age <= 17:
                    raise ValueError("age must be 1-17")
                c.age = age
                if age >= ASSUME_READER_FROM:
                    c.can_read = True  # no need to ask
            elif q.id == "child_reads":
                c.can_read = value == "yes"
            elif q.id == "child_avatar":
                if value not in q.options:
                    raise ValueError(f"avatar {value!r} not available")
                c.avatar = value
                self._more = None  # ask whether there is another child

    # -- result -----------------------------------------------------------
    def profiles(self) -> list[Profile]:
        out = [Profile("me", self.adult_name)]
        for i, c in enumerate(k for k in self._children if k.avatar):
            out.append(Profile(f"child{i + 1}", c.name, child=True, age=c.age,
                               can_read=bool(c.can_read), avatar=c.avatar))
        return out


@dataclass(frozen=True)
class PickerItem:
    profile_id: str
    avatar: str | None
    label: str | None  # None -> picture only


def profile_picker(profiles: list[Profile]) -> list[PickerItem]:
    """Who is brushing now? (shared phone). Names only for people who can read;
    non-readers find themselves by their avatar picture."""
    return [PickerItem(p.id, p.avatar, p.name if p.can_read else None) for p in profiles]


__all__ = ["Onboarding", "Question", "PickerItem", "profile_picker", "avatar_label"]
