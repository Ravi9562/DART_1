window.dataLayer = window.dataLayer || [];
function gtag() { dataLayer.push(arguments); }
gtag('js', new Date());
gtag('config', 'UA-26406144-13');

// Setup listening to send Google Analytics events when any element
// with a 'data-ga-click-event' attribute is clicked.
window.addEventListener('DOMContentLoaded', function () {
  function sendEvent(e) {
    gtag('event', e.currentTarget.dataset.gaClickEvent, {
      'event_category': 'click',
      'event_label': 'path:' + window.location.pathname,
      'value': 1
    });
  }
  function addListeners() {
    var elements = document.querySelectorAll('[data-ga-click-event]');
    for (var i = 0; i < elements.length; i++) {
      elements[i].addEventListener('click', sendEvent);
    }
  }
  addListeners();
});
