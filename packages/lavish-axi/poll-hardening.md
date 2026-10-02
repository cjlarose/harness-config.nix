## Poll feedback safety

These rules are load-bearing: ignoring them silently destroys the user's
feedback. They override any shorter claim earlier in this skill that a killed
poll can always be re-run without loss — that holds only for a kill while the
poll is *waiting*, never for one landing mid-delivery or for a filtered poll.

**Core rule: never put a line-dropping filter after `lavish-axi poll`.** The
user's annotations are delivered *exactly once*. `poll` empties the session's
`prompts` as it hands them over, and what remains afterward is the freeform chat
only — never the annotations. There is no second copy to fall back on: the
session is left holding `prompts: []`, and polling again cannot recover what was
already handed off — with nothing queued, the next poll blocks waiting for the
*next* batch, it never replays what you lost. So an annotation your command
filtered away is **destroyed**, and the only remedy left is making the user type
it again. The payload is small and dense — often one line per annotation — so a
filter does not trim noise off something verbose, it deletes notes outright.
Never put `tail`, `head`, `grep`, `sed`, `awk`, or any other line-dropping
filter after `lavish-axi poll`. Read every byte it gives you.

**Keep a durable copy — `tee`, never a filter.**

```
lavish-axi poll <html-file> --agent-reply "<what to review>" \
  | tee ".lavish/feedback-$(date +%s).txt"
```

`tee` discards nothing: it keeps the feedback in front of you *and* leaves the
whole of it on disk, so if your own view was capped somewhere you can still
recover it. Give every poll its own filename — this is a loop, and a fixed name
is emptied the moment the next poll opens it, taking the previous round's copy
with it. If a payload is too big to take in at once, narrow the *saved file*,
never the live stream.

**Background polling.** A background poll is allowed only through a harness-native
tracked background-job facility whose completion result is guaranteed to resume
or notify the same agent — and the no-filter rule applies there exactly as in the
foreground: read the job's full completion output whole (`cat`), never through a
filter. Never use `nohup`, shell `&`, `disown`, or a detached process without a
verified wake callback merely to keep polling alive.

**Account for every annotation before you act.** The returned payload names its
own length: `prompts[N]` means N annotations arrived. Enumerate them by `prompt`
text (always populated), adding the `selector`/`tag`/`text` anchor where present,
one row per item in arrival order — never merge two that read alike (three
"typo" notes against three lines are three notes, not one). Count what you have
against N before editing anything; if they disagree you are looking at a
truncated view, and the rest is in the saved file. Then echo the list back in
your next `--agent-reply`, because a batch destroyed in delivery never reaches
you to be counted — only the user knows it existed. Do not try to infer
completeness from `uid`; it numbers DOM elements, is minted for elements merely
inspected, and restarts from 1 on each regeneration, so gaps in it mean nothing.

**If a batch was lost in delivery** — the user says in the chat panel that they
already sent something you never received — believe them and ask them to resend,
rather than assuming you merely have not waited long enough. A kill or timeout
*while the poll is waiting* loses nothing; a kill or filter landing *during
delivery* is the case that loses the batch.
