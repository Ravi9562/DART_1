window.dataLayer = window.dataLayer || [];
function gtag() { dataLayer.push(arguments); }
gtag('js', new Date());
gtag('config', 'UA-26406144-13');

// Setup listening to send Google Analytics events when any element
// with a 'data-ga-click-event' attribute is clicked.
window.addEventListener('DOMContentLoaded', function () {
  function sendEvent(e) {
    var elem = e.currentTarget;

    var data = {
      'event_category': 'click',
      'event_label': 'path:' + window.location.pathname,
      'value': 1
    };

    // Events on links should be sent via beacon, see:
    // https://support.google.com/analytics/answer/7478520?hl=en
    if (elem.hasAttribute('href')) {
      data.event_callback = function() { document.location = elem.href; };
      data.transport_type = 'beacon';
      e.preventDefault();
    }

    gtag('event', elem.dataset.gaClickEvent, data);
  }
  function addListeners() {
    var elements = document.querySelectorAll('[data-ga-click-event]');
    for (var i = 0; i < elements.length; i++) {
      elements[i].addEventListener('click', sendEvent);
    }
  }
  addListeners();
});
