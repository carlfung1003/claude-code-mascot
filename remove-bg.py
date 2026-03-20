#!/usr/bin/env python3
"""Remove white background from images, making it transparent."""
import sys, os, glob
from PIL import Image
import numpy as np

def remove_white_bg(path, threshold=230):
    img = Image.open(path).convert("RGBA")
    data = np.array(img)
    
    # Find pixels where R, G, B are all above threshold (white/near-white)
    white_mask = np.all(data[:, :, :3] > threshold, axis=2)
    
    # Set alpha to 0 for white pixels
    data[white_mask, 3] = 0
    
    # Also clean up near-white edges (anti-aliasing)
    edge_mask = np.all(data[:, :, :3] > threshold - 20, axis=2) & (data[:, :, 3] > 0)
    # Make edge pixels semi-transparent based on how white they are
    for y, x in zip(*np.where(edge_mask)):
        brightness = np.mean(data[y, x, :3])
        if brightness > threshold - 20:
            alpha = int(255 * (1 - (brightness - (threshold - 20)) / (255 - (threshold - 20))))
            data[y, x, 3] = min(data[y, x, 3], max(0, alpha))
    
    # Trim transparent borders
    alpha = data[:, :, 3]
    rows = np.any(alpha > 0, axis=1)
    cols = np.any(alpha > 0, axis=0)
    if rows.any() and cols.any():
        rmin, rmax = np.where(rows)[0][[0, -1]]
        cmin, cmax = np.where(cols)[0][[0, -1]]
        # Add small padding
        pad = 4
        rmin = max(0, rmin - pad)
        rmax = min(data.shape[0], rmax + pad)
        cmin = max(0, cmin - pad)
        cmax = min(data.shape[1], cmax + pad)
        data = data[rmin:rmax+1, cmin:cmax+1]
    
    # Make square
    result = Image.fromarray(data)
    w, h = result.size
    size = max(w, h)
    square = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    square.paste(result, ((size - w) // 2, (size - h) // 2))
    
    # Resize to 256x256
    square = square.resize((256, 256), Image.LANCZOS)
    square.save(path)

if len(sys.argv) < 2:
    print("Usage: python3 remove-bg.py <dir_or_file> [...]")
    sys.exit(1)

for arg in sys.argv[1:]:
    if os.path.isdir(arg):
        files = glob.glob(os.path.join(arg, "*.png"))
    else:
        files = [arg]
    for f in files:
        if "sheet" in f:
            continue
        print(f"  Processing {f}")
        remove_white_bg(f)

print("Done!")
