/// The field guide.
///
/// Written for the person holding the gateway, and grounded only in what this
/// product actually does: the app's own labels, the firmware's own behaviour,
/// the time zone rule. Explanations of battery physics are kept to what is
/// observable in the readings the gateway reports, because a confident sentence
/// about chemistry is exactly the kind of claim nobody can check from here.
///
/// No em dashes: this is user-facing copy, and the copy guard enforces the same
/// rule on the built output.
class GuideSection {
  const GuideSection(this.heading, this.paragraphs);

  final String heading;
  final List<String> paragraphs;
}

class GuideArticle {
  const GuideArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.sections,
  });

  final String id;
  final String title;
  final String summary;
  final List<GuideSection> sections;
}

const guideArticles = <GuideArticle>[
  GuideArticle(
    id: 'one-cell-first',
    title: 'Why one cell reaches the cutoff first',
    summary: 'A series pack stops when its weakest cell does, not when its average does.',
    sections: [
      GuideSection('Every cell carries the same current', [
        'In a series pack the same current flows through every cell, so the pack cannot discharge past the point where its weakest cell hits the low cutoff, and it cannot charge past the point where its strongest cell hits the high one.',
        'That is why the pack total can look healthy while one cell is doing the limiting. The Cells screen names the weakest and the strongest cell for that reason.',
      ]),
      GuideSection('What to check', [
        'If the same cell is the outlier every time, look at its sense lead and terminal torque first. A loose connection reads as a voltage error under load and looks like a bad cell.',
        'If the cells move around between charges, the pack is behaving normally and the spread is a balance question rather than a fault.',
      ]),
      GuideSection('What not to do', [
        'Do not raise the cutoff to get more capacity out of the pack. The cutoff is protecting the cell that is already the limit; moving it moves the risk, not the limit.',
      ]),
    ],
  ),
  GuideArticle(
    id: 'cell-spread',
    title: 'What the cell spread means',
    summary: 'The difference between the lowest and highest cell, and when it is worth acting on.',
    sections: [
      GuideSection('What the number is', [
        'The spread is the highest cell voltage minus the lowest, taken from the same reading. It is a difference, not a measurement of any one cell.',
        'The Cells screen draws a range and says whether the pack is inside it, so the colour and the sentence agree with the bars rather than each other.',
      ]),
      GuideSection('Read it at rest', [
        'Spread widens under load and during charge, because cells respond to current slightly differently. A spread measured while the pack is working is not the same measurement as one taken after it has settled.',
        'If the number only looks alarming while the pack is moving, check it again when it is quiet before treating it as a problem.',
      ]),
      GuideSection('One cell or all of them', [
        'A single cell that is out of line points at that cell or its connection. All cells drifting together points at the pack as a whole, and is usually about how it is being charged rather than about any one cell.',
      ]),
    ],
  ),
  GuideArticle(
    id: 'current-sign',
    title: 'Which way the current is flowing',
    summary: 'Positive is charging, negative is discharging, and what the small numbers mean.',
    sections: [
      GuideSection('The convention', [
        'The app treats current above zero as charging and current below zero as discharging. A reading very close to zero is treated as idle, because a pack sitting still still reports a small number.',
        'Power follows the same sign, so a charging pack shows positive power and a discharging one shows negative.',
      ]),
      GuideSection('Why the sign matters more than the size', [
        'The sign tells you which direction energy is moving; the size tells you how fast. A pack that reads discharging while the charger is connected is telling you something the magnitude alone would hide.',
      ]),
    ],
  ),
  GuideArticle(
    id: 'online-no-data',
    title: 'Gateway online, no data from the BMS',
    summary: 'Two different states that used to be shown as one.',
    sections: [
      GuideSection('Two questions, two answers', [
        'The dashboard answers two questions separately: is the gateway talking to us, and is the gateway talking to the battery. A gateway can be online and healthy while the link to the pack is down, and the banner says so in those words.',
        'That is deliberate. A single "offline" label for both cases sent people looking at their Wi-Fi when the problem was the short-range link to the pack.',
      ]),
      GuideSection('What the gateway does about it', [
        'The firmware drops a link that has gone silent, reconnects, and reports the signal strength and the last error it saw. Recent firmware also resets its reconnect backoff as soon as a valid frame arrives, so a link that is working recovers quickly from a drop.',
        'The signal strength is the first thing to read. A weak link is a physical problem: distance, the enclosure, or where the gateway is sitting.',
      ]),
      GuideSection('When it keeps happening', [
        'Move the gateway closer to the battery, or out of a metal enclosure if it is inside one. If the signal is strong and the link still drops, that is worth reporting with the time it happened, because the log will show what the gateway saw.',
      ]),
    ],
  ),
  GuideArticle(
    id: 'local-time',
    title: 'The times you see are your local time',
    summary: 'The gateway keeps UTC; the app renders it in your zone.',
    sections: [
      GuideSection('Why the gateway keeps UTC', [
        'Every gateway stores and sends timestamps in UTC, so a reading has one meaning regardless of where the pack is. If the gateway kept local time, two gateways in different zones would produce records that cannot be lined up.',
      ]),
      GuideSection('Where your zone is applied', [
        'The app converts the stored time for display. The gateway also has a time zone setting, which changes how times are written in its own log, not the timestamps it stores.',
        'If the app shows a time that looks wrong, check the phone first. A gateway-side zone only affects the device log.',
      ]),
    ],
  ),
  GuideArticle(
    id: 'trial-and-plan',
    title: 'What the trial changes',
    summary: 'Seven days of five-minute updates, once per gateway, then the hourly free tier.',
    sections: [
      GuideSection('What you get', [
        'A gateway that has not been on a plan gets seven days of five-minute updates from the moment it is claimed. The dashboard banner shows the date it ends.',
        'When it ends the gateway keeps working: it returns to the free tier, which reports once an hour. Nothing stops, and no data is deleted.',
      ]),
      GuideSection('Once per gateway', [
        'The trial belongs to the gateway, not the account, and it does not restart if the gateway is claimed again. A second gateway gets its own trial.',
        'A paid plan always takes priority over the trial, so upgrading does not wait for it to end.',
      ]),
    ],
  ),
];
