! function(e) {
    "use strict";
    e.fn.fitVids = function(t) {
        var i = {
            customSelector: null
        };
        if (!document.getElementById("fit-vids-style")) {
            var n = document.head || document.getElementsByTagName("head")[0],
                r = ".fluid-width-video-wrapper{width:100%;position:relative;padding:0;}.fluid-width-video-wrapper iframe,.fluid-width-video-wrapper object,.fluid-width-video-wrapper embed {position:absolute;top:0;left:0;width:100%;height:100%;}",
                a = document.createElement("div");
            a.innerHTML = '<p>x</p><style id="fit-vids-style">' + r + "</style>", n.appendChild(a.childNodes[1])
        }
        return t && e.extend(i, t), this.each(function() {
            var t = ["iframe[src*='player.vimeo.com']", "iframe[src*='youtube.com']", "iframe[src*='youtube-nocookie.com']", "iframe[src*='kickstarter.com'][src*='video.html']", "object", "embed"];
            i.customSelector && t.push(i.customSelector);
            var n = e(this).find(t.join(","));
            n = n.not("object object"), n.each(function() {
                var t = e(this);
                if (!("embed" === this.tagName.toLowerCase() && t.parent("object").length || t.parent(".fluid-width-video-wrapper").length)) {
                    var i = "object" === this.tagName.toLowerCase() || t.attr("height") && !isNaN(parseInt(t.attr("height"), 10)) ? parseInt(t.attr("height"), 10) : t.height(),
                        n = isNaN(parseInt(t.attr("width"), 10)) ? t.width() : parseInt(t.attr("width"), 10),
                        r = i / n;
                    if (!t.attr("id")) {
                        var a = "fitvid" + Math.floor(999999 * Math.random());
                        t.attr("id", a)
                    }
                    t.wrap('<div class="fluid-width-video-wrapper"></div>').parent(".fluid-width-video-wrapper").css("padding-top", 100 * r + "%"), t.removeAttr("height").removeAttr("width")
                }
            })
        })
    }
}(window.jQuery || window.Zepto),
function(e) {
    e.fn.readingTime = function(t) {
        var i = {
                readingTimeTarget: ".eta",
                wordCountTarget: null,
                wordsPerMinute: 260,
                secondsPerImage: 20,
                round: !0,
                lang: "en",
                lessThanAMinuteString: "",
                prependTimeString: "",
                prependWordString: "",
                remotePath: null,
                remoteTarget: null,
                success: function() {},
                error: function() {}
            },
            n = this,
            r = e(this);
        n.settings = e.extend({}, i, t);
        var a = n.settings;
        if (!this.length) return a.error.call(this), this;
        if ("it" == a.lang) var o = a.lessThanAMinuteString || "Meno di un minuto",
            s = "min";
        else if ("fr" == a.lang) var o = a.lessThanAMinuteString || "Moins d'une minute",
            s = "min";
        else if ("de" == a.lang) var o = a.lessThanAMinuteString || "Weniger als eine Minute",
            s = "min";
        else if ("es" == a.lang) var o = a.lessThanAMinuteString || "Menos de un minuto",
            s = "min";
        else if ("nl" == a.lang) var o = a.lessThanAMinuteString || "Minder dan een minuut",
            s = "min";
        else if ("sk" == a.lang) var o = a.lessThanAMinuteString || "Menej než minútu",
            s = "min";
        else if ("cz" == a.lang) var o = a.lessThanAMinuteString || "Méně než minutu",
            s = "min";
        else if ("hu" == a.lang) var o = a.lessThanAMinuteString || "Kevesebb mint egy perc",
            s = "perc";
        else var o = a.lessThanAMinuteString || "Less than a minute",
            s = "min";
        var d = function(t, img) {
            if ("" !== t) {
                var i = t.trim().split(/\s+/g).length,
                    n = a.wordsPerMinute / 60,
                    r = i / n;
                r += img * a.secondsPerImage;
                if (a.round === !0) var d = Math.round(r / 60);
                else var d = Math.floor(r / 60);
                var l = Math.round(r - 60 * d);
                if (a.round === !0) d > 0 ? e(a.readingTimeTarget).text(a.prependTimeString + d + " " + s) : e(a.readingTimeTarget).text(a.prependTimeString + o);
                else {
                    var u = d + ":" + l;
                    e(a.readingTimeTarget).text(a.prependTimeString + u)
                }
                "" !== a.wordCountTarget && void 0 !== a.wordCountTarget && e(a.wordCountTarget).text(a.prependWordString + i), a.success.call(this)
            } else a.error.call(this, "The element is empty.")
        };
        r.each(function() {
            null != a.remotePath && null != a.remoteTarget ? e.get(a.remotePath, function(t) {
                var g = e("<div>").html(t).find(a.remoteTarget);
                d(g.text(), g.find("img").length)
            }) : d(r.text(), r.find("img").length)
        })
    }
}(jQuery), $(document).ready(function() {
    
});
var $latest = $("#posts");
"/" !== location.pathname && $latest.load("/ #posts li"),
    function(e, t) {
        "use strict";
        var i = e(document);
        i.ready(function() {
            var t = e(".post-content");
            t.fitVids(), e(".scroll-down").arctic_scroll(), e(".menu-button, .nav-cover, .nav-close").on("click", function(t) {
                t.preventDefault(), e("body").toggleClass("nav-opened nav-closed")
            })
        }), e.fn.arctic_scroll = function(t) {
            var i = {
                    elem: e(this),
                    speed: 500
                },
                n = e.extend(i, t);
            n.elem.click(function(t) {
                t.preventDefault();
                var i, r = e(this),
                    a = e("html, body"),
                    o = r.attr("data-offset") ? r.attr("data-offset") : !1,
                    s = r.attr("data-position") ? r.attr("data-position") : !1;
                o ? (i = parseInt(o), a.stop(!0, !1).animate({
                    scrollTop: e(this.hash).offset().top + i
                }, n.speed)) : s ? (i = parseInt(s), a.stop(!0, !1).animate({
                    scrollTop: i
                }, n.speed)) : a.stop(!0, !1).animate({
                    scrollTop: e(this.hash).offset().top
                }, n.speed)
            })
        }
    }(jQuery), $(window).scroll(function() {
        var e = 100 * $(window).scrollTop() / ($(document).height() - $(window).height());
        $(".progressbar").css("width", e + "%")
    }), $("article").readingTime();