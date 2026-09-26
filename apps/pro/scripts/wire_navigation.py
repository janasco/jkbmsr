#!/usr/bin/env python3
"""
Wire navigation between all 13 screens in JKBMSR Pro:
- Standardizes BottomNavBar across all 13 screens with 5 core tabs (Home, Explore, Monitor, Community, Profile)
- Wires top-bar back buttons, header icons, and action sheet triggers
- Connects in-screen cards, buttons, and action bars to their target flows
"""

import os
import re
from pathlib import Path

SITE_DIR = str(Path(__file__).resolve().parent.parent / "site" / "public")

SCREEN_ACTIVE_TAB = {
    "home.html": "home",
    "explore.html": "explore",
    "template-detail.html": "explore",
    "template-spec.html": "explore",
    "template-studio.html": "explore",
    "template-remix.html": "explore",
    "flasher-transfer.html": "explore",
    "device-monitor.html": "monitor",
    "alerts-diagnostics.html": "monitor",
    "community-feed.html": "community",
    "create-template.html": "community",
    "user-profile.html": "profile",
    "settings.html": "profile",
}

def generate_bottom_nav(active_tab):
    tabs = [
        ("home", "home.html", "home", "Home"),
        ("explore", "explore.html", "explore", "Explore"),
        ("monitor", "device-monitor.html", "sensors", "Monitor"),
        ("community", "community-feed.html", "diversity_3", "Community"),
        ("profile", "user-profile.html", "person", "Profile"),
    ]
    
    tab_html = []
    for tab_id, href, icon, label in tabs:
        is_active = (tab_id == active_tab)
        if is_active:
            btn = f"""    <a href="{href}" class="flex flex-col items-center justify-center text-white relative after:content-[''] after:absolute after:-bottom-1 after:w-1.5 after:h-1.5 after:bg-white after:rounded-full after:shadow-[0_0_8px_rgba(255,255,255,0.9)] scale-100 transition-all">
      <span class="material-symbols-outlined text-[24px]" style="font-variation-settings: 'FILL' 1;">{icon}</span>
      <span class="text-[10px] font-medium tracking-wide mt-0.5">{label}</span>
    </a>"""
        else:
            btn = f"""    <a href="{href}" class="flex flex-col items-center justify-center text-[#64748B] hover:text-white/80 scale-95 active:scale-90 transition-all">
      <span class="material-symbols-outlined text-[24px]">{icon}</span>
      <span class="text-[10px] font-medium tracking-wide mt-0.5">{label}</span>
    </a>"""
        tab_html.append(btn)
        
    return f"""<!-- BottomNavBar (Standardized JKBMSR Pro) -->
<nav class="bg-[#12171F]/95 backdrop-blur-md border-t border-[rgba(255,255,255,0.12)] fixed bottom-0 left-0 right-0 max-w-[480px] mx-auto z-50 flex justify-around items-center px-4 py-2 rounded-t-2xl pb-6">
{chr(10).join(tab_html)}
</nav>"""

def wire_screen(filename):
    filepath = os.path.join(SITE_DIR, filename)
    if not os.path.exists(filepath):
        print(f"File not found: {filename}")
        return
        
    with open(filepath, "r", encoding="utf-8") as f:
        html = f.read()

    active_tab = SCREEN_ACTIVE_TAB.get(filename, "home")
    new_bottom_nav = generate_bottom_nav(active_tab)

    # 1. Replace existing <nav ...> ... </nav> bottom bar with standardized bottom bar
    nav_pattern = re.compile(r'<!-- BottomNavBar.*?-->.*?<nav.*?</nav>', re.DOTALL | re.IGNORECASE)
    if nav_pattern.search(html):
        html = nav_pattern.sub(new_bottom_nav, html)
    else:
        # Try generic nav matching at bottom
        nav_pattern2 = re.compile(r'<nav\s+class="[^"]*fixed\s+bottom-0[^"]*".*?</nav>', re.DOTALL | re.IGNORECASE)
        if nav_pattern2.search(html):
            html = nav_pattern2.sub(new_bottom_nav, html)
        elif "</body>" in html:
            html = html.replace("</body>", f"{new_bottom_nav}\n</body>")

    # 2. Specific button / card wiring per screen
    if filename == "home.html":
        # Search input click -> explore.html
        html = re.sub(
            r'(<input[^>]*placeholder="Search templates[^"]*"[^>]*)/?>',
            r'\1 onclick="window.location.href=\'explore.html\'" style="cursor:pointer;" />',
            html
        )
        # Category chips -> explore.html
        html = re.sub(
            r'(<button[^>]*class="[^"]*rounded-full[^"]*"[^>]*>\s*<span>[^<]*</span>\s*(Trending|Solar|Campervan|Marine|Powerwall)[^<]*</button>)',
            r'<a href="explore.html">\1</a>',
            html
        )
        # Workshop Pack live strip -> device-monitor.html
        html = re.sub(
            r'(<div class="surface-layer rounded-xl p-md flex flex-col gap-sm relative overflow-hidden group cursor-pointer[^"]*")',
            r'\1 onclick="window.location.href=\'device-monitor.html\'"',
            html
        )
        # "View All" featured profiles -> explore.html
        html = html.replace(
            '<button class="text-sm text-text-muted hover:text-white transition-colors">View All</button>',
            '<a href="explore.html" class="text-sm text-[#64748B] hover:text-white transition-colors">View All</a>'
        )
        # Card 1 "Apply to BMS" and "View Spec"
        html = html.replace(
            '<button class="flex-1 bg-primary text-background font-semibold py-2 rounded-lg text-sm hover:bg-primary/90 transition-colors">Apply to BMS</button>',
            '<a href="template-detail.html" class="flex-1 bg-white text-black font-semibold py-2 rounded-lg text-sm hover:bg-white/90 transition-colors text-center">Apply to BMS</a>'
        )
        html = html.replace(
            '<button class="flex-1 bg-transparent border border-hairline text-white font-medium py-2 rounded-lg text-sm hover:border-white/50 transition-colors">View Spec</button>',
            '<a href="template-spec.html" class="flex-1 bg-transparent border border-[rgba(255,255,255,0.12)] text-white font-medium py-2 rounded-lg text-sm hover:border-white/50 transition-colors text-center">View Spec</a>'
        )
        # Card 1 title link
        html = html.replace(
            '<h3 class="font-body-md text-body-md font-semibold text-white leading-tight">EVE 280Ah 16S Daily Solar Cycle</h3>',
            '<h3 class="font-body-md text-body-md font-semibold text-white leading-tight"><a href="template-detail.html" class="hover:underline">EVE 280Ah 16S Daily Solar Cycle</a></h3>'
        )
        # Card 2 title link
        html = html.replace(
            '<h3 class="font-body-md text-body-md font-semibold text-white leading-tight">Overkill 8S 24V Campervan Setup</h3>',
            '<h3 class="font-body-md text-body-md font-semibold text-white leading-tight"><a href="template-detail.html" class="hover:underline">Overkill 8S 24V Campervan Setup</a></h3>'
        )

    elif filename == "explore.html":
        # Back arrow in header -> home.html
        html = re.sub(
            r'(<span class="material-symbols-outlined[^"]*">\s*(arrow_back|chevron_left)\s*</span>)',
            r'<a href="home.html" class="text-white hover:opacity-80 transition-opacity">\1</a>',
            html
        )
        # Template cards link to template-detail.html
        html = html.replace('href="#"', 'href="template-detail.html"')

    elif filename == "template-detail.html":
        # Back arrow -> home.html
        html = re.sub(
            r'(<span class="material-symbols-outlined[^"]*">\s*(arrow_back|chevron_left)\s*</span>)',
            r'<a href="home.html" class="text-white hover:opacity-80 transition-opacity">\1</a>',
            html
        )
        # Wire buttons
        html = re.sub(r'href="#"', 'href="template-spec.html"', html)
        # Flash CTA
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Flash to BMS|Apply to BMS|1-Click Flash|Flash Profile)(.*?)</button>',
            r'<a href="flasher-transfer.html"\1 class="flex items-center justify-center gap-2 bg-white text-black font-semibold rounded-full py-3 px-6 hover:bg-white/90 transition-all">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )
        # View Specs CTA
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(View Full Spec|View Specs|Technical Specs)(.*?)</button>',
            r'<a href="template-spec.html"\1 class="flex items-center justify-center gap-2 border border-[rgba(255,255,255,0.12)] text-white font-medium rounded-full py-3 px-6 hover:border-white/50 transition-all">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )
        # Customize / Edit / Tune CTA
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Customize|Edit Profile|Tune in Studio|Open Studio)(.*?)</button>',
            r'<a href="template-studio.html"\1 class="flex items-center justify-center gap-2 border border-[rgba(255,255,255,0.12)] text-white font-medium rounded-full py-3 px-6 hover:border-white/50 transition-all">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )
        # Compare / Diff CTA
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Compare Diff|Remix & Diff|Diff)(.*?)</button>',
            r'<a href="template-remix.html"\1 class="flex items-center justify-center gap-2 border border-[rgba(255,255,255,0.12)] text-white font-medium rounded-full py-3 px-6 hover:border-white/50 transition-all">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )

    elif filename == "template-spec.html":
        # Back arrow -> template-detail.html
        html = re.sub(
            r'(<span class="material-symbols-outlined[^"]*">\s*(arrow_back|chevron_left)\s*</span>)',
            r'<a href="template-detail.html" class="text-white hover:opacity-80 transition-opacity">\1</a>',
            html
        )
        # Action buttons
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Tune Parameters|Edit in Studio|Customize)(.*?)</button>',
            r'<a href="template-studio.html"\1 class="flex items-center justify-center gap-2 border border-[rgba(255,255,255,0.12)] text-white font-medium rounded-full py-3 px-6 hover:border-white/50 transition-all">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Flash to Hardware|Proceed to Flash|Flash to BMS)(.*?)</button>',
            r'<a href="flasher-transfer.html"\1 class="flex items-center justify-center gap-2 bg-white text-black font-semibold rounded-full py-3 px-6 hover:bg-white/90 transition-all">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )

    elif filename == "template-studio.html":
        # Back arrow -> template-detail.html
        html = re.sub(
            r'(<span class="material-symbols-outlined[^"]*">\s*(arrow_back|chevron_left)\s*</span>)',
            r'<a href="template-detail.html" class="text-white hover:opacity-80 transition-opacity">\1</a>',
            html
        )
        # Bottom sticky actions: Compare Diff -> template-remix.html, Flash to BMS -> flasher-transfer.html
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Compare Diff|Remix & Diff|Diff)(.*?)</button>',
            r'<a href="template-remix.html"\1 class="flex items-center justify-center gap-2 border border-[rgba(255,255,255,0.12)] text-white font-medium rounded-full py-3 px-6 hover:border-white/50 transition-all">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Flash to BMS|Proceed to Flash|Flash Profile)(.*?)</button>',
            r'<a href="flasher-transfer.html"\1 class="flex items-center justify-center gap-2 bg-white text-black font-semibold rounded-full py-3 px-6 hover:bg-white/90 transition-all">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )

    elif filename == "template-remix.html":
        # Back arrow -> template-studio.html
        html = re.sub(
            r'(<span class="material-symbols-outlined[^"]*">\s*(arrow_back|chevron_left)\s*</span>)',
            r'<a href="template-studio.html" class="text-white hover:opacity-80 transition-opacity">\1</a>',
            html
        )
        # Back to Studio / Proceed to Flash
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Back to Studio|Back to Editor)(.*?)</button>',
            r'<a href="template-studio.html"\1 class="flex items-center justify-center gap-2 border border-[rgba(255,255,255,0.12)] text-white font-medium rounded-full py-3 px-6 hover:border-white/50 transition-all">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Proceed to Flash|Flash to BMS|Start Flash)(.*?)</button>',
            r'<a href="flasher-transfer.html"\1 class="flex items-center justify-center gap-2 bg-white text-black font-semibold rounded-full py-3 px-6 hover:bg-white/90 transition-all">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )

    elif filename == "flasher-transfer.html":
        # Cancel / Close -> home.html
        html = re.sub(
            r'(<span class="material-symbols-outlined[^"]*">\s*(close|arrow_back|chevron_left)\s*</span>)',
            r'<a href="home.html" class="text-white hover:opacity-80 transition-opacity">\1</a>',
            html
        )
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Cancel)(.*?)</button>',
            r'<a href="home.html"\1 class="text-center px-4 py-1.5 border border-[rgba(255,255,255,0.12)] text-white rounded-full text-xs hover:border-white/50 transition-colors">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Open Live Monitor|View Live Telemetry|Live Monitor)(.*?)</button>',
            r'<a href="device-monitor.html"\1 class="flex items-center justify-center gap-2 bg-white text-black font-semibold rounded-full py-3 px-6 hover:bg-white/90 transition-all text-center">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Back to Home|Done|Finish)(.*?)</button>',
            r'<a href="home.html"\1 class="flex items-center justify-center gap-2 border border-[rgba(255,255,255,0.12)] text-white font-medium rounded-full py-3 px-6 hover:border-white/50 transition-all text-center">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )

    elif filename == "device-monitor.html":
        # Top bar alert bell -> alerts-diagnostics.html
        html = re.sub(
            r'(<span class="material-symbols-outlined[^"]*">\s*(notifications_active|notifications|error|warning)\s*</span>)',
            r'<a href="alerts-diagnostics.html" class="text-white hover:opacity-80 transition-opacity">\1</a>',
            html
        )
        # Action buttons
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Browse Templates to Flash|Browse Profiles|Templates)(.*?)</button>',
            r'<a href="explore.html"\1 class="flex items-center justify-center gap-2 border border-[rgba(255,255,255,0.12)] text-white font-medium rounded-full py-3 px-6 hover:border-white/50 transition-all text-center">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Diagnostic Center|Diagnostics|View Alarms)(.*?)</button>',
            r'<a href="alerts-diagnostics.html"\1 class="flex items-center justify-center gap-2 border border-[rgba(255,255,255,0.12)] text-white font-medium rounded-full py-3 px-6 hover:border-white/50 transition-all text-center">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )

    elif filename == "alerts-diagnostics.html":
        # Back arrow -> device-monitor.html
        html = re.sub(
            r'(<span class="material-symbols-outlined[^"]*">\s*(arrow_back|chevron_left)\s*</span>)',
            r'<a href="device-monitor.html" class="text-white hover:opacity-80 transition-opacity">\1</a>',
            html
        )
        # Tune balancer button -> template-studio.html
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Tune Balancer|Balance Parameters)(.*?)</button>',
            r'<a href="template-studio.html"\1 class="px-4 py-1.5 border border-[rgba(255,255,255,0.12)] text-white rounded-full text-xs hover:border-white/50 transition-colors">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )
        # Inspect flash history -> flasher-transfer.html
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Inspect Firmware Flash History|Flash History)(.*?)</button>',
            r'<a href="flasher-transfer.html"\1 class="flex items-center justify-center gap-2 border border-[rgba(255,255,255,0.12)] text-white font-medium rounded-full py-3 px-6 hover:border-white/50 transition-all text-center">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )

    elif filename == "community-feed.html":
        # "+" button in top bar or FAB -> create-template.html
        html = re.sub(
            r'(<span class="material-symbols-outlined[^"]*">\s*add\s*</span>)',
            r'<a href="create-template.html" class="text-white hover:opacity-80 transition-opacity">\1</a>',
            html
        )
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Share Setup|New Post|\+ Share)(.*?)</button>',
            r'<a href="create-template.html"\1 class="flex items-center justify-center gap-2 bg-white text-black font-semibold rounded-full py-3 px-6 hover:bg-white/90 transition-all shadow-lg text-center">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )
        # Template pill in build card -> template-detail.html
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Template:\s*[^<]+)(.*?)</button>',
            r'<a href="template-detail.html"\1 class="inline-flex items-center gap-2 px-3 py-1.5 bg-[#1A202C] border border-[rgba(255,255,255,0.12)] text-white rounded-full text-xs hover:border-white/50 transition-colors">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )
        # Avatars -> user-profile.html
        html = html.replace('@solar_andy', '<a href="user-profile.html" class="hover:underline">@solar_andy</a>')
        html = html.replace('@vanlife_nordic', '<a href="user-profile.html" class="hover:underline">@vanlife_nordic</a>')

    elif filename == "create-template.html":
        # Back arrow -> community-feed.html
        html = re.sub(
            r'(<span class="material-symbols-outlined[^"]*">\s*(arrow_back|chevron_left)\s*</span>)',
            r'<a href="community-feed.html" class="text-white hover:opacity-80 transition-opacity">\1</a>',
            html
        )
        # Tune in Studio -> template-studio.html
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Tune in Studio|Open Studio)(.*?)</button>',
            r'<a href="template-studio.html"\1 class="flex items-center justify-center gap-2 border border-[rgba(255,255,255,0.12)] text-white font-medium rounded-full py-3 px-6 hover:border-white/50 transition-all text-center">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )
        # Publish to Community -> template-detail.html
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Publish to Community|Publish Template|Publish)(.*?)</button>',
            r'<a href="template-detail.html"\1 class="flex items-center justify-center gap-2 bg-white text-black font-semibold rounded-full py-3 px-6 hover:bg-white/90 transition-all text-center">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )

    elif filename == "user-profile.html":
        # Settings gear icon -> settings.html
        html = re.sub(
            r'(<span class="material-symbols-outlined[^"]*">\s*settings\s*</span>)',
            r'<a href="settings.html" class="text-white hover:opacity-80 transition-opacity">\1</a>',
            html
        )
        # "Open Monitor" button -> device-monitor.html
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Open Monitor|Monitor)(.*?)</button>',
            r'<a href="device-monitor.html"\1 class="flex items-center justify-center gap-2 bg-white text-black font-semibold rounded-full py-2 px-5 hover:bg-white/90 transition-all text-center text-xs">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )
        # "Tune in Studio" button -> template-studio.html
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(Tune in Studio)(.*?)</button>',
            r'<a href="template-studio.html"\1 class="flex items-center justify-center gap-2 border border-[rgba(255,255,255,0.12)] text-white font-medium rounded-full py-2 px-4 hover:border-white/50 transition-all text-center text-xs">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )
        # "+" FAB -> create-template.html
        html = re.sub(
            r'<button([^>]*?)>(\s*<[^>]+>\s*)?(New Profile|\+ New Profile|\+)(.*?)</button>',
            r'<a href="create-template.html"\1 class="flex items-center justify-center gap-2 bg-white text-black font-semibold rounded-full py-3 px-6 hover:bg-white/90 transition-all shadow-lg text-center">\2\3\4</a>',
            html,
            flags=re.IGNORECASE
        )

    elif filename == "settings.html":
        # Back arrow -> user-profile.html
        html = re.sub(
            r'(<span class="material-symbols-outlined[^"]*">\s*(arrow_back|chevron_left)\s*</span>)',
            r'<a href="user-profile.html" class="text-white hover:opacity-80 transition-opacity">\1</a>',
            html
        )

    # 3. Responsive container constraints (keep viewport mobile-scaled 430px max width centered on large screens)
    if "body class=" in html and "max-w-" not in html:
        html = html.replace('<body class="', '<body class="max-w-[480px] mx-auto min-h-screen relative shadow-2xl ')

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"✓ Successfully wired navigation for {filename}")

def main():
    screens = [f for f in os.listdir(SITE_DIR) if f.endswith(".html") and f != "index.html"]
    for s in sorted(screens):
        wire_screen(s)

if __name__ == "__main__":
    main()
