#!/usr/bin/env python3
"""
Crop character sheets into individual emotion images.
Detects character positions automatically by finding non-white regions,
then crops each into separate files.

Usage: python3 crop-sheet.py <sheet.png> <output_dir> [emotion1,emotion2,...]
Default emotions: focused,happy,frustrated,neutral,sleepy
"""

import sys
import os
from PIL import Image
import numpy as np

def find_character_columns(img_array, threshold=240, min_gap=10):
    """Find columns where characters are by detecting non-white regions."""
    # Convert to grayscale if needed
    if len(img_array.shape) == 3:
        # Check if pixel is "not white" (any channel < threshold)
        not_white = np.any(img_array[:, :, :3] < threshold, axis=2)
    else:
        not_white = img_array < threshold

    # Project vertically — which columns have content?
    col_has_content = np.any(not_white, axis=0)

    # Find contiguous regions of content
    regions = []
    in_region = False
    start = 0

    for x in range(len(col_has_content)):
        if col_has_content[x] and not in_region:
            start = x
            in_region = True
        elif not col_has_content[x] and in_region:
            if x - start > min_gap:  # Only count regions wider than min_gap
                regions.append((start, x))
            in_region = False

    if in_region:
        regions.append((start, len(col_has_content)))

    # Merge regions that are close together (part of same character)
    merged = []
    for start, end in regions:
        if merged and start - merged[-1][1] < min_gap:
            merged[-1] = (merged[-1][0], end)
        else:
            merged.append((start, end))

    return merged

def find_content_rows(img_array, threshold=240):
    """Find the top and bottom of content."""
    if len(img_array.shape) == 3:
        not_white = np.any(img_array[:, :, :3] < threshold, axis=2)
    else:
        not_white = img_array < threshold

    row_has_content = np.any(not_white, axis=1)

    rows = np.where(row_has_content)[0]
    if len(rows) == 0:
        return 0, img_array.shape[0]

    return max(0, rows[0] - 5), min(img_array.shape[0], rows[-1] + 5)

def crop_sheet(sheet_path, output_dir, emotions):
    """Crop a character sheet into individual emotion images."""
    img = Image.open(sheet_path).convert("RGBA")
    img_array = np.array(img)

    # Find character columns
    columns = find_character_columns(img_array)

    print(f"Found {len(columns)} character regions in {sheet_path}")

    if len(columns) == 0:
        print("ERROR: No characters detected!")
        return False

    # If we found more or fewer than expected, try to split evenly
    if len(columns) != len(emotions):
        print(f"  Warning: found {len(columns)} regions but expected {len(emotions)}")
        if len(columns) > len(emotions):
            # Try merging close regions
            columns = columns[:len(emotions)]
        elif len(columns) < len(emotions):
            # Split the image evenly
            w = img.width
            step = w // len(emotions)
            columns = [(i * step, (i + 1) * step) for i in range(len(emotions))]
            print(f"  Falling back to even split: {step}px each")

    # Find vertical bounds
    top, bottom = find_content_rows(img_array)

    os.makedirs(output_dir, exist_ok=True)

    for i, (emotion, (left, right)) in enumerate(zip(emotions, columns)):
        # Add small padding
        pad = 5
        left = max(0, left - pad)
        right = min(img.width, right + pad)

        # Crop the character
        cropped = img.crop((left, top, right, bottom))

        # Make it square (pad shorter dimension)
        w, h = cropped.size
        size = max(w, h)
        square = Image.new("RGBA", (size, size), (255, 255, 255, 0))
        paste_x = (size - w) // 2
        paste_y = (size - h) // 2
        square.paste(cropped, (paste_x, paste_y))

        # Resize to 256x256 for quality
        square = square.resize((256, 256), Image.LANCZOS)

        out_path = os.path.join(output_dir, f"{emotion}.png")
        square.save(out_path)
        print(f"  Saved {emotion} → {out_path} (region {left}-{right})")

    return True

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 crop-sheet.py <sheet.png> <output_dir> [emotions]")
        sys.exit(1)

    sheet = sys.argv[1]
    output_dir = sys.argv[2]
    emotions = sys.argv[3].split(",") if len(sys.argv) > 3 else [
        "focused", "happy", "frustrated", "neutral", "sleepy"
    ]

    if not os.path.exists(sheet):
        print(f"ERROR: {sheet} not found")
        sys.exit(1)

    success = crop_sheet(sheet, output_dir, emotions)
    if not success:
        sys.exit(1)

if __name__ == "__main__":
    main()
