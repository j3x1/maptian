/**
 * Main JS file for Casper behaviours
 */

/* globals jQuery, document */
(function ($, undefined) {
    "use strict";

    var $document = $(document);

    $document.ready(function () {
        $(".postContent p").last().append("<span class='blink-cursor'>_</span>");
        // Does image comparison stuff
        $(".twentytwenty-container, .compare").twentytwenty({
          default_offset_pct: 0.5, // How much of the before image is visible when the page loads
          orientation: 'horizontal' // Orientation of the before and after images ('horizontal' or 'vertical'),
        });
        // Hack to circumvent race condition. (Yes I know it's a horrible hack)
        var adjustId = setInterval(function() {
          $(window).trigger("resize.twentytwenty");
          clearInterval(adjustId);
        }, 1500);

    });
})(jQuery);
