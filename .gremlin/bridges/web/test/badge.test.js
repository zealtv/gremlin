// badge.test.js - unit tests for the pure unread-badge core (run by test/run.sh
// under node). Exits non-zero on any failure.
"use strict";

var B = require("../public/badge.js");
var fails = 0;

function check(name, cond) {
  if (cond) {
    console.log("    ok   " + name);
  } else {
    console.log("    FAIL " + name);
    fails += 1;
  }
}

var s;

// An assistant turn while hidden, past the backfill guard window, increments.
s = B.next({ unread: 0 }, { type: "turn", role: "assistant", hidden: true, msSinceReset: 2001 });
check("assistant turn, hidden, past guard → unread+1", s.unread === 1);

s = B.next(s, { type: "turn", role: "assistant", hidden: true, msSinceReset: 5000 });
check("a second assistant turn → unread+1 again", s.unread === 2);

// User/system turns never count, regardless of visibility/timing.
s = B.next({ unread: 0 }, { type: "turn", role: "user", hidden: true, msSinceReset: 5000 });
check("user turn, hidden → unchanged", s.unread === 0);

s = B.next({ unread: 0 }, { type: "turn", role: "system", hidden: true, msSinceReset: 5000 });
check("system turn, hidden → unchanged", s.unread === 0);

// Turns while visible never count.
s = B.next({ unread: 0 }, { type: "turn", role: "assistant", hidden: false, msSinceReset: 5000 });
check("assistant turn, visible → unchanged", s.unread === 0);

// The backfill rule: turns within the reset guard window never count, even
// if hidden and assistant-authored (a reconnect replay must not fake unread).
s = B.next({ unread: 0 }, { type: "turn", role: "assistant", hidden: true, msSinceReset: 2000 });
check("assistant turn, hidden, msSinceReset == 2000 → unchanged (boundary)", s.unread === 0);

s = B.next({ unread: 0 }, { type: "turn", role: "assistant", hidden: true, msSinceReset: 500 });
check("assistant turn, hidden, within guard window → unchanged (backfill)", s.unread === 0);

// visible resets to 0.
s = B.next({ unread: 3 }, { type: "visible" });
check("visible → resets to 0", s.unread === 0);

// Anything else leaves state unchanged.
s = B.next({ unread: 2 }, { type: "something-else" });
check("unknown event type → unchanged", s.unread === 2);

// title() shape.
check("title(): 0 unread → base only", B.title("roo", 0) === "roo");
check("title(): 1 unread → (1) base", B.title("roo", 1) === "(1) roo");
check("title(): 12 unread → (12) base", B.title("roo", 12) === "(12) roo");

if (fails > 0) {
  console.log("    " + fails + " badge assertion(s) failed");
  process.exit(1);
}
