"""Avatar set for children: distinct, easy-to-recognise animals.

Ids are stable (stored in profiles); the emoji is a placeholder for the
illustrated artwork the apps will ship. Each child in a family gets a
different one, so a child who cannot read can still find themselves.
"""

AVATARS = {
    "lion": ("🦁", "Oroszlán"),
    "bear": ("🐻", "Maci"),
    "bunny": ("🐰", "Nyuszi"),
    "unicorn": ("🦄", "Unikornis"),
    "dog": ("🐶", "Kutyus"),
    "cat": ("🐱", "Cica"),
    "fox": ("🦊", "Róka"),
    "panda": ("🐼", "Panda"),
    "frog": ("🐸", "Béka"),
    "penguin": ("🐧", "Pingvin"),
    "dino": ("🦖", "Dínó"),
    "octopus": ("🐙", "Polip"),
}


def avatar_image(avatar_id: str) -> str:
    return AVATARS[avatar_id][0]


def avatar_label(avatar_id: str) -> str:
    return AVATARS[avatar_id][1]
