# Bottom Navigation Smooth Switching Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the bottom navigation tab switching into a buttery-smooth, 60fps/120fps fluid animation by eliminating DOM destruction on route changes, fixing gradient rendering glitches, stabilizing flexbox reflow physics, and polishing micro-interactions (icon spring, label reveal, active glow).

**Architecture:** 
1. **Persistent DOM Lifecycle in `index.html`:** Refactor `renderNav()` to mount the 5 tab buttons once on first load and reuse them across route transitions, updating only `.on`, ARIA states, and badge dots instead of wiping `nav.innerHTML` on every click.
2. **GPU-Accelerated Capsule Layer in `bottom-nav.css`:** Decouple the purple gradient and box-shadow from the button base into an accelerated pseudo-element (`.tab::before`) transitioning via `opacity` and `transform: scale()`, bypassing browser gradient interpolation limits.
3. **Harmonized Reflow & Symmetrical Easing:** Rebalance `flex-grow`, `max-width`, and icon transforms using coordinated, non-overshooting spring/bezier curves (`cubic-bezier(0.2, 0.8, 0.2, 1)`) so sibling tabs do not oscillate or stutter during expansion and collapse.
4. **Haptic & Kinetic Micro-Delights:** Introduce subtle icon scale pop (`scale(1.08)` settling to `scale(1)`), smooth text clip-fade without letter-wrap jitter, and maintain strict reduced-motion accessibility.

**Tech Stack:** Vanilla JavaScript (ES6+), Modern CSS3 (CSS Variables, Flexbox, Hardware-accelerated transforms, pseudo-elements), HTML5.

## Global Constraints
- Preserve the exact visual aesthetic shown in the user screenshot: rounded glass dock, inactive icons in slate-purple, active tab as an indigo/purple gradient capsule with white text and icon, and pink notification dot on Donation.
- Zero external CSS/JS framework dependencies added.
- Must work reliably across mobile (iOS Safari, Android Chrome) and desktop browsers (Edge, Chrome, Safari, Firefox).
- Full keyboard accessibility (`aria-current`, `focus-visible`, `aria-label`) and `prefers-reduced-motion` compliance.

---

### Task 1: Refactor `renderNav()` to Eliminate DOM Re-creation

**Files:**
- Modify: `index.html:3492-3520`

**Interfaces:**
- Consumes: `NAV` array, `path()`, `navIndexFor(p)`, `state.donations`, `requireAuth()`, `navigate()`
- Produces: Persistent `#nav` DOM where tab elements are instantiated once and smoothly toggled via class and attribute mutations without clearing `nav.innerHTML`.

- [ ] **Step 1: Inspect current DOM-destruction behavior**

Verify lines 3499-3519 in `index.html` where `nav.innerHTML = NAV.map(...)` destroys and re-appends DOM nodes on every hash/route change.

- [ ] **Step 2: Implement persistent DOM update logic in `renderNav()`**

Replace `renderNav()` in `index.html` with a lifecycle that:
1. Checks if `#nav` has already been built (`nav.dataset.built === "true"`).
2. If not built, builds the 5 tabs once, attaches the event listeners, and sets `nav.dataset.built = "true"`.
3. If already built, selectively toggles `.on` and `aria-current="page"` on the matching tab, removes them from non-matching tabs, and updates the dynamic donation badge dot without destroying nodes.

```javascript
    function renderNav() {
      const nav = document.getElementById("nav");
      if (!nav) return;
      const p = path();
      const activeIdx = navIndexFor(p);
      const show = NAV_PATHS.includes(p) || p.startsWith("/member/") || p === "/dues" || p === "/reminders" || p === "/report";
      const shouldShow = show && requireAuth();
      nav.classList.toggle("show", shouldShow);

      if (!shouldShow) {
        nav.innerHTML = "";
        nav.dataset.built = "";
        return;
      }

      // Check whether donations notice dot should be shown
      const showDonationDot = state.donations.some(d => {
        const date = String(d.date || d.created_at || "").slice(0, 10);
        const age = date ? Date.now() - new Date(`${date}T00:00:00`).getTime() : Infinity;
        return age >= 0 && age < 30 * 24 * 60 * 60 * 1000;
      });

      // First-time build: create elements once
      if (nav.dataset.built !== "true" || nav.children.length !== NAV.length) {
        nav.innerHTML = NAV.map((n, i) => {
          const isActive = (i === activeIdx);
          const aria = n.path === "/profile" ? "Profile and settings" : n.path === "/donations" ? "Donation, new campaign" : n.label;
          return `<button class="tab${isActive ? " on" : ""}" data-nav="${n.path}" data-idx="${i}" aria-label="${aria}"${isActive ? ' aria-current="page"' : ""}>${navButtonHTML(n, isActive)}</button>`;
        }).join("");

        nav.querySelectorAll("[data-nav]").forEach(b => {
          b.onclick = (e) => {
            e.preventDefault();
            const targetPath = b.dataset.nav;
            if (path() === targetPath) return;

            // Optimistically update classes immediately for instant gesture feedback
            nav.querySelectorAll(".tab").forEach(tab => {
              tab.classList.remove("on");
              tab.removeAttribute("aria-current");
            });
            b.classList.add("on");
            b.setAttribute("aria-current", "page");

            navigate(targetPath);
          };
        });

        nav.dataset.built = "true";
        return;
      }

      // Subsequent route changes: smoothly update existing tabs without re-rendering HTML
      const tabs = nav.querySelectorAll(".tab");
      tabs.forEach((tab, i) => {
        const isActive = (i === activeIdx);
        if (isActive) {
          if (!tab.classList.contains("on")) tab.classList.add("on");
          tab.setAttribute("aria-current", "page");
        } else {
          if (tab.classList.contains("on")) tab.classList.remove("on");
          tab.removeAttribute("aria-current");
        }

        // Update notice dot for donation tab without re-rendering whole button
        if (NAV[i].path === "/donations") {
          let dot = tab.querySelector(".dot");
          if (showDonationDot && !isActive) {
            if (!dot) {
              dot = document.createElement("i");
              dot.className = "dot";
              dot.setAttribute("aria-hidden", "true");
              tab.appendChild(dot);
            }
          } else if (dot) {
            dot.remove();
          }
        }
      });
    }
```

- [ ] **Step 3: Test and verify route switching in browser**

Verify in browser console that switching between `/home`, `/pay`, `/members`, `/donations`, and `/profile`:
1. Does NOT clear `#nav.innerHTML`.
2. Seamlessly toggles the `.on` class on the active button without aborting CSS transitions.

---

### Task 2: Re-architect Capsule Background into GPU-Accelerated Pseudo-Element

**Files:**
- Modify: `bottom-nav.css:16-52`

**Interfaces:**
- Consumes: `.tab`, `.tab.on`, `.lbl`, `svg`, `.dot`
- Produces: High-performance composited animations for the active pill background, preventing gradient snapping and GPU repaints.

- [ ] **Step 1: Understand current rendering bottleneck**

In `bottom-nav.css`:
- `.tab.on` sets `background: linear-gradient(135deg,#5b3df5,#7c5cff); box-shadow: ...`
- Since gradients cannot be animated smoothly by `transition: background`, the browser triggers an instantaneous repaint when `.on` is toggled.

- [ ] **Step 2: Add hardware-accelerated `.tab::before` capsule in `bottom-nav.css`**

Add an absolute pseudo-element `.tab::before` that holds the gradient, rounded border, and drop shadow. Transition it with `opacity` and `transform: scale()`:

```css
.tab{
  appearance:none; border:0; background:transparent; cursor:pointer; padding:0 8px;
  position:relative; flex:1 1 0; min-width:0; height:50px;
  display:flex; flex-direction:row; align-items:center; justify-content:center;
  border-radius:24px; color:#6f6892; font:inherit;
  /* Symmetrical, butter-smooth layout transition */
  transition: flex-grow 0.38s cubic-bezier(0.25, 1, 0.5, 1),
              color 0.25s ease;
  -webkit-tap-highlight-color:transparent; touch-action:manipulation;
  isolation: isolate;
  will-change: flex-grow;
}

/* Independent GPU-accelerated pill capsule layer */
.tab::before{
  content:"";
  position:absolute;
  inset:0;
  border-radius:24px;
  background:linear-gradient(135deg, #5b3df5, #7c5cff);
  box-shadow:0 8px 18px -6px rgba(91,61,245,.65), inset 0 1px 0 rgba(255,255,255,.3);
  opacity:0;
  transform:scale(0.88);
  transition:opacity 0.28s cubic-bezier(0.25, 1, 0.5, 1),
             transform 0.35s cubic-bezier(0.34, 1.3, 0.64, 1);
  pointer-events:none;
  z-index:-1;
}

.tab.on::before{
  opacity:1;
  transform:scale(1);
}
```

- [ ] **Step 3: Test pill appearance and opacity fade**

Verify that on activating a tab, the purple capsule scales up smoothly from 0.88 to 1.0 with an organic spring feel while fading in, and smoothly contracts and fades away when deactivated.

---

### Task 3: Smooth Symmetrical Flex-Grow & Label Clip-Path Expansion

**Files:**
- Modify: `bottom-nav.css:24-45`

**Interfaces:**
- Consumes: `.tab`, `.tab svg`, `.tab .lbl`, `.tab.on`
- Produces: Symmetrical width expansion between active and inactive tabs without bouncing sibling icons.

- [ ] **Step 1: Harmonize flex ratios and curves**

Update the flex-grow and label styling in `bottom-nav.css`:
- Inactive: `flex: 1 1 0`
- Active: `flex-grow: 2.1`
- Transition timing: Use matching `cubic-bezier(0.25, 1, 0.5, 1)` on both `flex-grow` and `.lbl` expansion so the dock layout reflows synchronously.

```css
.tab svg{
  width:23px; height:23px; flex-shrink:0; overflow:visible;
  stroke:currentColor; fill:none; stroke-width:1.8;
  stroke-linecap:round; stroke-linejoin:round;
  transition:transform 0.35s cubic-bezier(0.34, 1.3, 0.64, 1),
             fill 0.25s ease,
             stroke 0.25s ease;
  z-index:1;
}

.tab .lbl{
  display:inline-block;
  max-width:0;
  opacity:0;
  overflow:hidden;
  white-space:nowrap;
  font-size:13.5px;
  font-weight:700;
  letter-spacing:-0.005em;
  line-height:1;
  margin-left:0;
  transform:translateX(-6px);
  transition:max-width 0.38s cubic-bezier(0.25, 1, 0.5, 1),
             opacity 0.25s cubic-bezier(0.25, 1, 0.5, 1),
             margin-left 0.38s cubic-bezier(0.25, 1, 0.5, 1),
             transform 0.35s cubic-bezier(0.25, 1, 0.5, 1);
  z-index:1;
  pointer-events:none;
}

.tab:active svg{
  transform:scale(0.88);
}

.tab:hover:not(.on){
  color:#5b3df5;
}

.tab:focus-visible{
  outline:2.5px solid #7c5cff;
  outline-offset:2px;
}

.tab.on{
  flex-grow:2.1;
  color:#ffffff;
}

.tab.on .lbl{
  max-width:85px;
  opacity:1;
  margin-left:7px;
  transform:translateX(0);
}

.tab.on svg{
  fill:rgba(255,255,255,0.2);
  transform:scale(1.04);
}
```

- [ ] **Step 2: Smooth Notification Dot Transition**

Update `.dot` in `bottom-nav.css` so that it smoothly scales down when its tab becomes active instead of disappearing abruptly:

```css
.dot{
  position:absolute; top:9px; right:calc(50% - 17px);
  width:8px; height:8px; border-radius:50%;
  background:#ff5d8f; border:2px solid #fbf9ff;
  transition:transform 0.25s cubic-bezier(0.34, 1.4, 0.64, 1), opacity 0.2s ease;
  z-index:2;
}

.tab.on .dot{
  transform:scale(0);
  opacity:0;
  pointer-events:none;
}
```

- [ ] **Step 3: Verification in browser**

Click between tabs repeatedly:
1. Verify no tab icons bounce sideways or jitter.
2. Verify text slides in gently with `transform: translateX` and `opacity`.
3. Verify the notification dot scales down smoothly when Donation is opened, and reappears when switching away.

---

### Task 4: Optional Premium Glider (Sliding Background Pill) Evaluation & Verification

**Files:**
- Test & Benchmark: Compare the optimized Elastic Capsule (Task 1-3) vs. a Continuous Sliding Glider Track.

- [ ] **Step 1: Verify 60fps frame rate and visual polish in Chrome DevTools**
Run Chrome DevTools Performance recording or visual inspection while toggling through all 5 tabs.
Confirm 0 dropped frames, no layout thrashing, and zero DOM rebuilds in the Elements panel.

- [ ] **Step 2: Test Reduced Motion (`prefers-reduced-motion`)**
Verify in `bottom-nav.css`:
```css
@media (prefers-reduced-motion: reduce) {
  .tab, .tab::before, .tab svg, .tab .lbl, .dot {
    transition: none !important;
  }
}
```
Ensure instantaneous and accessible switching when reduced motion is preferred by the user.

- [ ] **Step 3: Commit and summarize**
Commit changes with a clear message:
`git commit -m "feat(nav): smooth 60fps bottom navigation tab switching animation"`
