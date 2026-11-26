// Console: a home screen for the TV that lists the nxnative games in /Applications and is driven by a game controller.
// It runs in the background from login (LaunchAgent, --hidden) and comes to the front when a controller connects, when it is opened
// again, or when a game started from it ends. A starts the selected game without its settings window; + opens the options;
// holding HOME (1.2 s) while a game runs quits the game and comes back here. Arrows, Return, Escape and Tab do the same on a keyboard.
// --snapshot <file.png> draws the screen into a PNG at 1920x1080 and exits (to check the look without taking over the screen).
import AppKit
import SwiftUI
import GameController
import IOKit.ps
import IOBluetooth
import ApplicationServices
import CoreAudio

let cyan = Color(red: 0.0, green: 0.76, blue: 0.89)
let gamePrefix = "org.nxnative."
// Games from other ports, by bundle identifier: one per line in ~/Library/Application Support/Console/extra.txt
let extraIDs: Set<String> = {
    var ids: Set<String> = []
    let f = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Console/extra.txt")
    for l in ((try? String(contentsOf: f, encoding: .utf8)) ?? "").split(separator: "\n") {
        let t = l.trimmingCharacters(in: .whitespaces); if !t.isEmpty && !t.hasPrefix("#") { ids.insert(t) }
    }
    return ids
}()
// The text in the Mac's language (System Settings > General > Language & Region), English for a language it has no text in.
// --lang <code> picks one (to check a translation).
let strings: [String: [String: String]] = [
    "en": ["noGames": "No games found in Applications", "connect": "Connect a controller", "play": "Play", "options": "Options",
           "homeHint": "Hold in a game: back here", "close": "B: close", "m0": "Play with the game's settings", "m1": "Refresh the list",
           "m2": "Swap the A and B buttons", "m3": "Exit to the desktop", "m4": "Put the Mac to sleep", "m5": "Turn off the controller and exit"],
    "es": ["noGames": "No hay juegos en Aplicaciones", "connect": "Conecta un mando", "play": "Jugar", "options": "Opciones",
           "homeHint": "Mantener en el juego: volver aquí", "close": "B: cerrar", "m0": "Jugar con los ajustes del juego", "m1": "Actualizar la lista",
           "m2": "Intercambiar los botones A y B", "m3": "Salir al escritorio", "m4": "Poner el Mac en reposo", "m5": "Apagar el mando y salir"],
    "fr": ["noGames": "Aucun jeu dans Applications", "connect": "Connectez une manette", "play": "Jouer", "options": "Options",
           "homeHint": "Maintenir en jeu : revenir ici", "close": "B : fermer", "m0": "Jouer avec les réglages du jeu", "m1": "Actualiser la liste",
           "m2": "Inverser les boutons A et B", "m3": "Quitter vers le bureau", "m4": "Suspendre le Mac", "m5": "Éteindre la manette et quitter"],
    "de": ["noGames": "Keine Spiele in Programme", "connect": "Controller verbinden", "play": "Spielen", "options": "Optionen",
           "homeHint": "Im Spiel halten: hierher zurück", "close": "B: schließen", "m0": "Mit den Spieleinstellungen spielen", "m1": "Liste aktualisieren",
           "m2": "Tasten A und B tauschen", "m3": "Zum Schreibtisch", "m4": "Mac in den Ruhezustand", "m5": "Controller ausschalten und beenden"],
    "it": ["noGames": "Nessun gioco in Applicazioni", "connect": "Collega un controller", "play": "Gioca", "options": "Opzioni",
           "homeHint": "Tieni premuto nel gioco: torna qui", "close": "B: chiudi", "m0": "Gioca con le impostazioni del gioco", "m1": "Aggiorna l'elenco",
           "m2": "Scambia i pulsanti A e B", "m3": "Esci alla scrivania", "m4": "Metti il Mac in stop", "m5": "Spegni il controller ed esci"],
    "pt": ["noGames": "Nenhum jogo em Aplicativos", "connect": "Conecte um controle", "play": "Jogar", "options": "Opções",
           "homeHint": "Segure no jogo: voltar aqui", "close": "B: fechar", "m0": "Jogar com os ajustes do jogo", "m1": "Atualizar a lista",
           "m2": "Trocar os botões A e B", "m3": "Sair para a mesa", "m4": "Colocar o Mac em repouso", "m5": "Desligar o controle e sair"],
]
let lang: String = {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: "--lang"), i + 1 < a.count { return a[i + 1] }
    let code = String((Locale.preferredLanguages.first ?? "en").prefix(2))
    return strings[code] != nil ? code : "en"
}()
func L(_ k: String) -> String { strings[lang]?[k] ?? strings["en"]?[k] ?? k }

func isGame(_ id: String?) -> Bool { guard let id else { return false }; return id.hasPrefix(gamePrefix) || extraIDs.contains(id) }

struct Game: Identifiable { let id: String; let name: String; let url: URL; let icon: NSImage; let tile: NSImage }

// The tile as the screen shows it, drawn once: the picture with rounded corners and its drop shadow, on a canvas TILE_PAD larger on each side.
// SwiftUI drawing a blurred shadow per tile on every frame of a move made the screen stutter at TV resolution.
let TILE_PAD: CGFloat = 0.10
func bakedTile(_ img: NSImage) -> NSImage {
    let S: CGFloat = 512, P = S * TILE_PAD, side = S + 2 * P
    let out = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
        let r = NSRect(x: P, y: P, width: S, height: S), path = NSBezierPath(roundedRect: r, xRadius: S * 0.03, yRadius: S * 0.03)
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.5); sh.shadowBlurRadius = S * 0.04; sh.shadowOffset = NSSize(width: 0, height: -S * 0.02)
        sh.set(); NSColor.black.setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        path.addClip(); img.draw(in: r)
        return true
    }
    var rect = NSRect(x: 0, y: 0, width: side, height: side)
    guard let cg = out.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return out }
    return NSImage(cgImage: cg, size: out.size)   // a bitmap now, not a drawing handler run again at each draw
}

// The icon of an app as a square tile picture. Icons drawn as a macOS rounded square with a transparent margin (the ones made from
// box art) are cropped to the inside of that square, so that every tile is a full square picture like the game icons from the games' own data.
func tileImage(_ url: URL) -> NSImage {
    var img: NSImage?
    if let f = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
        img = NSImage(contentsOf: url.appendingPathComponent("Contents/Resources/" + (f.hasSuffix(".icns") ? f : f + ".icns")))
    }
    let base = img ?? NSWorkspace.shared.icon(forFile: url.path)
    var r = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    guard let cg = base.cgImage(forProposedRect: &r, context: nil, hints: nil) else { return base }
    let w = cg.width, h = cg.height
    if let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
        ctx.draw(cg, in: CGRect(x: -2, y: 3 - CGFloat(h), width: CGFloat(w), height: CGFloat(h)))   // the pixel 2,2 from the top left
        if let d = ctx.data, d.load(fromByteOffset: 3, as: UInt8.self) < 16 {
            let s = CGFloat(w) / 1024
            if let c = cg.cropping(to: CGRect(x: 154 * s, y: 164 * s, width: 716 * s, height: 716 * s)) { return NSImage(cgImage: c, size: NSSize(width: 512, height: 512)) }
        }
    }
    return NSImage(cgImage: cg, size: NSSize(width: 512, height: 512))
}

final class Model: ObservableObject {
    @Published var games: [Game] = []
    @Published var sel = 0
    @Published var launching: Game?
    @Published var controller: String?
    @Published var now = Date()
    @Published var battery: Int?
    @Published var charging = false
    @Published var menuOpen = false
    @Published var menuSel = 0
    @Published var logo = false       // the opening: the logo on black
    @Published var logoIn = false     // the logo has come in
    @Published var revealed = true    // the bars and the tiles are in place (they come in one after another)
    let menuItems = ["m0", "m1", "m2", "m3", "m5", "m4"].map { L($0) }   // the order on screen

    var lastPlayed: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: "lastPlayed") as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "lastPlayed") }
    }

    // The covers made once per app (by its path and modification time), so coming up redraws none of them: reading and baking all of them
    // held the screen up 0.6 s before its opening
    var covers: [String: (Date, NSImage, NSImage)] = [:]

    func scan() {
        let fm = FileManager.default; var out: [Game] = []; var seen = Set<String>()
        for d in [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")] {
            for u in (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [] where u.pathExtension == "app" {
                guard let b = Bundle(url: u), let id = b.bundleIdentifier, isGame(id), !seen.contains(id) else { continue }
                seen.insert(id)
                let mtime = (try? fm.attributesOfItem(atPath: u.path)[.modificationDate] as? Date) ?? .distantPast
                let icon: NSImage, tile: NSImage
                if let c = covers[u.path], c.0 == mtime { (icon, tile) = (c.1, c.2) }
                else { icon = tileImage(u); tile = bakedTile(icon); covers[u.path] = (mtime, icon, tile) }
                out.append(Game(id: id, name: u.deletingPathExtension().lastPathComponent, url: u, icon: icon, tile: tile))
            }
        }
        let lp = lastPlayed
        out.sort { let a = lp[$0.id] ?? 0, b = lp[$1.id] ?? 0; return a != b ? a > b : $0.name < $1.name }
        games = out
        if sel >= games.count { sel = max(0, games.count - 1) }
    }

    func readBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { battery = nil; return }
        for ps in list {
            if let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any], let cur = d[kIOPSCurrentCapacityKey] as? Int {
                battery = cur; charging = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            }
        }
    }
}

struct HomeView: View {
    @ObservedObject var m: Model
    var snapshot = false   // ImageRenderer draws no ScrollView content: the snapshot lays the row out without one

    func font(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: s, weight: w, design: .rounded) }

    var body: some View {
        GeometryReader { geo in
            let H = geo.size.height, tile = H * 0.30
            ZStack {
                LinearGradient(colors: [Color(white: 0.20), Color(white: 0.13)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                VStack(spacing: 0) {
                    topBar(H)
                        .opacity(m.revealed ? 1 : 0).offset(y: m.revealed ? 0 : -H * 0.04)
                        .animation(.easeOut(duration: 0.5).delay(0.05), value: m.revealed)
                    Spacer()
                    if m.games.isEmpty {
                        Text(L("noGames")).font(font(H * 0.035)).foregroundColor(.gray)
                    } else if snapshot {
                        HStack(alignment: .bottom, spacing: tile * 0.09) {
                            ForEach(Array(m.games.enumerated()), id: \.element.id) { i, g in tileView(g, i, tile, H) }
                        }
                        .padding(.horizontal, H * 0.09).padding(.vertical, H * 0.05)
                        .frame(width: geo.size.width, alignment: .leading).clipped()
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .bottom, spacing: tile * 0.09) {
                                    ForEach(Array(m.games.enumerated()), id: \.element.id) { i, g in
                                        tileView(g, i, tile, H).id(i)
                                    }
                                }
                                .padding(.horizontal, H * 0.09).padding(.vertical, H * 0.05)
                            }
                            .onChange(of: m.sel) { _, new in withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(new, anchor: .center) } }
                            .onAppear { proxy.scrollTo(m.sel, anchor: .center) }
                        }
                    }
                    Spacer()
                    bottomBar(H)
                        .opacity(m.revealed ? 1 : 0).offset(y: m.revealed ? 0 : H * 0.04)
                        .animation(.easeOut(duration: 0.5).delay(0.15), value: m.revealed)
                }
                if m.logo { logoView(H).transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 1.12)))) }
                if let g = m.launching { launchingView(g, H).transition(.opacity) }
                if m.menuOpen { menuView(H).transition(.opacity) }
            }
            .animation(.easeOut(duration: 0.2), value: m.menuOpen)
            .animation(.easeIn(duration: 0.45), value: m.logo)
            .animation(.easeOut(duration: 0.25), value: m.launching?.id)
        }
    }

    func topBar(_ H: CGFloat) -> some View {
        HStack(spacing: H * 0.02) {
            Image(systemName: "person.crop.circle.fill").font(.system(size: H * 0.055)).foregroundColor(Color(white: 0.55))
            Spacer()
            Text(m.now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)).font(font(H * 0.032, .medium))
            if let b = m.battery {
                HStack(spacing: H * 0.006) {
                    Text("\(b)%").font(font(H * 0.026))
                    Image(systemName: m.charging ? "battery.100.bolt" : b > 70 ? "battery.100" : b > 40 ? "battery.75" : b > 15 ? "battery.25" : "battery.0")
                        .font(.system(size: H * 0.03))
                }
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, H * 0.06).padding(.top, H * 0.045)
    }

    func tileView(_ g: Game, _ i: Int, _ tile: CGFloat, _ H: CGFloat) -> some View {
        let on = i == m.sel
        return VStack(alignment: .leading, spacing: H * 0.018) {
            Text(g.name).font(font(H * 0.032, .medium)).foregroundColor(cyan).lineLimit(1).fixedSize()
                .frame(width: tile, alignment: .leading).opacity(on ? 1 : 0)
            Image(nsImage: g.tile).resizable().interpolation(.high)
                .frame(width: tile * (1 + 2 * TILE_PAD), height: tile * (1 + 2 * TILE_PAD)).padding(-tile * TILE_PAD)
                .overlay(RoundedRectangle(cornerRadius: tile * 0.05).stroke(on ? cyan : .clear, lineWidth: H * 0.006).padding(-H * 0.009))
                .scaleEffect(on ? 1.04 : 1)
                .animation(.easeOut(duration: 0.15), value: on)
        }
        .opacity(m.revealed ? 1 : 0).offset(y: m.revealed ? 0 : H * 0.10).scaleEffect(m.revealed ? 1 : 0.9)
        .animation(.spring(response: 0.6, dampingFraction: 0.78).delay(0.08 + Double(min(i, 8)) * 0.07), value: m.revealed)
    }

    func logoView(_ H: CGFloat) -> some View {
        let red = LinearGradient(colors: [Color(red: 0.97, green: 0.18, blue: 0.18), Color(red: 0.76, green: 0.04, blue: 0.08)], startPoint: .top, endPoint: .bottom)
        return ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [Color(red: 0.9, green: 0.1, blue: 0.12).opacity(m.logoIn ? 0.28 : 0), .clear], center: .center, startRadius: 0, endRadius: H * 0.6)
                .ignoresSafeArea()
            VStack(spacing: H * 0.04) {
                RoundedRectangle(cornerRadius: H * 0.05).fill(red).frame(width: H * 0.22, height: H * 0.22)
                    .overlay(Image(systemName: "gamecontroller.fill").font(.system(size: H * 0.105, weight: .semibold)).foregroundColor(.white))
                    .shadow(color: Color.red.opacity(m.logoIn ? 0.55 : 0), radius: H * 0.05)
                    .rotationEffect(.degrees(m.logoIn ? 0 : -12))
                Text("CONSOLE").font(font(H * 0.04, .heavy)).foregroundColor(.white).tracking(m.logoIn ? H * 0.012 : H * 0.04)
                    .opacity(m.logoIn ? 1 : 0)
            }
            .scaleEffect(m.logoIn ? 1 : 0.6).opacity(m.logoIn ? 1 : 0).blur(radius: m.logoIn ? 0 : H * 0.015)
        }
        .animation(.spring(response: 0.7, dampingFraction: 0.7), value: m.logoIn)
    }

    func hint(_ symbol: String, _ text: String, _ H: CGFloat) -> some View {
        HStack(spacing: H * 0.008) { Image(systemName: symbol).font(.system(size: H * 0.032)); Text(text).font(font(H * 0.024)) }
    }

    func bottomBar(_ H: CGFloat) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1).padding(.horizontal, H * 0.04)
            HStack(spacing: H * 0.035) {
                Image(systemName: "gamecontroller.fill").font(.system(size: H * 0.03)).foregroundColor(m.controller == nil ? .gray : cyan)
                Text(m.controller ?? L("connect")).font(font(H * 0.024))
                Spacer()
                hint("a.circle.fill", L("play"), H)
                hint("plus.circle.fill", L("options"), H)
                hint("house.circle.fill", L("homeHint"), H)
            }
            .foregroundColor(.white).padding(.horizontal, H * 0.06).frame(height: H * 0.10)
        }
    }

    func launchingView(_ g: Game, _ H: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: H * 0.03) {
                Image(nsImage: g.icon).resizable().interpolation(.high).frame(width: H * 0.3, height: H * 0.3)
                    .clipShape(RoundedRectangle(cornerRadius: H * 0.012))
                Text(g.name).font(font(H * 0.04, .semibold)).foregroundColor(.white)
                ProgressView().controlSize(.large).tint(.white)
            }
        }
    }

    func menuView(_ H: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(alignment: .leading, spacing: H * 0.012) {
                Text(L("options")).font(font(H * 0.04, .bold)).foregroundColor(.white).padding(.bottom, H * 0.01)
                ForEach(m.menuItems.indices, id: \.self) { i in
                    Text(m.menuItems[i]).font(font(H * 0.03)).foregroundColor(.white)
                        .padding(.horizontal, H * 0.025).padding(.vertical, H * 0.014)
                        .frame(width: H * 0.75, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: H * 0.012).fill(i == m.menuSel ? cyan.opacity(0.22) : .clear))
                        .overlay(RoundedRectangle(cornerRadius: H * 0.012).stroke(i == m.menuSel ? cyan : .clear, lineWidth: H * 0.004))
                }
                Text(L("close")).font(font(H * 0.022)).foregroundColor(.gray).padding(.top, H * 0.01)
            }
            .padding(H * 0.045)
            .background(RoundedRectangle(cornerRadius: H * 0.025).fill(Color(white: 0.21)))
        }
    }
}

final class HomeWindow: NSWindow {
    var onKey: ((UInt16) -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with e: NSEvent) { onKey?(e.keyCode) }
}

func isBuiltIn(_ s: NSScreen) -> Bool {
    guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return true }
    return CGDisplayIsBuiltin(n.uint32Value) != 0
}

// The audio outputs: (id, name, transport type)
func outputDevices() -> [(AudioDeviceID, String, UInt32)] {
    let sys = AudioObjectID(kAudioObjectSystemObject)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.compactMap { id in
        var sa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var ss: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &sa, 0, nil, &ss) == noErr, ss > 0 else { return nil }   // no output streams: a microphone
        var t: UInt32 = 0, ts = UInt32(MemoryLayout<UInt32>.size)
        var ta = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(id, &ta, 0, nil, &ts, &t)
        var name: Unmanaged<CFString>?, ns = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var na = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(id, &na, 0, nil, &ns, &name)
        return (id, (name?.takeRetainedValue() as String?) ?? "?", t)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let m = Model()
    var window: HomeWindow!
    var timer: Timer?
    var running: String?          // the game started from here (or the one HOME asked to quit)
    let startedAt = Date()
    var lastDir = 0, dirSince = Date.distantPast, lastRepeat = Date.distantPast
    var prevA = false, prevB = false, prevMenu = false
    var homeSince: Date?, homeDone = false, prevHome = false
    var quietUntil = Date.distantPast   // a controller turned off from here may connect again for a moment: no coming up for it
    var hadController = false, lastCheck = Date.distantPast, prevWake = false
    var cursorHidden = false
    var lastPoll = Date.distantPast   // a gap between two looks at the controller is the main thread held up: logged while the screen shows
    var lastDismiss = Date.distantPast, askedAccess = false

    // ~/Library/Logs/Console/console.log: controllers coming and going, the buttons that bring this screen up, showing and hiding
    let logURL: URL = {
        let d = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Console")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("console.log")
    }()
    func log(_ text: String) {
        let line = "\(Date()) \(text)\n"
        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: logURL, atomically: true, encoding: .utf8) }
    }

    func setCursorHidden(_ hidden: Bool) {   // NSCursor.hide and unhide nest: one of each
        guard hidden != cursorHidden else { return }
        cursorHidden = hidden
        if hidden { NSCursor.hide() } else { NSCursor.unhide() }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        GCController.shouldMonitorBackgroundEvents = true   // HOME must work while a game is in front
        window = HomeWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: HomeView(m: m))
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenNone, .canJoinAllSpaces]
        window.onKey = { [weak self] k in self?.key(k) }
        let nc = NotificationCenter.default
        nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            self?.log("controller connected: \((n.object as? GCController)?.vendorName ?? "?")"); self?.controllerConnected()
        }
        nc.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] n in
            self?.log("controller disconnected: \((n.object as? GCController)?.vendorName ?? "?")"); self?.updateController()
        }
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            if self?.window.isVisible == true { self?.place() }
        }
        // Apple's Games app (which the controller's HOME button opens) is closed as it opens, and this screen comes up in its place, unless a
        // game runs. defaults write io.github.vtanco.console replaceGamesApp -bool false turns that off.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.bundleIdentifier == "com.apple.games",
                  UserDefaults.standard.object(forKey: "replaceGamesApp") as? Bool ?? true else { return }
            self.log("Games app opened: closing it")
            app.forceTerminate()
            let gameRunning = NSWorkspace.shared.runningApplications.contains { isGame($0.bundleIdentifier) }
            if self.running == nil && !gameRunning { self.show(intro: !self.window.isVisible) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier, id == self.running else { return }
            self.gameEnded(id)
        }
        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer!, forMode: .common)
        m.readBattery()
        updateController()
        hadController = m.controller != nil
        log("started\(CommandLine.arguments.contains("--hidden") ? " (hidden)" : ""), controller: \(m.controller ?? "none")")
        if CommandLine.arguments.contains("--hidden") { NSApp.setActivationPolicy(.accessory); m.scan() } else { show() }   // hidden: the covers made now
    }

    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows f: Bool) -> Bool { if running == nil { show() }; return false }
    func applicationDidBecomeActive(_ n: Notification) {
        if window.isVisible { NSApp.presentationOptions = [.hideDock, .hideMenuBar]; setCursorHidden(true) }
    }
    func applicationDidResignActive(_ n: Notification) { if running != nil { parkPointer() }; setCursorHidden(false) }   // a game or another app in front gets its pointer back

    // MARK: showing and hiding

    func show(intro: Bool = true) {
        let wasVisible = window.isVisible
        m.scan(); m.sel = 0; m.launching = nil; m.menuOpen = false; m.now = Date(); m.readBattery()
        if !wasVisible { opening(full: intro) }
        NSApp.setActivationPolicy(.regular)
        place()
        window.level = .floating   // over the other windows even when macOS does not let this app in front
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.window.isVisible else { return }
            if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
            self.log(NSApp.isActive ? "in front" : "shown, but macOS kept another app in front (the controller works anyway)")
        }
        setCursorHidden(true)
        log("shown")
        routeAudioToTV()
        if !askedAccess {   // closing notification banners needs Accessibility: macOS asks once (System Settings › Privacy & Security › Accessibility)
            askedAccess = true
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
        log("Accessibility (to close notifications): \(AXIsProcessTrusted() ? "allowed" : "not allowed")")
        dismissNotifications()
    }

    // Closes the notification banners on screen (the top right corner), as their close button does: a controller cannot reach them.
    // Notification Center's elements with a close or clear action, in the languages the menus are in. Needs Accessibility; without it, nothing.
    let axQueue = DispatchQueue(label: "notifications")
    var axBusy = false
    // Off the main thread: reading Notification Center through Accessibility can take tens of milliseconds, a stutter on the screen each time.
    // Its windows are looked at first, and the walk runs only when one is up.
    func dismissNotifications() {
        guard !axBusy, AXIsProcessTrusted(),
              let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else { return }
        axBusy = true
        let pid = nc.processIdentifier
        axQueue.async { [weak self] in
            let closed = Self.closeBanners(pid)
            DispatchQueue.main.async { self?.axBusy = false; if closed > 0 { self?.log("closed \(closed) notification(s)") } }
        }
    }

    static func closeBanners(_ pid: pid_t) -> Int {
        let app = AXUIElementCreateApplication(pid)
        var wins: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &wins) == .success, let list = wins as? [AXUIElement], !list.isEmpty else { return 0 }
        let words = ["close", "clear", "dismiss", "cerrar", "borrar", "fermer", "effacer", "schließen", "löschen", "chiudi", "cancella", "fechar", "limpar"]
        var closed = 0
        func walk(_ e: AXUIElement, _ depth: Int) {
            guard depth < 14 else { return }
            var names: CFArray?
            if AXUIElementCopyActionNames(e, &names) == .success, let acts = names as? [String],
               let close = acts.first(where: { a in let l = a.lowercased(); return words.contains { l.contains($0) } }) {
                if AXUIElementPerformAction(e, close as CFString) == .success { closed += 1 }
                return
            }
            var kids: CFTypeRef?
            if AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &kids) == .success, let list = kids as? [AXUIElement] {
                for k in list { walk(k, depth + 1) }
            }
        }
        for w in list { walk(w, 1) }
        return closed
    }

    // The opening: the logo comes in on black, then fades out larger while the bars and the tiles come in one after another.
    // Back from a game there is no logo, only the tiles coming in.
    func opening(full: Bool) {
        m.revealed = false; m.logoIn = false; m.logo = full
        if full {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.m.logoIn = true; self.sound("Glass") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.m.logo = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { self.m.revealed = true }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.m.revealed = true }
        }
    }

    // The sound to the TV: the first audio output on HDMI or DisplayPort (a TV on a USB-C dock comes as either) becomes the Mac's output,
    // for games and for alerts. Unplugging the TV puts macOS back on the Mac's speakers by itself. defaults write io.github.vtanco.console
    // audioToTV -bool false turns it off.
    // Off the main thread: changing the output to an HDMI device makes coreaudiod set up the TV's audio, and the call waits for it (about
    // 10 s measured with an LG TV), which froze the screen, its opening and the controller. Nothing is changed when the TV is already the output.
    let audioQueue = DispatchQueue(label: "audio")
    // audioOutput: "tv" (the default), "mac" (the Mac's own speakers, as macOS often moves the output to a TV when it is plugged in, and
    // some docks pass no sound to it) or "off" (left as it is). The older audioToTV false is "off".
    func routeAudioToTV() {
        let pref = UserDefaults.standard.string(forKey: "audioOutput") ?? (UserDefaults.standard.object(forKey: "audioToTV") as? Bool == false ? "off" : "tv")
        guard pref != "off" else { return }
        audioQueue.async { [weak self] in
            let mine = pref == "mac" ? [kAudioDeviceTransportTypeBuiltIn] : [kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort]
            guard let tv = outputDevices().first(where: { mine.contains($0.2) }) else { return }
            let sys = AudioObjectID(kAudioObjectSystemObject)
            var cur = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
            var da = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            if AudioObjectGetPropertyData(sys, &da, 0, nil, &size, &cur) == noErr, cur == tv.0 { return }
            let t0 = Date()
            var id = tv.0
            for sel in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
                var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                AudioObjectSetPropertyData(sys, &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
            }
            let took = Date().timeIntervalSince(t0)
            DispatchQueue.main.async { self?.log("sound to \(tv.1) (\(String(format: "%.1f", took)) s)") }
        }
    }

    // The pointer off the picture while a game runs: to the bottom right corner of the Mac's own screen when the TV is another screen,
    // else of the only screen. The games hide it at a controller press, until the mouse moves; out of the way, a nudge does not show it on the TV.
    func parkPointer() {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return }
        let target = (screens.count > 1 ? screens.first(where: { isBuiltIn($0) }) : nil) ?? screens.first(where: { !isBuiltIn($0) }) ?? primary
        let f = target.frame
        CGWarpMouseCursorPosition(CGPoint(x: f.maxX - 1, y: primary.frame.maxY - (f.minY + 1)))   // Quartz: the top left of the primary screen is 0,0
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    func place() {   // the TV (any screen that is not the Mac's own) when there is one
        let s = NSScreen.screens.first(where: { !isBuiltIn($0) }) ?? NSScreen.main ?? NSScreen.screens[0]
        window.setFrame(s.frame, display: true)
    }

    func hide() {
        log("hidden")
        setCursorHidden(false)
        NSApp.presentationOptions = []
        window.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    func controllerConnected() {
        updateController()
        let gameRunning = NSWorkspace.shared.runningApplications.contains { isGame($0.bundleIdentifier) }
        let ok = Date().timeIntervalSince(startedAt) > 3 && Date() > quietUntil && running == nil && !gameRunning && !window.isVisible
        if !window.isVisible { log(ok ? "coming up for the controller" : "not coming up (\(Date() <= quietUntil ? "just turned off" : running != nil || gameRunning ? "a game runs" : "starting"))") }
        if ok { show() }
    }

    func updateController() {
        m.controller = GCController.controllers().first(where: { $0.extendedGamepad != nil }).map { $0.vendorName ?? $0.productCategory }
    }

    // MARK: games

    func setSettingsWindow(_ id: String, shown: Bool?) {
        CFPreferencesSetAppValue("window.show" as CFString, shown.map { $0 as CFBoolean } ?? nil, id as CFString)
        CFPreferencesAppSynchronize(id as CFString)
    }

    func launch(_ g: Game, settings: Bool = false) {
        guard running == nil else { return }
        if !settings && g.id.hasPrefix(gamePrefix) { setSettingsWindow(g.id, shown: false) }   // straight into the game with its saved settings
        var lp = m.lastPlayed; lp[g.id] = Date().timeIntervalSince1970; m.lastPlayed = lp
        running = g.id; m.launching = g; m.menuOpen = false
        sound("Pop")
        let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = true
        NSWorkspace.shared.openApplication(at: g.url, configuration: cfg) { [weak self] _, err in
            DispatchQueue.main.async {
                guard let self else { return }
                if err != nil { if g.id.hasPrefix(gamePrefix) { self.setSettingsWindow(g.id, shown: nil) }; self.running = nil; self.m.launching = nil; return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { if self.running == g.id { self.hide() } }
            }
        }
    }

    func gameEnded(_ id: String) {
        if id.hasPrefix(gamePrefix) { setSettingsWindow(id, shown: nil) }   // opened from Finder, the game shows its settings window again
        running = nil
        show(intro: false)
    }

    func homeHeld() {   // quit the game in front (⌘Q, so the game can close cleanly), then this screen comes back
        let games = NSWorkspace.shared.runningApplications.filter { isGame($0.bundleIdentifier) }
        if games.isEmpty { if !window.isVisible { show() }; return }
        sound("Pop")
        for g in games {
            if running == nil { running = g.bundleIdentifier }
            g.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { if !g.isTerminated { g.forceTerminate() } }
        }
    }

    // MARK: input

    // NSSound(named:) is one shared sound: play() while it still plays does nothing (every other move was silent), so it is restarted
    // On the audio queue too: a sound played while the output is moving to the TV waits for coreaudiod, and on the main thread that wait
    // was the freeze; queued behind the move, it plays once the TV is ready
    func sound(_ name: String) {
        audioQueue.async { if let s = NSSound(named: NSSound.Name(name)) { s.volume = 0.25; s.stop(); s.play() } }
    }

    func poll() {
        let now = Date()
        let gap = now.timeIntervalSince(lastPoll); lastPoll = now
        if window.isVisible, gap > 0.5, gap < 3600 { log(String(format: "screen held up for %.1f s", gap)) }
        if now.timeIntervalSince(m.now) >= 1 {
            m.now = now
            if Int(now.timeIntervalSince1970) % 30 == 0 { m.readBattery() }
        }
        // A controller that has appeared since the last look (once a second): as the connect notification, which a controller turned off
        // and on again does not always bring
        if window.isVisible, now.timeIntervalSince(lastDismiss) >= 2 { lastDismiss = now; dismissNotifications() }   // the ones that come while it shows
        if now.timeIntervalSince(lastCheck) >= 1 {
            lastCheck = now
            let has = GCController.controllers().contains { $0.extendedGamepad != nil }
            if has && !hadController { log("controller seen"); controllerConnected() } else if !has && hadController { updateController() }
            hadController = has
        }
        guard let ctl = GCController.controllers().first(where: { $0.extendedGamepad != nil }), let pad = ctl.extendedGamepad else { return }
        // HOME or OPTIONS (+) pressed while this screen is away and no game runs: come back (a controller left on after exiting to the desktop).
        // OPTIONS too, as macOS may keep HOME for itself (Launchpad or the Games app) and then no app sees it.
        let wake = (pad.buttonHome?.isPressed ?? false) || pad.buttonMenu.isPressed
        if wake && !prevWake && !window.isVisible && running == nil
            && !NSWorkspace.shared.runningApplications.contains(where: { isGame($0.bundleIdentifier) }) { log("HOME/OPTIONS pressed on the desktop"); show() }
        prevWake = wake
        if let home = pad.buttonHome, home.isPressed {
            if homeSince == nil { homeSince = now } else if !homeDone, now.timeIntervalSince(homeSince!) > 1.2 { homeDone = true; homeHeld() }
        } else { homeSince = nil; homeDone = false }
        // Nintendo controllers have A on the right: confirm with the right button there, with the bottom one elsewhere (the options swap them)
        let cat = (ctl.productCategory + " " + (ctl.vendorName ?? "")).lowercased()
        let nintendo = cat.contains("switch") || cat.contains("joy-con") || cat.contains("pro controller")
        let swap = nintendo != UserDefaults.standard.bool(forKey: "swapAB")
        let a = (swap ? pad.buttonB : pad.buttonA).isPressed, b = (swap ? pad.buttonA : pad.buttonB).isPressed, menu = pad.buttonMenu.isPressed
        defer { prevA = a; prevB = b; prevMenu = menu }
        // While this screen shows, the controller drives it whether or not macOS made this app the active one: an app that comes up by
        // itself (a controller connecting) is not always let in front, and the controller's input reaches it in the background anyway.
        guard window.isVisible, running == nil, !m.logo else { lastDir = 0; return }
        let x = pad.dpad.xAxis.value + pad.leftThumbstick.xAxis.value, y = pad.dpad.yAxis.value + pad.leftThumbstick.yAxis.value
        var dir = 0
        if abs(x) > 0.5, abs(x) >= abs(y) { dir = x > 0 ? 1 : -1 } else if abs(y) > 0.5 { dir = y > 0 ? 2 : -2 }
        if dir != lastDir { lastDir = dir; dirSince = now; lastRepeat = now; if dir != 0 { move(dir) } }
        else if dir != 0, now.timeIntervalSince(dirSince) > 0.4, now.timeIntervalSince(lastRepeat) > 0.11 { lastRepeat = now; move(dir) }
        if a && !prevA { confirm() }
        if b && !prevB { back() }
        if menu && !prevMenu { toggleMenu() }
    }

    func key(_ k: UInt16) {
        guard running == nil else { return }
        switch k {
        case 123: move(-1)
        case 124: move(1)
        case 126: move(2)
        case 125: move(-2)
        case 36, 76: confirm()
        case 53: if m.menuOpen { back() } else { hide() }
        case 48: toggleMenu()
        default: break
        }
    }

    func move(_ dir: Int) {   // 1 right, -1 left, 2 up, -2 down
        if m.menuOpen {
            guard abs(dir) == 2 else { return }
            let n = min(max(m.menuSel + (dir > 0 ? -1 : 1), 0), m.menuItems.count - 1)
            if n != m.menuSel { m.menuSel = n; sound("Tink") }
            return
        }
        guard abs(dir) == 1, !m.games.isEmpty else { return }
        let n = min(max(m.sel + dir, 0), m.games.count - 1)
        if n != m.sel { m.sel = n; sound("Tink") }
    }

    func confirm() {
        if m.menuOpen { menuAction(m.menuSel); return }
        if m.games.indices.contains(m.sel) { launch(m.games[m.sel]) }
    }

    func back() { if m.menuOpen { m.menuOpen = false } }

    // Turns the controller off by closing its Bluetooth connection: Xbox, PlayStation and Nintendo controllers go to sleep when the Mac lets them go.
    // The connected Bluetooth devices that are a joystick or gamepad (peripheral class 5, minor 1 or 2), or that carry a connected controller's name.
    // The first time, macOS asks to let Console use Bluetooth. A USB controller stays on (it has no connection to close).
    func turnOffController() {
        let names = GCController.controllers().compactMap { $0.vendorName?.lowercased() }.filter { !$0.isEmpty }
        quietUntil = Date().addingTimeInterval(6)
        for d in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] where d.isConnected() {
            let name = (d.name ?? "").lowercased()
            let gamepad = d.deviceClassMajor == 0x05 && [1, 2].contains(Int(d.deviceClassMinor) & 0x0F)
            if gamepad || (!name.isEmpty && names.contains(where: { name.contains($0) || $0.contains(name) })) {
                log("turning off \(d.name ?? "?"): \(d.closeConnection() == kIOReturnSuccess ? "ok" : "failed")")
            }
        }
    }

    func toggleMenu() { m.menuSel = 0; m.menuOpen.toggle() }

    func menuAction(_ i: Int) {
        switch i {
        case 0: if m.games.indices.contains(m.sel) { launch(m.games[m.sel], settings: true) }
        case 1: m.scan(); m.menuOpen = false
        case 2: UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "swapAB"), forKey: "swapAB"); m.menuOpen = false
        case 3: m.menuOpen = false; hide()
        case 4: m.menuOpen = false; turnOffController(); hide()
        case 5:
            m.menuOpen = false; turnOffController(); hide()
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = ["sleepnow"]; try? p.run()
        default: break
        }
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count { MainActor.assumeIsolated {
    let m = Model(); m.scan(); m.readBattery(); m.controller = "Xbox Wireless Controller"; m.sel = min(1, max(0, m.games.count - 1))
    if CommandLine.arguments.contains("--menu") { m.menuOpen = true; m.menuSel = 1 }
    if CommandLine.arguments.contains("--intro") { m.logo = true; m.logoIn = true }
    let r = ImageRenderer(content: HomeView(m: m, snapshot: true).frame(width: 1920, height: 1080).environment(\.colorScheme, .dark))
    r.scale = 1
    if let img = r.nsImage, let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t), let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    }
    exit(0)
} }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
