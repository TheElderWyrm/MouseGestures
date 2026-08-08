import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - View Model

/// Backing state for ``ReportIssueView``.
///
/// Every property a control binds to is a stored `@Published` rather than a
/// computed one: a computed property never fires `objectWillChange`, so SwiftUI
/// would not redraw when the diagnostics finish loading. `reportText` is
/// therefore recomposed eagerly whenever either half of it changes, instead of
/// being derived at read time.
final class ReportIssueViewModel: ObservableObject {

    /// What the user types. `didSet` keeps `reportText` -- the thing the user
    /// reviews and the thing that gets sent -- in lockstep with it.
    @Published var userDescription: String = "" {
        didSet { recomposeReport() }
    }

    /// The redacted diagnostics half, filled in asynchronously.
    @Published private(set) var diagnostics: String = ""

    /// Exactly what will be copied, saved, or mailed. Shown verbatim in the
    /// sheet -- there is no second rendering for the send path.
    @Published private(set) var reportText: String = ""

    @Published private(set) var isGathering: Bool = false

    @Published var statusMessage: String?
    @Published var statusIsError: Bool = false

    private var hasLoaded = false

    // MARK: - Loading

    /// Kicks off diagnostics collection. Safe to call repeatedly (`onAppear`
    /// fires again when the window is re-shown); only the first call works.
    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        isGathering = true
        recomposeReport()

        IssueReportService.shared.gatherDiagnostics { [weak self] text in
            // Delivered on the main thread by the service.
            guard let self = self else { return }
            self.diagnostics = text
            self.isGathering = false
            self.recomposeReport()
        }
    }

    private func recomposeReport() {
        reportText = IssueReportLogic.fullReport(description: userDescription, diagnostics: diagnostics)
    }

    // MARK: - Actions

    /// Opens a prefilled draft in the user's mail client.
    ///
    /// `mailto:` URLs are truncated by some clients past a few thousand
    /// characters, so a long report is put on the clipboard instead and the
    /// draft asks the user to paste it. If no mail client is configured at all,
    /// the report still ends up on the clipboard along with the address.
    func sendEmail() {
        let info = IssueReportService.shared.versionInfo
        let mail = IssueReportLogic.composeMail(
            subject: IssueReportLogic.mailSubject(appVersion: info.version, buildNumber: info.build),
            description: userDescription,
            diagnostics: diagnostics
        )

        guard let url = URL(string: mail.urlString) else {
            copyToPasteboard(reportText)
            setStatus("Couldn't build an email link. The full report has been copied to your clipboard — please send it to \(IssueReportLogic.supportEmail).", isError: true)
            return
        }

        if mail.needsClipboardFallback {
            copyToPasteboard(reportText)
        }

        guard hasMailClient(), NSWorkspace.shared.open(url) else {
            copyToPasteboard(reportText)
            setStatus("No email app is set up on this Mac. The full report has been copied to your clipboard — please send it to \(IssueReportLogic.supportEmail).", isError: true)
            return
        }

        if mail.needsClipboardFallback {
            setStatus("The report was too long for an email link, so it's on your clipboard — paste it into the draft before sending.", isError: false)
        } else {
            setStatus("Opened a draft in your email app. Press send there to file the report.", isError: false)
        }
    }

    func copyReport() {
        copyToPasteboard(reportText)
        setStatus("Report copied to the clipboard.", isError: false)
    }

    func saveToFile() {
        let panel = NSSavePanel()
        panel.title = "Save Issue Report"
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = IssueReportLogic.suggestedFileName()

        // Captured before the panel returns; `reportText` is main-thread state
        // and the completion handler runs on main, but reading it once here
        // keeps what's written identical to what the user reviewed.
        let contents = reportText
        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            do {
                try contents.write(to: url, atomically: true, encoding: .utf8)
                self.setStatus("Report saved to \(url.lastPathComponent).", isError: false)
            } catch {
                self.setStatus("Couldn't save the report: \(error.localizedDescription)", isError: true)
            }
        }
    }

    // MARK: - Helpers

    private func hasMailClient() -> Bool {
        guard let probe = URL(string: "mailto:\(IssueReportLogic.supportEmail)") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}

// MARK: - View

/// The "Report an Issue" sheet: describe the problem, review the *exact* text
/// that will leave the machine, then send / copy / save it.
struct ReportIssueView: View {
    @StateObject private var viewModel = ReportIssueViewModel()
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MGSheetHeader(
                "Report an Issue",
                subtitle: "Sends a report to \(IssueReportLogic.supportEmail). Nothing leaves your Mac until you choose an option below."
            )

            ScrollView {
                VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
                    descriptionSection
                    previewSection
                }
                .padding(MGStyle.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let message = viewModel.statusMessage {
                statusStrip(message)
            }

            footer
        }
        .frame(width: 660, height: 660)
        .onAppear { viewModel.loadIfNeeded() }
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
            Text("What went wrong?")
                .font(.system(size: MGStyle.FontSize.heading, weight: .semibold))

            Text("What were you doing, what did you expect, and what happened instead? Anything you type here is included in the report.")
                .font(.caption)
                .foregroundColor(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.userDescription)
                    .font(.system(size: MGStyle.FontSize.body))
                    .padding(MGStyle.Spacing.sm)

                if viewModel.userDescription.isEmpty {
                    Text("e.g. “The bottom-right corner gesture stopped firing after I woke the Mac from sleep.”")
                        .font(.system(size: MGStyle.FontSize.body))
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, MGStyle.Spacing.md)
                        .padding(.vertical, MGStyle.Spacing.lg)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 110)
            .background(RoundedRectangle(cornerRadius: MGStyle.Corner.md).fill(MGStyle.Colors.contentBackground))
            .overlay(RoundedRectangle(cornerRadius: MGStyle.Corner.md).stroke(MGStyle.Colors.separator, lineWidth: 0.5))
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
            HStack(spacing: MGStyle.Spacing.md) {
                Text("Exactly what will be sent")
                    .font(.system(size: MGStyle.FontSize.heading, weight: .semibold))

                if viewModel.isGathering {
                    ProgressView().controlSize(.small)
                }

                Spacer()
            }

            Label(
                "Your license key, home folder path, user name, email addresses and any key-like text are removed automatically.",
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundColor(.secondary)

            ScrollView {
                Text(viewModel.reportText)
                    .font(.system(size: MGStyle.FontSize.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(MGStyle.Spacing.md)
            }
            .frame(height: 260)
            .background(RoundedRectangle(cornerRadius: MGStyle.Corner.md).fill(MGStyle.Colors.contentBackground))
            .overlay(RoundedRectangle(cornerRadius: MGStyle.Corner.md).stroke(MGStyle.Colors.separator, lineWidth: 0.5))
        }
    }

    // MARK: - Status

    private func statusStrip(_ message: String) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: MGStyle.Spacing.md) {
                Image(systemName: viewModel.statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundColor(viewModel.statusIsError ? .orange : .green)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.horizontal, MGStyle.Spacing.xl)
            .padding(.vertical, MGStyle.Spacing.lg)
        }
    }

    // MARK: - Footer

    /// Hand-rolled rather than `MGSheetFooter` because that helper marks its
    /// primary button as the Return-key default, which would steal Return from
    /// the multi-line description editor above.
    private var footer: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: MGStyle.Spacing.md) {
                Button("Copy Report") { viewModel.copyReport() }
                    .disabled(viewModel.isGathering)

                Button("Save to File…") { viewModel.saveToFile() }
                    .disabled(viewModel.isGathering)

                Spacer()

                Button("Close", action: onClose)

                Button("Send Email") { viewModel.sendEmail() }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isGathering)
            }
            .padding(MGStyle.Spacing.xl)
        }
    }
}

// MARK: - Window Presentation

/// Presents ``ReportIssueView`` in its own window.
///
/// MouseGestures is an `LSUIElement` agent app, so there is no main window to
/// hang a sheet off when the flow is started from the menu bar. A standalone
/// window is used for both entry points (menu bar and Settings ▸ About) so
/// there is exactly one presentation path.
///
/// The window is retained here and released via `NSWindowDelegate` rather than
/// a block-based NotificationCenter observer: those return an opaque token that
/// must be kept to unregister, and discarding it leaks an observer that can
/// never be removed.
final class ReportIssueWindowController: NSObject, NSWindowDelegate {
    static let shared = ReportIssueWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    /// Shows (or re-focuses) the report window. Safe to call from any thread;
    /// all AppKit work is marshalled to main.
    func present() {
        // Explicitly typed: `self?.presentOnMain()` infers `() -> ()?` via optional
        // chaining, which doesn't satisfy DispatchQueue.async's `() -> Void`.
        let work: () -> Void = { [weak self] in self?.presentOnMain() }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    private func presentOnMain() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = ReportIssueView(onClose: { [weak self] in self?.close() })

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 660),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Report an Issue"
        newWindow.contentView = NSHostingView(rootView: content)
        newWindow.setContentSize(NSSize(width: 660, height: 660))
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self

        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
    }
}
