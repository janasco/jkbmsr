#!/usr/bin/env python3
import os
import re
from pathlib import Path
import glob

SITE_DIR = str(Path(__file__).resolve().parent.parent / "site" / "public")

def main():
    files = sorted(glob.glob(f"{SITE_DIR}/*.html"))
    print(f"Total HTML files found: {len(files)}")
    all_target_files = {os.path.basename(f) for f in files}
    
    broken_links = []
    total_links = 0
    
    for f in files:
        fname = os.path.basename(f)
        with open(f, "r", encoding="utf-8") as fp:
            content = fp.read()
            
        # Match href="..." and onclick="window.location.href='...'"
        hrefs = re.findall(r'href=["\']([^"\']+\.html)["\']', content)
        onclicks = re.findall(r'window\.location\.href=[\'"]([^"\']+\.html)[\'"]', content)
        
        links = hrefs + onclicks
        total_links += len(links)
        
        for link in links:
            clean_link = link.split('#')[0].split('?')[0]
            if clean_link not in all_target_files:
                broken_links.append((fname, link))
                
    print(f"Total internal links scanned: {total_links}")
    if broken_links:
        print("❌ Found broken links:")
        for source, target in broken_links:
            print(f"  In {source} -> target '{target}' does NOT exist!")
        exit(1)
    else:
        print("✓ ALL internal links point to valid existing screens! 0 broken links.")

if __name__ == "__main__":
    main()
