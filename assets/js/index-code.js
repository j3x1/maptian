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



        // Adds captions to the images from the alt text
        var selectors = [
          ".post-content span.right",
          ".post-content span.left",
          ".post-content span.overflow",
          ".post-content span.fit",
          ".post-content span.full"
        ]
        $(selectors.join(', ')).each(
        function() {
            var $image = $(this).find('img');
            if ( $image.length == 0 ) {
              return;
            }
            $image.addClass('image');
            // Let's put a caption if there is one
            if ($image.attr("alt")) {
                $image.after(
                    '<figcaption>' +
                    $image.attr(
                        "alt") +
                    '</figcaption>'
                );
            }
        });

        // Adds anchor links to the h2 headers
        var titles = document.getElementsByTagName('h2');

        for(var i = 0; i < titles.length; i++) {
          var aid = titles[i].id.endsWith('-') ? titles[i].id.slice(0, -1) : titles[i].id;
          var atag = document.createElement('a')
          atag.id = aid
          titles[i].parentNode.insertBefore(atag, titles[i])
        }

    });
})(jQuery);
