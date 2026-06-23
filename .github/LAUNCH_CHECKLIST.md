# MacHive Launch Checklist

## Pre-Launch (Do these NOW)

### GitHub Repository Setup
- [ ] Add repository description from `.github/DESCRIPTION.txt`
- [ ] Add all topics from `.github/TOPICS.md`
- [ ] Create first release (v1.0.0) with MacHive.app binary
- [ ] Add social preview image (1280x640px)
- [ ] Enable Discussions tab
- [ ] Pin important issues/discussions

### Documentation
- [x] README with viral headline
- [x] Badges (build, license, platform)
- [ ] Add demo GIF/screenshot (CRITICAL - 3x stars)
- [x] Quick start (under 5 steps)
- [x] Clear use cases
- [ ] Add "Star this repo" call-to-action

## Launch Day (Post in this order)

### Reddit (High-impact subreddits)
1. **r/LocalLLaMA** (200k+ members) - Post title: "I built a GUI to run Llama 70B across multiple Macs with zero config"
2. **r/MachineLearning** (2.5M members) - Post title: "MacHive: Distributed inference for Apple Silicon Macs"
3. **r/MacApps** (50k members) - Post title: "MacHive - Turn your Macs into an AI cluster"
4. **r/homelab** (500k members) - Post title: "Free alternative to cloud AI: Run LLMs on your Mac cluster"
5. **r/SelfHosted** (200k members) - Post title: "Self-hosted AI inference across multiple Macs"

**Reddit Post Template:**
```
Title: I built a free macOS app to run Llama 70B across multiple Macs

I got tired of paying for ChatGPT Plus when I have 3 Macs sitting around.

MacHive pools their RAM and runs large models locally:
- M1 Mac (8GB) + M2 Mac (16GB) = Can run Llama 3 70B
- Zero configuration, just click Start
- Completely free, no API keys
- All data stays on your network

GitHub: https://github.com/PlatiniumTermite/MacHive

It's built on exo (the distributed inference framework) but with a GUI so non-technical users can use it.

Would love feedback!
```

### Hacker News
- [ ] Submit to Show HN: https://news.ycombinator.com/submit
- Title: "Show HN: MacHive – Run Llama 70B across multiple Macs with one click"
- Text: Brief description + link

### Twitter/X
- [ ] Thread explaining the problem and solution
- [ ] Tag @exo_labs (they'll likely retweet)
- [ ] Use hashtags: #LocalLLM #AppleSilicon #MachineLearning #OpenSource
- [ ] Post demo video/GIF

### Product Hunt
- [ ] Submit as new product
- [ ] Prepare 3-5 screenshots
- [ ] Write compelling tagline: "Turn your Macs into an AI supercomputer"

## Week 1 Follow-up

### Community Engagement
- [ ] Respond to every GitHub issue within 24h
- [ ] Answer all Reddit comments
- [ ] Join r/LocalLLaMA Discord and share
- [ ] Post in exo's GitHub Discussions

### Content
- [ ] Write blog post: "How I built MacHive"
- [ ] Create demo video (YouTube)
- [ ] Submit to newsletters:
  - TLDR Newsletter
  - Pointer.io
  - Console.dev
  - Changelog News

### Outreach
- [ ] Email tech bloggers who cover AI/Mac apps
- [ ] Reach out to Mac Power Users podcast
- [ ] Contact AppleInsider, 9to5Mac for coverage

## Viral Triggers (What makes repos famous)

### The Formula
1. **Solve a painful problem** ✅ (Running 70B models is expensive/hard)
2. **Make it stupidly easy** ✅ (One-click install)
3. **Free alternative to paid service** ✅ (vs ChatGPT Plus/Claude)
4. **Show, don't tell** ⚠️ (NEED DEMO GIF)
5. **Timing** - Post when US/Europe are awake (9am-12pm EST)

### Reddit Success Pattern
- Post on Tuesday-Thursday (highest engagement)
- 9-11am EST (when devs browse Reddit)
- Include "I built" in title (personal story = upvotes)
- Respond to every comment in first 2 hours
- Cross-post to related subreddits after 24h

### HN Success Pattern
- Submit Saturday morning (Show HN gets more attention)
- Respond to technical questions immediately
- Don't argue with critics, just fix issues they mention
- If it doesn't get traction, resubmit in 2 weeks with improvements

## Metrics to Track

- GitHub stars (goal: 100 in week 1, 1000 in month 1)
- Reddit upvotes (goal: 500+ on r/LocalLLaMA)
- HN points (goal: front page = 100+ points)
- Downloads from Releases
- Issues/PRs (engagement signal)

## Red Flags to Avoid

- ❌ Spamming multiple subreddits same day
- ❌ Ignoring criticism in comments
- ❌ No demo GIF (instant bounce)
- ❌ Posting at 3am EST (no one sees it)
- ❌ Asking for stars (looks desperate)

## The Nuclear Option (If nothing else works)

1. Make a 60-second demo video
2. Post on Twitter with: "I spent 6 months building this and got 0 stars. Here's what it does..."
3. Tag relevant accounts
4. The sympathy angle works surprisingly well

## Most Important

**Get the demo GIF/video done FIRST.** Nothing else matters if people can't see it working.

Record:
1. Opening MacHive on 2 Macs
2. Both showing in peer list
3. Clicking Start on both
4. Opening chat
5. Asking a question
6. Getting a response
7. Showing Activity Monitor with both Macs at 30% CPU

This one GIF will 10x your stars.
