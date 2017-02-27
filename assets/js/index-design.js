/**
 * Main JS file for Casper behaviours
 */

/* globals jQuery, document */
(function ($, undefined) {
    "use strict";

    var $document = $(document);

    $document.ready(function () {

        var $postContent = $(".post-content");
        $postContent.fitVids();

        $(".scroll-down").arctic_scroll();

        $(".menu-button, .nav-cover, .nav-close").on("click", function(e){
            e.preventDefault();
            $("body").toggleClass("nav-opened nav-closed");
        });

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

        // Adds full class to p tags containing full images
        $(".post-content p span.full").each(
          function() {
            $(this).parent().addClass('full');
          }
        );

        $(".post-content p span.fit").each(
          function() {
            $(this).parent().addClass('fit');
          }
        );

        $(".post-content p span.overflow").each(
          function() {
            $(this).parent().addClass('overflow');
          }
        );

        $(".post-content p").each(
          function() {
            if ($(this).text() == "") {
              console.log("Empty paragraph");
              $(this).remove();
            }
          }
        );


        $(".post-content p").last().append("<span class='end-of-transmission'>♦</span>");

        var readingTime = 0;
        var WPM = 200;
        var $content = $("section.post-content");
        if ( $content.length > 0 ) {
          var readingTime = Math.ceil($content.text().trim().split(/\s+/).length / WPM);
        }
        // Adds the author content where the tag is
        var authorDom = '<div class="author-container">';
        authorDom += '<hr class="hline">';
        authorDom += '<img src="/assets/jj-line.png" />';
        authorDom += '<div class="name-container">by <span class="name">Low Jia Jin</span></div>';
        authorDom += '<div class="time">a <span class="minutes">' + readingTime + '</span> min read</div>';
        authorDom += '<div class="vline"></div>';
        authorDom += '</div>';
        $(".post-content author").each(
          function() {
            $(this).append(authorDom);
          }
        );

        // Does image comparison stuff
        $(".twentytwenty-container, .compare").twentytwenty({
          default_offset_pct: 0.5, // How much of the before image is visible when the page loads
          orientation: 'horizontal' // Orientation of the before and after images ('horizontal' or 'vertical')
        });
        // Hack to circumvent race condition. (Yes I know it's a horrible hack)
        var adjustId = setInterval(function() {
          $(window).trigger("resize.twentytwenty");
          clearInterval(adjustId);
        }, 1500);

    });

    // Arctic Scroll by Paul Adam Davis
    // https://github.com/PaulAdamDavis/Arctic-Scroll
    $.fn.arctic_scroll = function (options) {

        var defaults = {
            elem: $(this),
            speed: 500
        },

        allOptions = $.extend(defaults, options);

        allOptions.elem.click(function (event) {
            event.preventDefault();
            var $this = $(this),
                $htmlBody = $('html, body'),
                offset = ($this.attr('data-offset')) ? $this.attr('data-offset') : false,
                position = ($this.attr('data-position')) ? $this.attr('data-position') : false,
                toMove;

            if (offset) {
                toMove = parseInt(offset);
                $htmlBody.stop(true, false).animate({scrollTop: ($(this.hash).offset().top + toMove) }, allOptions.speed);
            } else if (position) {
                toMove = parseInt(position);
                $htmlBody.stop(true, false).animate({scrollTop: toMove }, allOptions.speed);
            } else {
                $htmlBody.stop(true, false).animate({scrollTop: ($(this.hash).offset().top) }, allOptions.speed);
            }
        });

    };
})(jQuery);
