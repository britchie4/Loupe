import LoupeFeature

// A coding agent launches `Loupe --mcp` to reach the running Loupe app through Agent Link.
// That mode shows no interface; otherwise start the app as usual.
if CommandLine.arguments.contains("--mcp") {
    AgentLinkRelay.run()
}

LoupeApp.main()
