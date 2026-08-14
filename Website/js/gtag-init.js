/* Google tag (gtag.js) — Google Ads AW-18386624012.
 *
 * This is Google's own inline snippet, moved into an external file ON PURPOSE.
 * The site's CSP is `script-src 'self'` with NO 'unsafe-inline' (see _headers),
 * so Google's copy-paste inline <script> block is silently blocked by the
 * browser. Serving the identical code from our own origin keeps the strict
 * policy intact instead of punching an 'unsafe-inline' hole through it for
 * every script on every page.
 *
 * Loading gtag.js itself still requires googletagmanager.com in script-src,
 * plus img-src/connect-src/frame-src allowances for the measurement beacons —
 * all scoped in _headers.
 */
window.dataLayer = window.dataLayer || [];
function gtag() { dataLayer.push(arguments); }
gtag('js', new Date());

gtag('config', 'AW-18386624012');

/* ---------------------------------------------------------------------------
 * Purchase conversion reporting.
 *
 * >>> PASTE THE CONVERSION LABEL BELOW <<<
 * Google Ads ▸ Goals ▸ Conversions ▸ (your purchase action) ▸ Tag setup ▸
 * "Use Google tag". It shows send_to: 'AW-18386624012/AbC-D_efGhI'. Copy ONLY
 * the part after the slash. Until it is filled in, no conversion is reported —
 * a wrong label silently reports nothing, so this fails loudly instead.
 */
var MG_ADS_ID = 'AW-18386624012';
var MG_CONVERSION_LABEL = '';   // e.g. 'AbC-D_efGhI'

var MG_LIST_PRICE = 9.99;       // fallback only; real total preferred
var MG_CURRENCY = 'USD';

/* Both the checkout overlay and the /thanks redirect can fire for one purchase,
 * so dedupe. Google Ads dedupes server-side on transaction_id, but only when we
 * know the order id — sessionStorage covers the case where we don't. It is
 * per-origin, so it survives the /purchase -> /thanks navigation. */
function mgAlreadyCounted(key) {
  try {
    if (!window.sessionStorage) return false;
    if (sessionStorage.getItem(key)) return true;
    sessionStorage.setItem(key, '1');
  } catch (e) { /* Safari private mode: fall through, Ads still dedupes on id */ }
  return false;
}

/* Lemon Squeezy money fields are integer cents. Read defensively: an unexpected
 * shape must degrade to list price, never report 0 or NaN to Google. */
function mgOrderTotal(order) {
  try {
    var a = order && order.attributes;
    var cents = a && (a.total_usd != null ? a.total_usd : a.total);
    if (typeof cents === 'number' && isFinite(cents) && cents > 0) return cents / 100;
  } catch (e) { /* ignore */ }
  return MG_LIST_PRICE;
}

/* Returns true if a conversion was actually sent. */
function mgTrackPurchase(opts) {
  opts = opts || {};
  var id = opts.transaction_id ? String(opts.transaction_id) : '';

  if (!MG_CONVERSION_LABEL) {
    console.warn('[MouseGestures] Purchase detected but MG_CONVERSION_LABEL is ' +
                 'empty in js/gtag-init.js — no conversion reported to Google Ads.',
                 { source: opts.source, transaction_id: id || '(unknown)' });
    return false;
  }
  if (mgAlreadyCounted('mg_conv_' + (id || 'session'))) return false;

  var payload = {
    send_to: MG_ADS_ID + '/' + MG_CONVERSION_LABEL,
    value: typeof opts.value === 'number' ? opts.value : MG_LIST_PRICE,
    currency: opts.currency || MG_CURRENCY
  };
  if (id) payload.transaction_id = id;   // lets Ads dedupe across both paths
  gtag('event', 'conversion', payload);
  return true;
}
