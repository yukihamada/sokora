import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var menubarController: MenubarController?
    var proxyServer: ProxyServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menubarController = MenubarController()
        proxyServer = ProxyServer()
        Task {
            await proxyServer?.start()
        }
    }
}
