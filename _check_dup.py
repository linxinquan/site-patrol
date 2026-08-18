# -*- coding: utf-8 -*-
p = r"F:\GitHub\site-patrol\lib\data\mock\mock_data.dart"
lines = open(p, encoding="utf-8", errors="ignore").read().splitlines()
print("=== B05/B02 Floor lines ===")
for i, l in enumerate(lines):
    if "dy04_7_B0" in l and "Floor(" in l:
        print(i + 1, l)
print("=== B02 Drawing title ===")
for i, l in enumerate(lines):
    if "dy04_7_B02" in l and "Drawing(" in l:
        print("  next:", lines[i + 1])
