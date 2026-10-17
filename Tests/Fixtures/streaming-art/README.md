# Streaming redesign fixtures

These credited NASA photographs illustrate a fictional, clearly labeled preview library. Titles, channels, comments, statistics and progress are synthetic. Playback is the existing generated twelve-second silent test-pattern clip, not NASA footage. The production Debug Simulator target uses the normal UI, authenticated image/media transport, native player, and private download preparer against a loopback fixture server. Release/device builds cannot enter the harness. No live account or archive is contacted.

The files are not proprietary movie artwork or app logos. `credits.json` records each NASA source URL, asset identifier and credit. Source: NASA. No NASA endorsement is implied. Use follows [NASA's media guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/); fixture imagery retains its source terms rather than the repository's software license.

Run `python3 Tests/Fixtures/streaming_server.py`, then launch the shipping Debug Simulator app with `--streaming-fixture --streaming-fixture-reset`. Optional flags: `--streaming-fixture-dark`, `--streaming-fixture-light`, `--streaming-fixture-accessibility`, `--streaming-fixture-long-list`, `--streaming-fixture-login`. All mutations affect in-memory fixture values or the separate `StreamingDesignFixture-v1` private directory. The banner marks every screenshot as test data.
