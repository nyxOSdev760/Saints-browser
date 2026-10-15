import Foundation

/// A small gallery of ready-made userscripts/userstyles that show off the extension layer.
struct GalleryItem: Identifiable {
    let id: String
    let name: String
    let summary: String
    let symbol: String
    let kind: WebExtension.Kind
    let source: String
}

enum BuiltInExtensions {
    static let newScriptTemplate = """
    // ==UserScript==
    // @name         My Script
    // @version      1.0
    // @description  Describe what this script does
    // @match        *://*/*
    // @grant        none
    // @run-at       document-end
    // ==/UserScript==

    (function () {
      'use strict';
      // Your code here. Use @grant GM_setValue / GM_xmlhttpRequest etc. for Greasemonkey APIs.
    })();
    """

    static let newStyleTemplate = """
    /* ==UserStyle==
    @name         My Style
    @version      1.0
    @description  Restyle any site
    ==/UserStyle== */

    @-moz-document domain("example.com") {
      body { font-family: -apple-system, system-ui; }
    }
    """

    static let gallery: [GalleryItem] = [
        GalleryItem(id: "cookie-reject", name: "Cookie Pop-up Auto-Reject",
                    summary: "Clicks “Reject all” on common consent banners and restores scrolling.",
                    symbol: "hand.raised.fill", kind: .userScript, source: """
        // ==UserScript==
        // @name         Cookie Pop-up Auto-Reject
        // @version      1.0
        // @description  Rejects non-essential cookies on common consent platforms.
        // @match        *://*/*
        // @grant        none
        // @run-at       document-end
        // ==/UserScript==
        (function () {
          const selectors = [
            '#onetrust-reject-all-handler', '.ot-pc-refuse-all-handler', '#CybotCookiebotDialogBodyButtonDecline',
            '.fc-cta-do-not-consent', '[data-testid="uc-deny-all-button"]', '.didomi-continue-without-agreeing',
            '#didomi-notice-disagree-button', '.cmpboxbtnno', '.cky-btn-reject', '#truste-consent-required',
            '.osano-cm-denyAll', '[aria-label="Reject all"]', '[aria-label="Decline all"]', 'button.sp_choice_type_13',
            '#tarteaucitronAllDenied2', '.iubenda-cs-reject-btn', '#cookiescript_reject', '.js-reject-cookies'
          ];
          let tries = 0;
          const run = () => {
            for (const s of selectors) {
              const el = document.querySelector(s);
              if (el && el.offsetParent !== null) { el.click(); break; }
            }
            for (const el of [document.documentElement, document.body]) {
              if (el && getComputedStyle(el).overflow === 'hidden') el.style.setProperty('overflow', 'auto', 'important');
            }
            if (++tries < 10) setTimeout(run, 700);
          };
          run();
        })();
        """),
        GalleryItem(id: "amp-redirect", name: "Skip AMP Pages",
                    summary: "Sends you from Google AMP pages to the publisher's real page.",
                    symbol: "bolt.slash.fill", kind: .userScript, source: """
        // ==UserScript==
        // @name         Skip AMP Pages
        // @version      1.0
        // @description  Redirects AMP pages to their canonical URL.
        // @match        *://*/*
        // @grant        none
        // @run-at       document-end
        // ==/UserScript==
        (function () {
          const html = document.documentElement;
          if (!(html.hasAttribute('amp') || html.hasAttribute('⚡'))) return;
          const link = document.querySelector('link[rel="canonical"]');
          if (link && link.href && link.href !== location.href) location.replace(link.href);
        })();
        """),
        GalleryItem(id: "copy-unlock", name: "Allow Copy & Select",
                    summary: "Re-enables text selection, copy and long-press menus on sites that block them.",
                    symbol: "doc.on.clipboard.fill", kind: .userScript, source: """
        // ==UserScript==
        // @name         Allow Copy & Select
        // @version      1.0
        // @description  Stops sites from blocking selection, copy and context menus.
        // @match        *://*/*
        // @grant        none
        // @run-at       document-start
        // ==/UserScript==
        (function () {
          for (const type of ['copy', 'cut', 'contextmenu', 'selectstart', 'dragstart']) {
            document.addEventListener(type, (e) => e.stopPropagation(), true);
          }
          const style = document.createElement('style');
          style.textContent = '*{-webkit-user-select:auto!important;user-select:auto!important;-webkit-touch-callout:default!important}';
          (document.head || document.documentElement).appendChild(style);
        })();
        """),
        GalleryItem(id: "video-speed", name: "Video Speed Control",
                    summary: "Adds a speed button to every video (0.75× – 3×).",
                    symbol: "gauge.with.dots.needle.67percent", kind: .userScript, source: """
        // ==UserScript==
        // @name         Video Speed Control
        // @version      1.0
        // @description  Tap the badge on a video to change its playback speed.
        // @match        *://*/*
        // @grant        none
        // @run-at       document-end
        // ==/UserScript==
        (function () {
          const speeds = [1, 1.25, 1.5, 2, 3, 0.75];
          const attach = (v) => {
            if (v.dataset.saintsSpeed) return;
            v.dataset.saintsSpeed = '1';
            const b = document.createElement('button');
            b.textContent = '1×';
            b.style.cssText = 'position:absolute;z-index:2147483647;top:8px;left:8px;padding:4px 9px;border:0;border-radius:12px;' +
              'background:rgba(0,0,0,.6);color:#fff;font:600 13px -apple-system,system-ui;';
            b.addEventListener('click', (e) => {
              e.preventDefault(); e.stopPropagation();
              const next = speeds[(speeds.indexOf(v.playbackRate) + 1) % speeds.length] || 1;
              v.playbackRate = next; b.textContent = next + '×';
            }, true);
            const parent = v.parentElement;
            if (!parent) return;
            if (getComputedStyle(parent).position === 'static') parent.style.position = 'relative';
            parent.appendChild(b);
          };
          const scan = () => document.querySelectorAll('video').forEach(attach);
          scan();
          new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true });
        })();
        """),
        GalleryItem(id: "google-to-ddg", name: "Google → DuckDuckGo",
                    summary: "If a link sends you to a Google search, SV Browser sends it to DuckDuckGo.",
                    symbol: "arrow.uturn.right", kind: .userScript, source: """
        // ==UserScript==
        // @name         Google → DuckDuckGo
        // @version      1.0
        // @description  Redirects Google searches to DuckDuckGo.
        // @include      /^https?://(www\\.)?google\\.[a-z.]+/search.*/
        // @grant        none
        // @run-at       document-start
        // ==/UserScript==
        (function () {
          const q = new URLSearchParams(location.search).get('q');
          if (q) location.replace('https://duckduckgo.com/?q=' + encodeURIComponent(q));
        })();
        """),
        GalleryItem(id: "dark-mode", name: "Force Dark Mode",
                    summary: "Smart-inverts light websites into a dark theme. Turn off per need in Extensions.",
                    symbol: "moon.fill", kind: .userStyle, source: """
        /* ==UserStyle==
        @name         Force Dark Mode
        @version      1.0
        @description  Smart-invert every website.
        ==/UserStyle== */
        html { filter: invert(0.9) hue-rotate(180deg) !important; background: #fff !important; }
        img, video, picture, canvas, iframe, embed, object, svg image, [style*="background-image"] {
          filter: invert(1) hue-rotate(180deg) !important;
        }
        """),
        GalleryItem(id: "no-shorts", name: "Hide YouTube Shorts",
                    summary: "Removes Shorts shelves and tabs from YouTube.",
                    symbol: "play.slash.fill", kind: .userStyle, source: """
        /* ==UserStyle==
        @name         Hide YouTube Shorts
        @version      1.0
        @description  Hides Shorts on m.youtube.com and youtube.com.
        ==/UserStyle== */
        @-moz-document domain("youtube.com") {
          ytm-reel-shelf-renderer, ytm-shorts-lockup-view-model, ytd-reel-shelf-renderer,
          ytd-rich-shelf-renderer[is-shorts], [tab-identifier="FEshorts"], ytm-pivot-bar-item-renderer:has(.pivot-shorts),
          a[href^="/shorts"] { display: none !important; }
        }
        """),
        GalleryItem(id: "readable", name: "Comfortable Reading",
                    summary: "Limits line length and boosts line spacing on article pages.",
                    symbol: "text.alignleft", kind: .userStyle, source: """
        /* ==UserStyle==
        @name         Comfortable Reading
        @version      1.0
        @description  Nicer typography for long articles.
        ==/UserStyle== */
        article p, main p { line-height: 1.65 !important; font-size: 1.06em !important; }
        article, main article { max-width: 42em !important; margin-left: auto !important; margin-right: auto !important; }
        """)
    ]
}
