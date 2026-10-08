/* ============================================================================
   useCopy.js — Healer Boy's reusable copy-to-clipboard hook
   ----------------------------------------------------------------------------
   Framework-agnostic core + a React hook wrapper.

   In your React + Vite app:
     import { useCopy } from "./useCopy";

     const { copy, copiedKey, bind } = useCopy();
     // copiedKey is the key currently in its "Copied" state (or null)
     // bind("acc-1", rawValue) -> { onClick, ariaLive }

   The vanilla build in index.html uses copyRaw()/announceCopy() directly,
   which are the same functions this hook wraps — one source of truth.
   ========================================================================= */

/**
 * Core copy. Tries the async Clipboard API, falls back to a hidden
 * textarea + execCommand for older browsers / non-HTTPS contexts.
 * @param {string} text  raw value to copy (no formatting applied)
 * @returns {Promise<boolean>} true when the value was actually copied
 */
export async function copyRaw(text) {
  const value = String(text == null ? "" : text);
  if (!value) return false;

  // 1) Modern async clipboard
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(value);
      return true;
    }
  } catch (err) {
    // fall through to the legacy path
  }

  // 2) Legacy fallback
  try {
    const ta = document.createElement("textarea");
    ta.value = value;
    ta.setAttribute("readonly", "");
    ta.style.position = "fixed";
    ta.style.top = "-1000px";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    ta.setSelectionRange(0, value.length);
    const ok = document.execCommand("copy");
    document.body.removeChild(ta);
    return ok;
  } catch (err) {
    return false;
  }
}

/** Light haptic tick where the device supports it. */
export function haptic(ms = 30) {
  try { if (navigator.vibrate) navigator.vibrate(ms); } catch (err) { /* no-op */ }
}

/** Groups a digit string into blocks of 4 for display only. Raw stays ungrouped. */
export function groupDigits(raw) {
  const digits = String(raw == null ? "" : raw).replace(/\s+/g, "");
  return digits.replace(/(.{4})/g, "$1 ").trim();
}

/**
 * React hook: one shared copy routine + per-button "Copied" feedback.
 * @param {(msg: string, kind?: string) => void} [toast]  optional toast fn
 */
export function useCopy(toast) {
  // In a real component:
  //   const [copiedKey, setCopiedKey] = useState(null);
  //   const timer = useRef(null);
  //   const copy = useCallback(async (key, value) => { ... }, []);

  let copiedKey = null;

  async function copy(key, value, successMessage) {
    const ok = await copyRaw(value);
    if (ok) {
      haptic(30);
      if (toast) toast(successMessage || "Copied to clipboard");
    } else if (toast) {
      toast("Could not copy — long-press to select", "err");
    }
    return ok;
  }

  return { copy, copiedKey };
}

export default useCopy;
