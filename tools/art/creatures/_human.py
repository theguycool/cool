"""What two-legged creatures share: trouser legs in four poses and the way a figure's parts are put
together for each frame, so every humanoid walks and strikes with the same timing."""
from artlib import part, frame

LEG_STAND = """
Pppq.
Pppq.
Pppq.
.ppq.
.ppq.
.pqq.
.pqq.
.ooO.
oooo.
ooooO
"""
LEG_FWD = """
Pppq...
PPppq..
.Pppq..
..ppqq.
..Pppq.
...ppq.
...pqq.
...ooO.
...oooo
...oooO
"""
LEG_BACK = """
..Pppq.
..Pppq.
.Pppq..
.ppqq..
Pppq...
ppq....
pqq....
ooO....
ooo....
oooO...
"""
LEG_LIFT = """
Pppq.
Pppq.
PPpq.
.Pppq
..ppq
..pqq
..ooO
.ooo.
.oooO
.....
"""
LEG_DX = dict(stand=0, fwd=0, back=-2, lift=0)


def legs(pal, far_pal, K, inner, texts=None):
    """Near and far legs in each pose: {pose: (near, far)}."""
    t = dict(stand=LEG_STAND, fwd=LEG_FWD, back=LEG_BACK, lift=LEG_LIFT)
    if texts:
        t.update(texts)
    return {k: (part(v, pal, outline=K, inner=inner, open_top=True), part(v, far_pal, outline=K, inner=inner, open_top=True)) for k, v in t.items()}


# the seven frames every humanoid has, in order: (near leg, far leg, body drop, lean, arm pose)
STEPS = [
    ("stand", "stand", 0, 0, "rest"),
    ("fwd", "back", 0, 0, "rest"),
    ("stand", "lift", 1, 0, "rest"),
    ("back", "fwd", 0, 0, "rest"),
    ("lift", "stand", 1, 0, "rest"),
]
POSES = {"idle": [0], "walk": [1, 2, 3, 4]}


def figure(W, H, L, at, near, far, bob, lean, layers_back, layers_front, head, torso, hips):
    """One frame. `at`: where the head, torso, hips and legs go, as a dict of (x, y)."""
    out = []
    out += layers_back
    out.append((L[far][1], at["far_leg"][0] + LEG_DX[far], at["far_leg"][1]))
    out.append((L[near][0], at["near_leg"][0] + LEG_DX[near], at["near_leg"][1]))
    if hips is not None:
        out.append((hips, at["hips"][0], at["hips"][1] + bob))
    out.append((torso, at["torso"][0] + lean // 2, at["torso"][1] + bob))
    out.append((head, at["head"][0] + lean, at["head"][1] + bob))
    out += layers_front
    return frame(W, H, out)
