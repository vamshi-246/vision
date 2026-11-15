"""Independent scalar oracle: no production kernels/helpers are reused."""
import numpy as np
import pytest

from model.golden import Config, edge_frame


def scalar_oracle(src, lo, hi):
    h,w=src.shape
    out={k:np.zeros((h,w),dtype=np.int32) for k in ("smooth","gx","gy","mag","dir","nms","cls","edge")}
    for y in range(1,h-1):
        for x in range(1,w-1):
            s=sum(int(src[y+dy,x+dx])*([1,2,1][dy+1])*([1,2,1][dx+1]) for dy in (-1,0,1) for dx in (-1,0,1))
            out["smooth"][y,x]=(s+8)//16
    a=out["smooth"]
    for y in range(2,h-2):
        for x in range(2,w-2):
            gx=sum((int(a[y+dy,x+1])-int(a[y+dy,x-1]))*[1,2,1][dy+1] for dy in (-1,0,1))
            gy=sum((int(a[y+1,x+dx])-int(a[y-1,x+dx]))*[1,2,1][dx+1] for dx in (-1,0,1))
            out["gx"][y,x]=gx; out["gy"][y,x]=gy
            out["mag"][y,x]=abs(gx)+abs(gy)
            # Ratio comparisons with Python integers, avoiding fixed-width overflow.
            if abs(gy)*32<=abs(gx)*13: d=0
            elif abs(gx)*32<=abs(gy)*13: d=2
            else: d=1 if gx*gy>=0 else 3
            out["dir"][y,x]=d
    offsets=[((0,-1),(0,1)),((-1,-1),(1,1)),((-1,0),(1,0)),((-1,1),(1,-1))]
    for y in range(3,h-3):
        for x in range(3,w-3):
            m=int(out["mag"][y,x]); earlier,later=offsets[out["dir"][y,x]]
            e=int(out["mag"][y+earlier[0],x+earlier[1]])
            l=int(out["mag"][y+later[0],x+later[1]])
            if m and m>=e and m>l:
                out["nms"][y,x]=m
                out["cls"][y,x]=2 if m>=hi else (1 if m>=lo else 0)
                out["edge"][y,x]=int(m>=hi)
    return out


@pytest.mark.parametrize("lo,hi",[(80,200),(0,0),(0,1),(80,80),(2047,2047)])
def test_model_matches_independent_scalar_oracle(lo,hi):
    rng=np.random.default_rng(7913)
    for h,w in [(1,1),(4,9),(7,7),(13,17),(16,12)]:
        for _ in range(4):
            gray=rng.integers(0,256,(h,w),dtype=np.uint8)
            actual=edge_frame(gray,Config(thr_lo=lo,thr_hi=hi))
            for key,expected in scalar_oracle(gray,lo,hi).items():
                np.testing.assert_array_equal(actual[key],expected,err_msg=f"{key}, {w}x{h}, {lo}/{hi}")


def test_zero_threshold_does_not_resurrect_suppressed_pixels_or_borders():
    result=edge_frame(np.full((17,19),255,np.uint8),Config(thr_lo=0,thr_hi=0))
    assert not result["cls"].any()
    assert not result["edge"].any()


def test_rgb_conversion_is_exact_integer_contract():
    rgb=np.array([[[255,0,0],[0,255,0],[0,0,255],[19,97,203]]],np.uint8)
    result=edge_frame(rgb)
    np.testing.assert_array_equal(result["gray"],[[76,149,28,(77*19+150*97+29*203)//256]])
