#!/usr/bin/env python3
# 复利计算
def compound(principal: float, rate: float, years: int) -> float:
    """每年复投一次"""
    for _ in range(years):
        principal *= (1 + rate)
    return principal

if __name__ == "__main__":
    print(compound(10000, 0.125, 22))
