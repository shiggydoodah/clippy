import AppKit

/// The Spotlight-style panel window. `.nonactivatingPanel` is the load-bearing
/// piece of this app: it lets the panel take keyboard focus while the app the
/// user was working in stays active, which is what makes paste-back possible.
final class SummonPanel: NSPanel {
    // NSPanel's default answer depends on style mask details; with
    // .fullSizeContentView and hidden titlebar chrome we state it explicitly
    // so keyboard input can never silently stop working after a styling tweak.
    override var canBecomeKey: Bool { true }
    // Never main: becoming the main window is an "active app" behaviour and
    // we are specifically avoiding activation.
    override var canBecomeMain: Bool { false }
}
