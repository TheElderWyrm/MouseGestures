/* Reports a Google Ads conversion on the post-purchase thank-you page.
 *
 * Path 2 of 2 (path 1 is the overlay handler in purchase-conversion.js). This
 * one is the reliable leg: it fires on a plain page load, so it survives the
 * overlay script failing, being blocked, or the buyer closing the modal.
 * mgTrackPurchase() dedupes across both, and passes transaction_id when known
 * so Google Ads can dedupe server-side too.
 *
 * Lemon Squeezy's redirect does not document a fixed set of query parameters,
 * so read several plausible names and degrade gracefully: with no id we fall
 * back to the sessionStorage guard rather than risk double-counting.
 */
(function () {
  var q = new URLSearchParams(window.location.search);
  var id = q.get('order_id') || q.get('order') || q.get('order_number') ||
           q.get('checkout_id') || '';

  var value;
  var total = q.get('total') || q.get('amount');
  if (total && isFinite(parseFloat(total))) value = parseFloat(total) / 100;

  mgTrackPurchase({
    source: 'thanks-page',
    transaction_id: id,
    value: value,
    currency: q.get('currency') || undefined
  });

  // Surface the order reference if Lemon Squeezy passed one along.
  if (id) {
    var el = document.getElementById('orderRef');
    if (el) {
      el.textContent = 'Order reference: ' + id;
      el.hidden = false;
    }
  }
})();
