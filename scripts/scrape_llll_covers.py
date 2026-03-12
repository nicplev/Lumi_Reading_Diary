#!/usr/bin/env python3
"""
Scrape cover images from Little Learners Love Literacy Shopify store.

Usage:
    pip install requests
    python scripts/scrape_llll_covers.py

This script:
1. Fetches all products from the LLLL Shopify /products.json endpoint
2. Reads the LEARNING LOGIC DATABASE.csv to get our product catalog
3. Fuzzy-matches CSV products to Shopify products
4. Downloads cover images to scripts/cover_images/
5. Outputs a JSON mapping file (scripts/llll_product_images.json)
"""

import csv
import json
import os
import re
import sys
import time
from pathlib import Path
from urllib.parse import urljoin

try:
    import requests
except ImportError:
    print("Please install requests: pip install requests")
    sys.exit(1)

BASE_URL = "https://www.littlelearnersloveliteracy.com.au"
PRODUCTS_JSON_URL = f"{BASE_URL}/products.json"
SCRIPT_DIR = Path(__file__).parent
CSV_PATH = SCRIPT_DIR.parent / "LEARNING LOGIC DATABASE.csv"
IMAGES_DIR = SCRIPT_DIR / "cover_images"
OUTPUT_JSON = SCRIPT_DIR / "llll_product_images.json"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "application/json, text/html, */*",
    "Accept-Language": "en-AU,en;q=0.9",
}

# Manual mapping for products whose names don't match Shopify slugs well.
# CSV ProductCode -> Shopify product handle (URL slug)
MANUAL_SLUG_MAP = {
    "LLRS1": "pip-and-tim-stage-1",
    "LLRS2": "pip-and-tim-stage-2",
    "LLRS3": "pip-and-tim-stage-3",
    "LLRS4": "pip-and-tim-stage-4",
    "LLRS4+": "pip-and-tim-stage-plus-4",
    "LLRS5": "pip-and-tim-stage-5",
    "LLRS6": "pip-and-tim-stage-6",
    "LLRS71": "pip-and-tim-stage-7-unit-1",
    "LLRS72": "pip-and-tim-stage-7-unit-2",
    "LLRS73": "pip-and-tim-stage-7-unit-3",
    "LLRS74": "pip-and-tim-stage-7-unit-4",
    "LLRS75": "pip-and-tim-stage-7-unit-5",
    "LLBW1": "little-learners-big-world-nonfiction-stage-1",
    "LLBW2": "little-learners-big-world-nonfiction-stage-2",
    "LLBW3": "little-learners-big-world-nonfiction-stage-3",
    "LLBW4": "little-learners-big-world-nonfiction-stage-4",
    "LLBW4+": "little-learners-big-world-nonfiction-stage-4-plus",
    "LLBW5": "little-learners-big-world-nonfiction-stage-5",
    "LLBW6": "little-learners-big-world-nonfiction-stage-6",
    "LLBW71": "little-learners-big-world-nonfiction-stage-7-unit-1",
    "LLBW72": "little-learners-big-world-nonfiction-stage-7-unit-2",
    "LLBW73": "little-learners-big-world-nonfiction-stage-7-unit-3",
    "LLBW74": "little-learners-big-world-nonfiction-stage-7-unit-4",
    "LLBW75": "little-learners-big-world-nonfiction-stage-7-unit-5",
    "TWK1": "the-wiz-kids-stage-1",
    "TWK2": "the-wiz-kids-stage-2",
    "TWK3": "the-wiz-kids-stage-3",
    "TWK4": "the-wiz-kids-stage-4",
    "TWKP4": "the-wiz-kids-stage-4-plus",
    "TWK5": "the-wiz-kids-stage-5",
    "TWK6": "the-wiz-kids-stage-6",
    "LLWD1": "wild-detectives-stage-1",
    "LLWD2": "wild-detectives-stage-2",
    "LLWD3": "wild-detectives-stage-3",
    "LLWD4": "wild-detectives-stage-4",
    "LLWD4+": "wild-detectives-stage-4-plus",
    "LLWD5": "wild-detectives-stage-5",
    "LLWD6": "wild-detectives-stage-6",
    "LLFK1": "fox-kid-and-the-rat-bot",
    "LLFK2": "fox-kid-and-the-mud-men",
    "LLFK3": "fox-kid-and-the-endless-frost",
    "LLFK4": "fox-kid-and-the-pond-trolls",
    "LLFK5": "fox-kid-and-the-big-sting",
    "LLFK6": "fox-kid-and-the-skull-twins",
    "LLFK7": "fox-kid-and-the-stink-bug",
    "LLFK8": "fox-kid-vs-fox-kid",
    "LLFK9": "fox-kid-and-the-extractor",
    "LLFK10": "fox-kid-and-the-fright-night",
    "MBS": "milos-birthday-surprise",
    "MFB": "milos-flipbook",
    "MAG": "milos-alphabet-games",
    "AAP": "ally-the-alligator-puppet",
    "SC1": "soundcheck",
    "SC2": "soundcheck-2",
    "MSS": "sound-swap",
}


def fetch_all_shopify_products():
    """Fetch all products from the Shopify /products.json endpoint."""
    all_products = []
    page = 1
    limit = 250  # Shopify max per page

    print("Fetching products from Shopify API...")
    while True:
        url = f"{PRODUCTS_JSON_URL}?limit={limit}&page={page}"
        print(f"  Page {page}...", end=" ")

        try:
            resp = requests.get(url, headers=HEADERS, timeout=30)
            resp.raise_for_status()
        except requests.RequestException as e:
            print(f"\n  Error fetching page {page}: {e}")
            if page == 1:
                print("\n  The /products.json endpoint may be disabled.")
                print("  Falling back to individual product page scraping...")
                return None
            break

        data = resp.json()
        products = data.get("products", [])
        print(f"got {len(products)} products")

        if not products:
            break

        all_products.extend(products)
        page += 1
        time.sleep(0.5)  # Be polite

    print(f"Total Shopify products fetched: {len(all_products)}")
    return all_products


def fetch_single_product_json(handle):
    """Fetch a single product by its handle/slug."""
    url = f"{BASE_URL}/products/{handle}.json"
    try:
        resp = requests.get(url, headers=HEADERS, timeout=15)
        if resp.status_code == 200:
            return resp.json().get("product")
        elif resp.status_code == 404:
            return None
        else:
            print(f"    HTTP {resp.status_code} for {handle}")
            return None
    except requests.RequestException as e:
        print(f"    Error fetching {handle}: {e}")
        return None


def read_csv_products():
    """Read the LEARNING LOGIC DATABASE CSV."""
    products = []
    with open(CSV_PATH, "r", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            code = row.get("ProductCode", "").strip()
            name = row.get("Name", "").strip()
            barcode = row.get("Barcode/ISBN", "").strip()
            if code and name:
                products.append({
                    "product_code": code,
                    "name": name,
                    "brand": row.get("Brand", "").strip(),
                    "barcode": barcode,
                })
    print(f"Read {len(products)} products from CSV")
    return products


def name_to_slug(name):
    """Convert a product name to a URL-friendly slug."""
    slug = name.lower()
    # Remove parenthetical state suffixes like (NSW), (VIC)
    slug = re.sub(r"\s*\((?:nsw|vic|qld|sa|tas)\)\s*", "", slug, flags=re.IGNORECASE)
    # Remove book number prefix like (Book 1), (Book 2)
    slug = re.sub(r"\(book\s*\d+\)\s*", "", slug, flags=re.IGNORECASE)
    # Replace special chars
    slug = re.sub(r"[''`]", "", slug)
    slug = re.sub(r"[&]", "and", slug)
    slug = re.sub(r"[^a-z0-9]+", "-", slug)
    slug = slug.strip("-")
    return slug


def match_csv_to_shopify(csv_products, shopify_products):
    """Match CSV products to Shopify products by handle/title."""
    # Build lookup by handle
    shopify_by_handle = {}
    shopify_by_title_lower = {}
    for sp in shopify_products:
        handle = sp.get("handle", "")
        title = sp.get("title", "").lower().strip()
        shopify_by_handle[handle] = sp
        shopify_by_title_lower[title] = sp

    matches = {}
    unmatched = []

    for cp in csv_products:
        code = cp["product_code"]
        name = cp["name"]

        # Try manual mapping first
        if code in MANUAL_SLUG_MAP:
            handle = MANUAL_SLUG_MAP[code]
            if handle in shopify_by_handle:
                matches[code] = shopify_by_handle[handle]
                continue

        # Try exact title match
        if name.lower().strip() in shopify_by_title_lower:
            matches[code] = shopify_by_title_lower[name.lower().strip()]
            continue

        # Try slug match
        slug = name_to_slug(name)
        if slug in shopify_by_handle:
            matches[code] = shopify_by_handle[slug]
            continue

        # Try partial matching
        found = False
        for handle, sp in shopify_by_handle.items():
            sp_title = sp.get("title", "").lower()
            if name.lower() in sp_title or sp_title in name.lower():
                matches[code] = sp
                found = True
                break

        if not found:
            unmatched.append(cp)

    return matches, unmatched


def try_individual_fetch(csv_products):
    """Fall back to fetching individual product pages when /products.json fails."""
    matches = {}
    unmatched = []

    # Collect unique slugs to try (deduplicate state variants)
    seen_slugs = set()
    products_to_try = []

    for cp in csv_products:
        code = cp["product_code"]
        name = cp["name"]

        if code in MANUAL_SLUG_MAP:
            slug = MANUAL_SLUG_MAP[code]
        else:
            slug = name_to_slug(name)

        if slug in seen_slugs:
            # This is a state variant - will share the same image
            products_to_try.append((cp, slug, True))
        else:
            seen_slugs.add(slug)
            products_to_try.append((cp, slug, False))

    fetched_cache = {}
    total = len(products_to_try)

    for i, (cp, slug, is_variant) in enumerate(products_to_try):
        code = cp["product_code"]
        print(f"  [{i + 1}/{total}] {code}: {cp['name']}", end=" ")

        if slug in fetched_cache:
            if fetched_cache[slug] is not None:
                matches[code] = fetched_cache[slug]
                print("(cached)")
            else:
                unmatched.append(cp)
                print("(cached - not found)")
            continue

        product = fetch_single_product_json(slug)
        fetched_cache[slug] = product

        if product:
            matches[code] = product
            print("OK")
        else:
            unmatched.append(cp)
            print("NOT FOUND")

        if not is_variant:
            time.sleep(0.3)  # Be polite

    return matches, unmatched


def get_best_image_url(shopify_product, size="800x"):
    """Extract the best cover image URL from a Shopify product."""
    images = shopify_product.get("images", []) or shopify_product.get("image", [])
    if not images:
        image = shopify_product.get("image")
        if image:
            images = [image] if isinstance(image, dict) else []

    if not images:
        return None

    # Use the first image (typically the main product/cover image)
    img = images[0] if isinstance(images, list) else images
    src = img.get("src", "")

    if not src:
        return None

    # Shopify CDN images support size suffixes like _800x before the extension
    # e.g., ...image.jpg -> ...image_800x.jpg
    if size and "cdn.shopify.com" in src:
        base, ext = os.path.splitext(src)
        src = f"{base}_{size}{ext}"

    return src


def download_image(url, filepath):
    """Download an image to the local filesystem."""
    try:
        resp = requests.get(url, headers=HEADERS, timeout=30, stream=True)
        resp.raise_for_status()
        with open(filepath, "wb") as f:
            for chunk in resp.iter_content(chunk_size=8192):
                f.write(chunk)
        return True
    except requests.RequestException as e:
        print(f"    Download failed: {e}")
        return False


def main():
    if not CSV_PATH.exists():
        print(f"CSV not found at {CSV_PATH}")
        sys.exit(1)

    IMAGES_DIR.mkdir(parents=True, exist_ok=True)

    # Step 1: Read CSV
    csv_products = read_csv_products()

    # Step 2: Try /products.json first
    shopify_products = fetch_all_shopify_products()

    if shopify_products is not None:
        # Step 3a: Match via bulk data
        matches, unmatched = match_csv_to_shopify(csv_products, shopify_products)
        print(f"\nMatched: {len(matches)} | Unmatched: {len(unmatched)}")

        # Try individual fetch for unmatched
        if unmatched:
            print(f"\nTrying individual fetch for {len(unmatched)} unmatched products...")
            extra_matches, still_unmatched = try_individual_fetch(unmatched)
            matches.update(extra_matches)
            unmatched = still_unmatched
            print(f"After individual fetch - Matched: {len(matches)} | Still unmatched: {len(still_unmatched)}")
    else:
        # Step 3b: Fall back to individual product page scraping
        print("\nFalling back to individual product fetching...")
        matches, unmatched = try_individual_fetch(csv_products)
        print(f"\nMatched: {len(matches)} | Unmatched: {len(unmatched)}")

    # Step 4: Download images and build output
    print("\n--- Downloading cover images ---")
    results = []
    downloaded = 0
    skipped = 0
    failed = 0

    for cp in csv_products:
        code = cp["product_code"]
        entry = {
            "product_code": code,
            "name": cp["name"],
            "barcode": cp["barcode"],
            "cover_image_url": None,
            "local_image_path": None,
            "shopify_handle": None,
        }

        if code in matches:
            sp = matches[code]
            entry["shopify_handle"] = sp.get("handle", "")
            img_url = get_best_image_url(sp)

            if img_url:
                entry["cover_image_url"] = img_url
                ext = os.path.splitext(img_url.split("?")[0])[1] or ".jpg"
                safe_code = code.replace("+", "plus").replace("/", "-")
                filename = f"{safe_code}{ext}"
                filepath = IMAGES_DIR / filename

                if filepath.exists():
                    entry["local_image_path"] = str(filepath)
                    skipped += 1
                    print(f"  [{code}] Already exists: {filename}")
                else:
                    print(f"  [{code}] Downloading {filename}...", end=" ")
                    if download_image(img_url, filepath):
                        entry["local_image_path"] = str(filepath)
                        downloaded += 1
                        print("OK")
                    else:
                        failed += 1
                        print("FAILED")
                    time.sleep(0.2)
            else:
                print(f"  [{code}] No image available")
        else:
            print(f"  [{code}] No Shopify match - {cp['name']}")

        results.append(entry)

    # Step 5: Write output JSON
    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)

    # Summary
    print(f"\n{'=' * 50}")
    print(f"SUMMARY")
    print(f"{'=' * 50}")
    print(f"Total CSV products:    {len(csv_products)}")
    print(f"Shopify matches:       {len(matches)}")
    print(f"Unmatched:             {len(unmatched)}")
    print(f"Images downloaded:     {downloaded}")
    print(f"Images skipped (exist):{skipped}")
    print(f"Images failed:         {failed}")
    print(f"\nOutput JSON: {OUTPUT_JSON}")
    print(f"Images dir:  {IMAGES_DIR}")

    if unmatched:
        print(f"\nUnmatched products:")
        for cp in unmatched:
            print(f"  {cp['product_code']}: {cp['name']}")


if __name__ == "__main__":
    main()
