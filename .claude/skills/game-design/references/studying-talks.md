# Studying talks and videos

## Tools on GitHub for turning YouTube videos into notes

| Tool | What it does | Notes |
|---|---|---|
| [jdepoix/youtube-transcript-api](https://github.com/jdepoix/youtube-transcript-api) | Python library and command that downloads a video's captions | No API key; the simplest start. `pip install youtube-transcript-api`, then `youtube_transcript_api <video id>` |
| [yt-dlp/yt-dlp](https://github.com/yt-dlp/yt-dlp) | Downloads videos, audio and subtitles | `yt-dlp --skip-download --write-auto-subs --sub-format vtt <url>` |
| [openai/whisper](https://github.com/openai/whisper) | Speech to text from audio | For videos with no captions: download the audio with yt-dlp, then transcribe |
| [danielmiessler/fabric](https://github.com/danielmiessler/fabric) | Prompt patterns for text, with a YouTube helper | `fabric -y <url> --pattern extract_wisdom` gives ideas, quotes, habits and references |
| [hancengiz/youtube-transcript-mcp](https://github.com/hancengiz/youtube-transcript-mcp) | An MCP server that gives Claude a transcript tool | Add it to Claude Code to read talks inside a session |
| [glebis/claude-skills](https://github.com/glebis/claude-skills) | Claude Code skills, including a yt-dlp transcript skill | A skill rather than a server |
| [badlogic/pi-skills](https://github.com/badlogic/pi-skills) | Agent skills, including a YouTube transcript skill (Node) | |
| [ZeroPointRepo/youtube-skills](https://github.com/ZeroPointRepo/youtube-skills) | Skills backed by a paid transcript service | Works where YouTube blocks direct requests, needs a key |

**In cloud sessions** YouTube often answers transcript requests from data-centre addresses with a
bot check, and the session's network may not allow the hosts involved. Then study the written
versions instead: the speaker's slides, articles and books, and detailed write-ups of the talk. Say
which you used.

## A workflow for one talk

1. Get the transcript (or the written version).
2. Pull out: the claim, the evidence (examples from real games), the technique, and when it does
   not apply.
3. Write each technique as a rule of one or two sentences, with the game it came from.
4. Test it against your own game: where would it apply, what would it cost, how would you know it
   worked?
5. File it in the skill's references under its topic; drop it if it repeats what is there.

## Reading list: the best-known talks and writing, by topic

Links go to the talk where the community lists give one; otherwise search the title on YouTube
(the GDC channel hosts most GDC talks) or the GDC Vault.

### Game design and development (the top 20)

1. Sid Meier: [Everything You Know Is Wrong](https://www.youtube.com/watch?v=bY7aRJE-oOY) (GDC 2010 keynote), and *Interesting Decisions* (GDC 2012).
2. Mark Rosewater: *Twenty Years, Twenty Lessons* (GDC 2016).
3. Raph Koster: [A Theory of Fun 10 Years Later](http://www.gdcvault.com/play/1016632/) (GDC 2012), and the book *A Theory of Fun for Game Design*.
4. Martin Jonasson and Petri Purho: [Juice It or Lose It](https://www.youtube.com/watch?v=Fy0aCDmgnxg) (2012).
5. Jan Willem Nijman: [The Art of Screenshake](https://www.youtube.com/watch?v=AJdEqssNZ-U) (INDIGO 2013).
6. Folmer Kelly: [Don't Juice It or Lose It](http://gdcvault.com/play/1020861/) (GDC Europe 2014), the counterweight.
7. Hidemaro Fujibayashi, Satoru Takizawa, Takuhiro Dohta: *Change and Constant: Breaking Conventions with The Legend of Zelda: Breath of the Wild* (GDC 2017), the chemistry engine.
8. Itay Keren: *Scroll Back: The Theory and Practice of Cameras in Side-Scrollers* (GDC 2015).
9. Matthias Worch: [Meaningful Choice in Game and Level Design](http://www.gdcvault.com/play/1020570/) (GDC 2014).
10. Jonathan Blow: [Truth in Game Design](http://www.gdcvault.com/play/1014982/) (GDC 2011) and [Indie Prototyping](https://www.youtube.com/watch?v=ISutk1mauPM) (2007).
11. Will Wright: [Dynamics for Designers](http://gdcvault.com/play/1019938/) (GDC Europe 2014).
12. George Fan: *How I Got My Mom to Play Through Plants vs. Zombies* (GDC 2012).
13. Celia Hodent: *The Gamer's Brain* talks (GDC, from 2015) and the book of the same name.
14. Anthony Giovannetti: *Slay the Spire: Metrics Driven Design and Balance* (GDC 2019).
15. Matthew Davis and Justin Ma: *Into the Breach Design Postmortem* (GDC 2019).
16. Chris Wilson: *Designing Path of Exile to Be Played Forever* (GDC 2019).
17. Dan Taylor: *Ten Principles for Good Level Design* (GDC 2013).
18. Scott Rogers: [Everything I Learned About Level Design I Learned from Disneyland](http://gdcvault.com/play/1305/) (GDC 2009).
19. Randy Smith: [Helping Your Players Feel Smart: Puzzles as User Interface](http://www.gdcvault.com/play/1333/) (GDC 2009).
20. Derek Sakamoto: [Hearthstone: How to Create an Immersive User Interface](http://www.gdcvault.com/play/1022036/) (GDC 2015).

### Player retention

- Chris Wilson, *Designing Path of Exile to Be Played Forever* (above): long-term goals, new
  content in seasons, a fair economy.
- Celia Hodent, *The Gamer's Brain, Part 2: UX of Onboarding and Player Engagement*.
- Anthony Giovannetti, *Slay the Spire* metrics (above): finding where and why players stop.
- Roblox creator documentation, production pages on retention, onboarding and core loops
  (in [roblox/creator-docs](https://github.com/Roblox/creator-docs)).
- Mark Brown (Game Maker's Toolkit): *How to Keep Players Engaged (Without Being Evil)*.

### Gameplay loops

- Daniel Cook: *Loops and Arcs* and *The Chemistry of Game Design* (skill atoms), Lostgarden essays.
- Henric Suuronen: [Killer Game Loops in Social Games](http://gdcvault.com/play/1014911/) (GDC).
- Joris Dormans and Ernest Adams: *Game Mechanics: Advanced Game Design* (resource flows, Machinations).
- Mark Brown: *Super Mario 3D World's 4 Step Level Design* (introduce, develop, twist, test).

### UI design

- Derek Sakamoto, Hearthstone UI (above).
- Celia Hodent, *The Gamer's Brain* (above).
- Erik Fagerholt and Magnus Lorentzon: *Beyond the HUD* (2009 thesis: diegetic, spatial, meta and non-diegetic UI).
- The Game UI Database (gameuidatabase.com): screens from many games to compare.
- Game Accessibility Guidelines (gameaccessibilityguidelines.com).

### Monetization (and its ethics)

- Chris Wilson, Path of Exile (above): cosmetics only, and why it works.
- Ramin Shokrizade: *The Top F2P Monetization Tricks* (2013 article), the dark patterns named.
- Roblox creator documentation on monetization foundations and season passes.
- Jamie Madigan: *Getting Gamers* (book): the psychology behind it.

### What makes a game fun

- Robin Hunicke, Marc LeBlanc, Robert Zubek: *MDA: A Formal Approach to Game Design* (2004 paper).
- Raph Koster, *A Theory of Fun* (above).
- Jesse Schell: *The Art of Game Design: A Book of Lenses* (book) and *Design Outside the Box* (DICE 2010).
- Scott Rigby and Richard Ryan: *Glued to Games* (self-determination theory and PENS).
- Mark Brown: *Secrets of Game Feel and Juice*, *The Two Types of Random in Game Design*,
  *Why Does Celeste Feel So Good to Play?*
- Maddy Thorson: the notes on Celeste's forgiving controls (coyote time, buffering, corner correction).
- Steve Swink: *Game Feel* (book).

### Pixel art

- Michael Azzi: *Pixel Logic* (book).
- Pedro Medeiros (saint11): pixel art tutorials.
- Raymond Schlitter (Slynyrd): *Pixelblog*.
- AdamCYounis and Brandon James Greer: YouTube channels on pixel art for games.
- Lospec: palettes and tutorials.
- [ashes999/pixel-artist-training](https://github.com/ashes999/pixel-artist-training) and
  [siilwyn/awesome-pixel-art](https://github.com/Siilwyn/awesome-pixel-art).
