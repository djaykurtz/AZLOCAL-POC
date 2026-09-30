/*
 * Answers of record.
 *
 * Everything typed into the commentary overlay lives in browser localStorage, which is one cleared
 * cache away from gone and invisible to git. This file is the durable copy.
 *
 * Loaded before notes.js. On start, any note with no local entry, or a local entry that is still
 * untouched, takes its status and answer from here. Anything actively edited in the browser wins,
 * so this can never overwrite newer thinking.
 *
 * To update: open the overlay, press Export, paste the result back into this file, commit.
 *
 * Last captured 2026-08-28.
 */

window.NOTE_ANSWERS = {
  "mockup": {
    "status": "resolved",
    "answer": "That's fine for now.\nBut i think right next to this, Azure Local POC Visual Console should be the label not 'Learning Console'"
  },
  "kinds-stat": {
    "status": "resolved",
    "answer": "I don't know what is meant by 'kinds'. I'm not even sure tracking connection types specifically is important. We can see in the bottom left. Maybe bottom left section should be called \"Pathways\""
  },
  "kinds-header": {
    "status": "resolved",
    "answer": "No, read number 2."
  },
  "movements": {
    "status": "resolved",
    "answer": "* as the system builds to them"
  },
  "tiers": {
    "status": "resolved",
    "answer": "I think we should include the switches in visual representation initially, and how they're connected, They'll fade into the fabric faster than the systems, probably in Movement 01.\nCan you give the switches their proper name."
  },
  "ceremony": {
    "status": "considering",
    "answer": "I need more details on what you means, we can talk about this as outstanding topics."
  },
  "teams": {
    "status": "resolved",
    "answer": "They should be larger, more spread out and take up more of the field, we can always scale it back later."
  },
  "morph": {
    "status": "change",
    "answer": "The switches need to move up first, then the servers."
  },
  "flip": {
    "status": "considering",
    "answer": "Yeah we'll figure out transitions later. We need a lot more slides and transitions. But this is more design at this point."
  },
  "resolve": {
    "status": "considering",
    "answer": "What does 'on request' mean exactly?"
  },
  "name": {
    "status": "considering",
    "answer": "We still haven't built the synthetic Console that shows the 'evidence' with expandable real world commands underneath."
  },
  "liveness": {
    "status": "considering",
    "answer": "Leaning closer to transcript, millions of lines flashing by an actual console is not great presentation material. See 11."
  },
  "collapse": {
    "status": "considering",
    "answer": "I still like the opening of the previous presentation. Lots of work still to do. You kind of lost sight of the original and I am worried that is context limitations. I like what we have here, but it is more like a re-imagined large slice of the previous presentation, neither are complete."
  },
  "live": {
    "status": "considering",
    "answer": "I'm not interested in the risk associated with live fail over... demonstrating what it would look like with actual word for word proof of actual events can be presented. But none of that is live."
  },
  "resync": {
    "status": "considering",
    "answer": "See other comments."
  },
  "deadline": {
    "status": "considering",
    "answer": "What is this database for?\nWhat do you mean deadline?\n\nI am looking to have this presentation feature complete in maybe 5 days."
  },
  "spine": {
    "status": "change",
    "answer": "Let's build off this one, v2."
  },
  "beats": {
    "status": "considering",
    "answer": "i dont see why we cannot do all of those things. We just need to think through the transitions of what gets focus."
  },
  "evidence": {
    "status": "considering",
    "answer": "i dont want to waste time integrating it until we have a mockup independent of what we already have created. So we can think through all the elements of it.\nThe width of the current visual elements can be adjusted, we'll figure out the actual spacing later on. There's space on top (shrink the 'four machines carry the cluster' fluff area) as well as the empty space below.\n\nMaybe it makes more sense side by side since consoles are more limited on width then height. Thinking about it."
  },
  "intro": {
    "status": "change",
    "answer": "I really like the work that went into that. Let's slap it in front when the system launches, And again make it a check box type thing at the start button."
  },
  "climax": {
    "status": "considering",
    "answer": "I need to see all the elements in order to properly arrange them and give them weight."
  },
  "ending": {
    "status": "considering",
    "answer": "I'd like a quick recap, followed by questions. But I think it would be great to be able to pull back the curtain a bit and show the actual creation somehow."
  },
  "runlength": {
    "status": "resolved",
    "answer": "Maybe aim for 20 minutes of content and I can have 10 minutes of questions. But it is likely open ended and if people are excited about it I could see it going on for a bit longer."
  },
  "control": {
    "status": "resolved",
    "answer": "It's always me, i move the presentation and explain things and then move to the next slide."
  },
  "delivery": {
    "status": "considering",
    "answer": "For now it is just where it is. I can see about export later."
  }
};
