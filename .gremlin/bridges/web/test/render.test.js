// render.test.js - unit tests for the pure body renderer (run by test/run.sh
// under node). Exits non-zero on any failure.
"use strict";

var R = require("../public/render.js");
var fails = 0;

function check(name, cond) {
  if (cond) {
    console.log("    ok   " + name);
  } else {
    console.log("    FAIL " + name);
    fails += 1;
  }
}

var h;

// Media embeds → cards.
h = R.renderBodyHTML("🖼️ [the chart](https://example.test/c.png)");
check("image emoji embed → <img>", /<img [^>]*src="https:\/\/example\.test\/c\.png"/.test(h));
check("image embed keeps caption", h.indexOf("the chart") !== -1);

h = R.renderBodyHTML("![alt text](https://example.test/i.png)");
check("![..](..) alias → <img>", /<img /.test(h) && h.indexOf("alt text") !== -1);

h = R.renderBodyHTML("📎 [the export](out/data.csv)");
check("file embed → download chip", h.indexOf("embed-file") !== -1 && h.indexOf("the export") !== -1);
check("local file src routed via /media", h.indexOf("/media?path=out%2Fdata.csv") !== -1);

// 🔊 (tts:) is deferred in M2 → left as literal text, not an audio element.
h = R.renderBodyHTML("🔊 [say hi](tts:)");
check("voice embed left as text in M2", h.indexOf("🔊") !== -1 && h.indexOf("<audio") === -1);

// Markdown subset.
check("bold", R.renderBodyHTML("**x**").indexOf("<strong>x</strong>") !== -1);
check("italic", R.renderBodyHTML("*x*").indexOf("<em>x</em>") !== -1);
check("inline code", R.renderBodyHTML("`x`").indexOf("<code>x</code>") !== -1);
check("fenced code", /<pre class="code"><code>line1\nline2<\/code><\/pre>/.test(
  R.renderBodyHTML("```\nline1\nline2\n```")));
check("safe link", /<a href="https:\/\/ok.test"/.test(R.renderBodyHTML("[t](https://ok.test)")));

// Security: escape + neutralize dangerous schemes.
check("html escaped", R.renderBodyHTML("<script>alert(1)</script>").indexOf("&lt;script&gt;") !== -1);
check("javascript: link NOT linkified",
  R.renderBodyHTML("[t](javascript:alert(1))").indexOf('href="javascript') === -1);
check("javascript: image refused (left as text)",
  R.renderBodyHTML("🖼️ [x](javascript:alert(1))").indexOf("<img") === -1);
check("data: image refused", R.renderBodyHTML("🖼️ [x](data:text/html,x)").indexOf("<img") === -1);

// Sentinel safety: a bare digit in prose must survive untouched.
check("bare digit survives", R.renderBodyHTML("I have 3 apples") === "I have 3 apples");

// Mixed text + embed preserves order and renders both.
h = R.renderBodyHTML("before 🖼️ [c](https://x.test/i.png) after");
check("mixed text+embed: text kept", h.indexOf("before ") !== -1 && h.indexOf(" after") !== -1);
check("mixed text+embed: image kept", h.indexOf("<img") !== -1);

// An incomplete/odd embed degrades to text, never throws.
check("non-embed text untouched", R.renderBodyHTML("just words") === "just words");

if (fails > 0) {
  console.log("    " + fails + " renderer assertion(s) failed");
  process.exit(1);
}
