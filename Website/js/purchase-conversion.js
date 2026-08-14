/* Reports a Google Ads conversion when the Lemon Squeezy overlay completes.
 *
 * Path 1 of 2. Path 2 is /thanks (thanks.js), reached via the Lemon Squeezy
 * "redirect after purchase" setting — it still records the sale if this script
 * fails to load or the buyer closes the overlay before it fires. Both call
 * mgTrackPurchase(), which dedupes, so a purchase is only ever counted once.
 *
 * External file, not inline: the site CSP has no 'unsafe-inline' (see _headers).
 *
 * Verified against the real shipped assets.lemonsqueezy.com/lemon.js:
 *   - it forwards EVERY postMessage from the checkout iframe to our handler,
 *     so `event` is the raw payload and we must match on event.event;
 *   - Setup() REPLACES any previous eventHandler, so this must be the only
 *     caller on the page;
 *   - window.LemonSqueezy only exists after lemon.js's own 'load' listener has
 *     run, hence the load-time wiring below;
 *   - lemon.js ALREADY calls gtag('event','purchase') itself on a GA.Purchase
 *     message. That is a GA4-shaped event with no send_to, so it does NOT
 *     register a Google Ads conversion — this file is still required.
 */
(function () {
  function wire() {
    if (!window.LemonSqueezy || typeof window.LemonSqueezy.Setup !== 'function') return;
    window.LemonSqueezy.Setup({
      eventHandler: function (event) {
        if (!event || event.event !== 'Checkout.Success') return;
        var order = event.data || {};
        mgTrackPurchase({
          source: 'overlay',
          transaction_id: order.id ||
            (order.attributes && order.attributes.order_number) || '',
          value: mgOrderTotal(order)
        });
      }
    });
  }

  // lemon.js wires createLemonSqueezy on window 'load'; run just after it. If
  // this script is evaluated post-load (defer/cache), fire immediately instead.
  if (document.readyState === 'complete') setTimeout(wire, 0);
  else window.addEventListener('load', function () { setTimeout(wire, 0); });
})();
