#!/usr/bin/env python3
"""
Build a local book database JSON from the LEARNING LOGIC DATABASE CSV
and scraped cover image data.

This creates a JSON file that maps ISBN/barcodes to book metadata,
acting as a local replacement for the Google Books API for LLLL products.

Usage:
    python scripts/build_book_database.py

Output:
    assets/data/llll_books_db.json
"""

import csv
import json
import os
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
CSV_PATH = PROJECT_ROOT / "LEARNING LOGIC DATABASE.csv"
COVER_IMAGES_JSON = SCRIPT_DIR / "llll_product_images.json"
OUTPUT_DIR = PROJECT_ROOT / "assets" / "data"
OUTPUT_PATH = OUTPUT_DIR / "llll_books_db.json"

# Maps product code prefixes to series info
SERIES_INFO = {
    "LLRS": {"series": "Pip and Tim", "type": "reader"},
    "LLBW": {"series": "Little Learners, Big World Nonfiction", "type": "reader"},
    "TWK": {"series": "The Wiz Kids", "type": "reader"},
    "TWKP": {"series": "The Wiz Kids", "type": "reader"},
    "LLWD": {"series": "Wild Detectives", "type": "reader"},
    "LLFK": {"series": "Fox Kid", "type": "chapter_book"},
    "LLFKBOX": {"series": "Fox Kid Ka-Blam! Box", "type": "box_set"},
    "LLFKWB": {"series": "Fox Kid Workbook", "type": "workbook"},
    "LLWKBK": {"series": "Workbook", "type": "workbook"},
    "MBS": {"series": "Milo", "type": "resource"},
    "MFB": {"series": "Milo", "type": "resource"},
    "MAG": {"series": "Milo", "type": "resource"},
    "MAF": {"series": "Milo", "type": "resource"},
    "MBSP": {"series": "Milo", "type": "resource"},
    "MMWP": {"series": "Milo", "type": "resource"},
    "MRMG": {"series": "Milo", "type": "resource"},
    "SC": {"series": "SoundCheck", "type": "resource"},
    "MSS": {"series": "Sound Swap", "type": "resource"},
    "AAP": {"series": "Ally the Alligator", "type": "resource"},
    "FF-": {"series": "Fluency Fun", "type": "reader"},
    "TAR": {"series": "Teacher Activity Resource", "type": "teacher_resource"},
    "SGRN": {"series": "Small Group Reading Teacher Notes", "type": "teacher_resource"},
    "MRG": {"series": "Read and Grab Word Game", "type": "resource"},
    "RRW": {"series": "Read, Write and Draw", "type": "workbook"},
    "HRJ": {"series": "Home Reading Journal", "type": "resource"},
    "BG": {"series": "Bingo Games", "type": "resource"},
    "SSC": {"series": "Speed Sounds and Chants Cards", "type": "resource"},
    "CCS": {"series": "Character Cards", "type": "resource"},
    "PSC": {"series": "Sounds Chart", "type": "resource"},
    "HWP": {"series": "Heart Word Posters", "type": "resource"},
    "LLAR": {"series": "Assessment", "type": "teacher_resource"},
    "LLAS": {"series": "Assessment", "type": "teacher_resource"},
    "LLBWQ": {"series": "Big World Quiz", "type": "resource"},
}


def extract_stage(name, product_code):
    """Extract the reading stage/level from a product name or code."""
    # Try to extract from name
    m = re.search(r"Stage\s+(\d+\+?)", name, re.IGNORECASE)
    if m:
        return m.group(1)

    m = re.search(r"Stage\s+(\d+)\s+Unit\s+(\d+)", name, re.IGNORECASE)
    if m:
        return f"{m.group(1)}.{m.group(2)}"

    # Try from product code
    m = re.search(r"(\d+)\+?$", product_code.split("-")[0])
    if m:
        return m.group(0)

    return None


def get_series_info(product_code):
    """Get series info by matching product code prefix."""
    # Sort by length descending so longer prefixes match first
    for prefix in sorted(SERIES_INFO.keys(), key=len, reverse=True):
        if product_code.startswith(prefix):
            return SERIES_INFO[prefix]
    return {"series": "Little Learners Love Literacy", "type": "other"}


def normalise_isbn(isbn_str):
    """Normalise an ISBN string: remove hyphens and spaces."""
    if not isbn_str:
        return None
    cleaned = re.sub(r"[^0-9Xx]", "", isbn_str.strip())
    if len(cleaned) in (10, 13):
        return cleaned
    return None


def build_database():
    if not CSV_PATH.exists():
        print(f"CSV not found: {CSV_PATH}")
        sys.exit(1)

    # Load cover image mapping if available
    cover_map = {}  # product_code -> image info
    if COVER_IMAGES_JSON.exists():
        with open(COVER_IMAGES_JSON, "r", encoding="utf-8") as f:
            image_data = json.load(f)
            for entry in image_data:
                code = entry.get("product_code", "")
                if code:
                    cover_map[code] = entry
        print(f"Loaded {len(cover_map)} cover image entries")
    else:
        print(f"No cover images JSON found at {COVER_IMAGES_JSON}")
        print("Run scrape_llll_covers.py first for cover images.")
        print("Continuing without covers...\n")

    # Read CSV
    products = []
    with open(CSV_PATH, "r", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            code = row.get("ProductCode", "").strip()
            name = row.get("Name", "").strip()
            brand = row.get("Brand", "").strip()
            barcode = row.get("Barcode/ISBN", "").strip()
            if code and name:
                products.append({
                    "product_code": code,
                    "name": name,
                    "brand": brand,
                    "barcode_raw": barcode,
                })

    print(f"Read {len(products)} products from CSV")

    # Build the database
    # Two indexes: by ISBN and by product code
    books_by_isbn = {}
    books_by_code = {}
    all_books = []

    for prod in products:
        code = prod["product_code"]
        name = prod["name"]
        barcode_raw = prod["barcode_raw"]

        isbn = normalise_isbn(barcode_raw)
        series_info = get_series_info(code)
        stage = extract_stage(name, code)

        # Get cover image URL from scraped data
        cover_url = None
        shopify_handle = None
        if code in cover_map:
            cover_url = cover_map[code].get("cover_image_url")
            shopify_handle = cover_map[code].get("shopify_handle")

        # If this is a state variant without a cover, try the base product
        if not cover_url and "-" in code:
            base_code = code.split("-")[0]
            if base_code in cover_map:
                cover_url = cover_map[base_code].get("cover_image_url")
                shopify_handle = cover_map[base_code].get("shopify_handle")

        # Clean up the display name - remove state suffixes for display
        display_name = re.sub(r"\s*\((?:NSW|VIC|QLD|SA|TAS)\)\s*$", "", name)
        # Remove book number prefix like (Book 1)
        display_name = re.sub(r"^\(Book\s*\d+\)\s*", "", display_name)

        book_entry = {
            "productCode": code,
            "title": display_name,
            "brand": prod["brand"],
            "isbn": isbn,
            "barcodeRaw": barcode_raw if barcode_raw and barcode_raw != "TBC" else None,
            "coverImageUrl": cover_url,
            "series": series_info["series"],
            "productType": series_info["type"],
            "readingStage": stage,
            "shopifyHandle": shopify_handle,
        }

        all_books.append(book_entry)
        books_by_code[code] = book_entry

        # Index by ISBN (multiple products can share an ISBN for state variants)
        if isbn:
            if isbn not in books_by_isbn:
                books_by_isbn[isbn] = []
            books_by_isbn[isbn].append(code)

    # Build the final output
    database = {
        "version": 1,
        "generatedAt": __import__("datetime").datetime.now().isoformat(),
        "totalBooks": len(all_books),
        "books": books_by_code,
        "isbnIndex": books_by_isbn,
    }

    # Write output
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(database, f, indent=2, ensure_ascii=False)

    # Stats
    has_isbn = sum(1 for b in all_books if b["isbn"])
    has_cover = sum(1 for b in all_books if b["coverImageUrl"])

    print(f"\n{'=' * 50}")
    print("BOOK DATABASE BUILT")
    print(f"{'=' * 50}")
    print(f"Total entries:     {len(all_books)}")
    print(f"With ISBN:         {has_isbn}")
    print(f"With cover image:  {has_cover}")
    print(f"Unique ISBNs:      {len(books_by_isbn)}")
    print(f"\nOutput: {OUTPUT_PATH}")


if __name__ == "__main__":
    build_database()
