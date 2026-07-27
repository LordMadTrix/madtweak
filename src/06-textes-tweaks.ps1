# ------------------------------------------------------------------------------
# TEXTES DES TWEAKS — traductions anglaises
#
# Le FRANÇAIS n'est pas ici : il reste écrit en clair à l'appel d'Invoke-Tweak,
# pour que le code se lise sans dictionnaire. C'est aussi lui le repli.
#
# Cette table ne contient donc que l'anglais, retrouvé par la CLÉ du tweak :
#   <cle>.t  le titre         <cle>.e  l'explication
#
# Conséquence utile : traduire est ADDITIF. Un tweak absent de cette table
# s'affiche en français, sans rien casser — on peut donc avancer par lots.
#
# Règle de traduction : l'explication doit dire ce que le réglage FAIT *et CE
# QU'IL COÛTE*. Une traduction qui perd la contrepartie trahit le projet.
# ------------------------------------------------------------------------------
$script:TextesTweaks = @{

    # --- 50 : Tweaks de base ---
    'telemetrie.t' = "Disable Windows telemetry, the advertising ID and suggestions?"
    'telemetrie.e' = "Windows regularly sends Microsoft data about how you use your PC, and uses an advertising ID to target you. This setting cuts both, and removes the « suggestions » from the Start menu and Settings. On Windows Home, telemetry drops to the lowest allowed level (Required) but cannot be switched off entirely: only Windows Enterprise permits that."

    'desinstaller-onedrive.t' = "Thoroughly uninstall Microsoft OneDrive?"
    'desinstaller-onedrive.e' = "Completely removes Microsoft OneDrive from the system, stops it running and cleans up its installation files."

    'widgets-chat.t' = "Remove Widgets, the Chat icon and cut Bing out of the Start menu?"
    'widgets-chat.e' = "Removes the Widgets panel (weather and news) and the Chat/Teams icon from the taskbar, and stops the Start menu sending what you type to Bing for web results. You keep local search for your files and apps."

    'bloatwares.t' = "Uninstall the usual bloatware (TikTok, Disney+, Spotify, Weather...)?"
    'bloatwares.e' = "Removes the preinstalled apps almost nobody uses: TikTok, Disney+, Spotify, News, Weather, Solitaire, LinkedIn, Clipchamp, Skype... They are removed from your account AND from future accounts created on this PC. The Microsoft Store, Defender and Terminal are never touched: removing those would break Windows. You can reinstall anything from the Store if you change your mind."

    'apps-oem.t' = "Uninstall OEM and Xbox apps (Dolby, Xbox, Family Safety, Phone Link)?"
    'apps-oem.e' = "Kept separate from the previous list because it is debatable: keep Xbox if you use Game Pass, and Dolby if your laptop has genuine Dolby Atmos audio hardware (otherwise you would lose sound quality). « Phone Link » is what receives Android texts and notifications on the PC."

    # --- 51 : Tweaks avancés ---
    'clic-droit-classique.t' = "Restore the classic Windows 10 right-click menu?"
    'clic-droit-classique.e' = "Windows 11 replaced the right-click menu with a shortened version that hides half the options behind « Show more options ». This setting brings back the full Windows 10 menu in one go. Explorer must be restarted (offered at the end of the menu) to see it."

    'animations.t' = "Disable window animations (snappier)?"
    'animations.e' = "Removes the opening, closing and minimising animations. Nothing actually runs faster, but everything RESPONDS faster: you no longer wait for the animation to finish. Most noticeable on a modest machine."

    'desinstaller-edge.t' = "Fully uninstall Microsoft Edge? (often blocked by Microsoft, and Edge can return via Windows Update)"
    'desinstaller-edge.e' = "Completely uninstalls Microsoft Edge. Note: Microsoft tends to reinstall it during major updates."

    'qos.t' = "Free the bandwidth Windows reserves (QoS Packet Scheduler)?"
    'qos.e' = "By default Windows reserves 20% of your bandwidth for so-called priority traffic that almost no application uses. This setting lifts that reservation. The gain is real but modest: do not expect your throughput to double."

    'wer.t' = "Disable the Windows Error Reporting service (WerSvc)?"
    'wer.e' = "The error reporting service collects crash details and offers to send them to Microsoft. Turning it off frees a little memory and stops those uploads. In exchange, you lose the reports that sometimes help you understand a recurring crash."

    'tuer-applis-figees.t' = "Make Windows kill unresponsive applications instantly?"
    'tuer-applis-figees.e' = "When an application stops responding, Windows waits several seconds before offering to close it. This setting shortens that wait considerably and closes frozen apps at shutdown. Downside: an application that is merely SLOW (a large save in progress) will be killed sooner, with a risk of losing your work."

    'noyau-en-ram.t' = "Keep the Windows kernel in RAM instead of the page file? (needs at least 8 GB)"
    'noyau-en-ram.e' = "Stops Windows paging the core of the system out to disk, keeping it in memory instead. Improves responsiveness if you have RAM to spare. Automatically refused below 8 GB, where it would be counterproductive."

    'ntfs-lastaccess.t' = "Stop timestamping every file when it is read (NTFS last access)? (speeds up large folders)"
    'ntfs-lastaccess.e' = "By default Windows records the date and time on every file READ: it writes to disk even when you are only browsing. Turning it off speeds up navigating large folders. Careful: if you use incremental backups based on access time, they will be thrown off."

    'longpaths.t' = "Lift the 260-character limit on file paths (LongPaths)?"
    'longpaths.e' = "Lifts the old 260-character limit on file paths. Useful if you hit « path too long » errors copying deep folder trees. No downside: applications that cannot handle long paths simply carry on as before."

    'sudo.t' = "Enable 'sudo' for Windows? (elevate one command without opening an admin terminal)"
    'sudo.e' = "Enables the Windows « sudo » command (24H2 and later), which elevates a single command without reopening an administrator terminal. Configured in « inline » mode: the elevated command runs in your current terminal. Usage: sudo <command>."

    'demarrage-rapide.t' = "Disable Fast Startup?"
    'demarrage-rapide.e' = "Disables fast startup so Windows shuts down completely every time. Avoids driver state corruption and fixes incomplete shutdowns (fans that keep spinning, for instance)."

    'clic-droit-possession.t' = "Add « Take Ownership » to the right-click menu?"
    'clic-droit-possession.e' = "Adds a « Take Ownership » entry to the right-click menu on files and folders, so you can grant yourself modify rights easily."

    'explorer-separate-process.t' = "Isolate Explorer windows in separate processes (SeparateProcess)?"
    'explorer-separate-process.e' = "Makes Windows Explorer open each folder in its own system process. Improves stability: if one folder window crashes or freezes, it no longer takes the taskbar and desktop down with it."

    'disable-low-disk-warning.t' = "Disable low disk space warnings?"
    'disable-low-disk-warning.e' = "Disables the recurring Windows notifications warning that one of your drives or partitions is nearly full. Handy for storage drives you intend to fill on purpose."

    'disable-lock-screen.t' = "Disable the lock screen?"
    'disable-lock-screen.e' = "Disables the welcome and lock screen at startup and on lock, going straight to the sign-in and password prompt."

    'kill-timeouts.t' = "Shorten the shutdown wait (kill timeouts)?"
    'kill-timeouts.e' = "Makes Windows close and kill stubborn or frozen applications and services far quicker (2 seconds instead of 20) when they block or slow down shutdown."

    'auto-restart-shell.t' = "Restart Explorer automatically after a crash (AutoRestartShell)?"
    'auto-restart-shell.e' = "Forces Windows to relaunch the File Explorer process (taskbar, desktop) automatically if it crashes or stops unexpectedly, so you are not left staring at a black screen."

    # --- 52 : Explorateur & vie privée ---
    'explorateur-accueil.t' = "Hide 'Recent files' and 'Frequent folders' from Explorer Home?"
    'explorateur-accueil.e' = "Hides the « Recent files » and « Frequent folders » lists shown when Explorer opens. Useful if someone else can see your screen: those lists tell the story of what you opened recently."

    'extensions-fichiers.t' = "Show file extensions by default (.txt, .exe, .ps1)?"
    'extensions-fichiers.e' = "Shows each file's real extension (.txt, .exe, .ps1). Windows hides them by default, which lets « photo.jpg.exe » pass itself off as an image. As much a security setting as a convenience one."

    'taches-telemetrie.t' = "Disable the scheduled data-collection tasks (telemetry tasks)?"
    'taches-telemetrie.e' = "Disables the scheduled tasks that collect usage data in the background (Compatibility Appraiser, Customer Experience Improvement Program, UsbCeip). They run periodically without giving you anything. Their names change between Windows versions: the script resolves them at runtime rather than guessing."

    'presse-papiers.t' = "Disable cloud clipboard history?"
    'presse-papiers.e' = "Turns off clipboard history (Win+V) and its sync to your other devices via your Microsoft account. Everything you copy — including passwords — stops being remembered and uploaded. Downside: Win+V will no longer bring back what you copied ten minutes ago."

    'recherche-bing.t' = "Cut Bing/web results and 'highlights' out of Windows Search?"
    'recherche-bing.e' = "Start menu search sends what you type to Bing to show web results and « highlights ». This setting cuts all of that: search becomes purely local, faster, and never leaves your PC."

    'delivery-optimization.t' = "Stop sharing your Windows updates with other PCs over the internet (Delivery Optimization)?"
    'delivery-optimization.e' = "By default your PC HOSTS pieces of Windows updates and uploads them to strangers over the internet, using your upload bandwidth. This setting stops that sharing: updates come from Microsoft servers only."

    'autoplay.t' = "Disable AutoPlay for USB sticks and external drives?"
    'autoplay.e' = "Stops Windows automatically running or opening the contents of a USB stick or external drive the moment it is plugged in. Convenient, but above all it closes a classic infection route via a booby-trapped USB stick."

    'historique-activite.t' = "Disable activity history and its upload to Microsoft (Timeline)?"
    'historique-activite.e' = "Windows keeps a history of what you opened (the « Timeline ») and can upload it to your Microsoft account. This setting cuts all three layers at once: the feature, the local collection and the upload. Most guides disable only one and leave the others running."

    'experiences-personnalisees.t' = "Disable 'tailored experiences' based on your diagnostic data?"
    'experiences-personnalisees.e' = "Stops Microsoft using your diagnostic data to suggest tips, ads and personalised apps inside Windows. This is the per-user setting, the only one genuinely honoured on every edition, Home included."

    'feedback.t' = "Never ask for feedback again (Windows Feedback)?"
    'feedback.e' = "Windows periodically asks for your opinion through pop-up windows. This setting tells it never to ask again. No downside: you can still give feedback yourself whenever you want."

    'saisie-personnalisation.t' = "Stop the collection of your typing and handwriting (input personalisation)?"
    'saisie-personnalisation.e' = "Windows analyses what you type and handwrite to improve its suggestions, and collects your contacts' names. This setting stops that collection. In exchange, typing suggestions and handwriting recognition will become less accurate."

    'service-diagtrack.t' = "Disable the DiagTrack telemetry service (Connected User Experiences)?"
    'service-diagtrack.e' = "Cuts the service that actually sends the telemetry, instead of merely asking it politely to hold back. This is more radical than the telemetry setting — and it is what counts on Windows Home, where the level cannot drop to zero. Downside: Feedback Hub and some Microsoft Support diagnostics will stop working."

    'defender-echantillons.t' = "Stop sending file samples to Microsoft Defender?"
    'defender-echantillons.e' = "Defender sends suspicious files to Microsoft for analysis by default — so potentially YOUR files. This setting stops those uploads. Important: Defender's cloud protection stays ACTIVE. Your security is not reduced, only the sharing of your files is."

    'geolocalisation.t' = "Deny location access to every application?"
    'geolocalisation.e' = "Denies location access to every application. Only enable this if you know what you lose: Weather, Maps and « Find my device » will stop working, and the time zone will no longer set itself automatically when you travel."

    'apps-arriere-plan.t' = "Stop Store apps running in the background? (saves RAM and battery)"
    'apps-arriere-plan.e' = "Stops Store apps running in the background when you are not using them. Saves memory and battery, especially on a laptop. Downside: those apps will no longer receive push notifications while this is on."

    'bloquer-sug-store.t' = "Block the automatic install of Store-suggested apps?"
    'bloquer-sug-store.e' = "Stops Windows and the Microsoft Store silently downloading and installing suggested or partner apps and games (Candy Crush, Spotify, TikTok and the like) in the background."

    'edge-telemetrie.t' = "Disable Microsoft Edge telemetry and sponsored suggestions?"
    'edge-telemetrie.e' = "Disables browsing telemetry, personalisation and sponsored suggestions in the Microsoft Edge browser."

    'dev-telemetrie.t' = "Disable VS Code and Visual Studio telemetry?"
    'dev-telemetrie.e' = "Disables the background upload of usage, diagnostic and user-experience data in VS Code (by editing the user settings.json) and in Visual Studio (via machine policy)."

    'browsers-telemetrie.t' = "Disable Google Chrome and Mozilla Firefox telemetry?"
    'browsers-telemetrie.e' = "Disables telemetry, usage reporting and built-in experimental studies in Chrome and Firefox through machine registry policies."

    'office-telemetrie.t' = "Disable Microsoft Office telemetry?"
    'office-telemetrie.e' = "Disables background feedback, diagnostics and client telemetry in the Microsoft Office suite."

    'disable-web-search-start.t' = "Disable Bing web search in the Start menu?"
    'disable-web-search-start.e' = "Disables Bing search in the local search box of the taskbar and Start menu. Stops everything you type locally to find an app or a file from being sent online to Bing."

    'thirdparty-telemetrie.t' = "Disable auto-start and telemetry of third-party services (Google Update, Adobe)?"
    'thirdparty-telemetrie.e' = "Configures Adobe (Adobe Update, Genuine Integrity) and Google Update's update and telemetry services so they do not start automatically in the background when the PC boots."

    # --- 53 : Matériel & réseau ---
    'nvidia-telemetrie.t' = "Disable the hidden NVIDIA graphics telemetry?"
    'nvidia-telemetrie.e' = "The NVIDIA driver installs a service and scheduled tasks that report usage data back to NVIDIA. Neither the driver nor your games need them. No effect if you have no NVIDIA card."

    'sysmain.t' = "Disable SysMain / Superfetch? (good on SSD - AVOID on a mechanical hard drive)"
    'sysmain.e' = "SysMain (formerly Superfetch) preloads into memory the applications it thinks you are about to open. On an SSD that guesswork is pointless and sometimes causes stutter. On a mechanical HARD DRIVE, however, it genuinely helps: the script checks your system drive and refuses the setting if it is a hard drive."

    'usb-suspension.t' = "Disable USB selective suspend? (prevents disconnections)"
    'usb-suspension.e' = "Windows cuts power to idle USB ports to save energy, which causes mice, keyboards, headsets or external drives to drop out. This setting stops it. On a desktop it is all upside; on a LAPTOP it costs battery life."

    'net-crawling.t' = "Disable automatic scanning for shared network folders?"
    'net-crawling.e' = "Stops Explorer automatically going looking for shared folders on your local network. Purely cosmetic: it avoids lag when Explorer opens. You can still reach your shares by typing their address."

    'hibernation.t' = "Disable hibernation and reclaim the hiberfil.sys space? (also disables Fast Startup)"
    'hibernation.e' = "Disables hibernation and deletes hiberfil.sys, a hidden file several GB in size. WARNING: this also disables « fast startup », so your PC will boot more slowly. On a laptop it is a bad idea: you lose the hibernation that saves your session when the battery runs out."

    'nagle.t' = "Disable Nagle's algorithm? (lowers gaming latency, may reduce download throughput)"
    'nagle.e' = "Nagle's algorithm bundles small network packets before sending them, which adds a few milliseconds of latency. Disabling it helps in online gaming. Real downside: it can REDUCE your download throughput. Only take it if latency matters more than bandwidth."

    'souris-acceleration.t' = "Disable mouse acceleration ('enhance pointer precision')? (consistent aim in games)"
    'souris-acceleration.e' = "Windows accelerates the pointer when you move the mouse quickly: the same gesture does not always travel the same distance. Turning it off makes your aim consistent, which is what every gamer wants. Expect an adjustment period: your in-game sensitivity will change. Takes effect at your next sign-in."

    'spouleur.t' = "Disable the print spooler? (closes a known attack surface)"
    'spouleur.e' = "The print spooler is a known attack surface (the PrintNightmare family of flaws) and runs permanently even without a printer. The script first checks that no real printer is installed and refuses if it finds one: without the spooler, printing becomes impossible."

    'llmnr-netbios.t' = "Disable LLMNR and NetBIOS? (closes two classic local-network attack surfaces)"
    'llmnr-netbios.e' = "LLMNR and NetBIOS are used to find machines on the local network when DNS fails. They are exploited by classic local-network spoofing attacks (Responder and friends), and a home PC with working DNS has no need for them. Downside: if you reach an old NAS or a share by name and it breaks, undo this setting."

    'doh.t' = "Allow encrypted DNS (DNS over HTTPS)?"
    'doh.e' = "Lets Windows encrypt your DNS queries (DNS over HTTPS), so your ISP no longer sees in the clear which sites you visit. Set to « allowed » rather than « required »: Windows encrypts if your DNS server supports it, and falls back to plaintext otherwise. « Required » with a DNS that lacks DoH would cut you off from the internet. Only effective with a compatible DNS (Cloudflare, Google, Quad9)."

    'carte-reseau-veille.t' = "Stop Windows powering down the network adapter to save energy? (Wi-Fi drops, latency)"
    'carte-reseau-veille.e' = "Windows powers down the network adapter to save energy, which causes Wi-Fi drops and latency spikes. This setting forbids it, on your physical adapters only (VPN virtual adapters are left alone). On a LAPTOP it costs battery life."

    'game-dvr.t' = "Disable Game DVR / Game Bar background recording? (FPS gain)"
    'game-dvr.e' = "The Game Bar records your game in the background permanently, in case you want to keep the last 30 seconds. That costs FPS for a feature few people use. The Game Bar (Win+G) stays usable: only background recording is cut."

    'plan-performances-ultimes.t' = "Enable the hidden 'Ultimate Performance' power plan?"
    'plan-performances-ultimes.e' = "Adds Microsoft's hidden power plan, which forbids any component from going to sleep. Reserved for DESKTOPS: the script refuses it on a laptop, where Microsoft hides it for good reason — it runs hot and drains the battery. Once added, you must select it in Settings > System > Power."

    'bridage-multimedia.t' = "Lift the network throttling reserved for multimedia (NetworkThrottlingIndex)?"
    'bridage-multimedia.e' = "Windows throttles the network and CPU priorities to reserve resources for multimedia, a trade-off designed for 2008-era machines. This setting lifts the throttle. Useful for gaming and streaming; no visible effect in office use."

    'modern-standby.t' = "Disable modern standby (S0) and restore classic S3 sleep?"
    'modern-standby.e' = "Forces classic S3 sleep instead of modern standby S0. RESERVED for machines whose firmware GENUINELY supports S3: on a laptop designed for S0 (most recent ROG models), forcing S3 causes crashes on wake and on RESUME FROM HIBERNATION. The tweak detects this and REFUSES to apply."

    'hags-gpu.t' = "Enable hardware-accelerated GPU scheduling (HAGS)?"
    'hags-gpu.e' = "Enables hardware-accelerated GPU scheduling to reduce display latency and improve performance in compatible games (required for Nvidia DLSS 3 / AMD FSR 3 frame generation)."

    'amd-telemetrie.t' = "Disable AMD Radeon Software telemetry?"
    'amd-telemetrie.e' = "Disables telemetry and analytics collection in AMD Radeon Software."

    'pcie-power-management.t' = "Disable PCIe power saving (Link State Power Management)?"
    'pcie-power-management.e' = "Configures the active power plan to disable PCIe Link State power management. Stops graphics cards and NVMe SSDs having their power reduced, eliminating wake-up micro-stutters."

    'xbox-gamebar.t' = "Disable Xbox Game Bar background features?"
    'xbox-gamebar.e' = "Disables background recording and the Xbox Game Bar app to free CPU and memory while gaming."

    'delivery-optimization-p2p.t' = "Disable P2P sharing of Windows Update downloads (Delivery Optimization)?"
    'delivery-optimization-p2p.e' = "Configures Windows to fetch Windows Update packages directly from Microsoft servers (HTTP) without using or sharing your upload bandwidth with other computers on the local network or the internet."

    'ntfs-performance.t' = "Disable 8.3 short-name creation (NTFS performance)?"
    'ntfs-performance.e' = "Disables the generation of DOS-style 8.3 short filenames on NTFS. Improves read/write performance, especially in directories holding very large numbers of files."

    # --- 61 : Apparence & visuel ---
    'mode-sombre.t' = "Enable DARK mode (Windows and apps)?"
    'mode-sombre.e' = "Switches Windows and applications to the dark theme. BOTH settings are written: one dresses the apps, the other the taskbar and Start menu. Many guides set only one and leave you with a half-dark theme."

    'transparence.t' = "Disable transparency effects (Acrylic / Mica)?"
    'transparence.e' = "Turns off the transparency effects (Acrylic, Mica) on windows and the Start menu. Unlike the other settings in this tab, this one genuinely affects performance: transparency costs GPU time, which matters on a laptop with integrated graphics."

    'accent-barres-titre.t' = "Apply your accent colour to title bars and borders?"
    'accent-barres-titre.e' = "Applies your accent colour to window title bars and borders. Without this setting they stay grey whatever colour you pick in Settings. The colour used is the one from Settings > Personalisation > Colours."

    'qualite-fond-ecran.t' = "Improve wallpaper quality (no JPEG recompression)?"
    'qualite-fond-ecran.e' = "Windows recompresses your wallpaper to roughly 85% quality, which shows on gradients and flat areas. This setting switches to maximum quality. Only effective when you SET a wallpaper again: the current one is already recompressed."

    'fichiers-caches.t' = "Show HIDDEN files and folders?"
    'fichiers-caches.e' = "Shows files and folders marked as hidden. Handy for reaching AppData or a .gitignore without a detour. Harmless: these are mostly configuration files."

    'fichiers-systeme.t' = "Also show protected SYSTEM files? (pagefile.sys, hiberfil.sys...)"
    'fichiers-systeme.e' = "ALSO shows protected system files (pagefile.sys, hiberfil.sys, bootmgr). Only take this if you know what you are doing: these files are hidden for a reason, and deleting one can leave Windows unbootable."

    'explorateur-ce-pc.t' = "Open Explorer on « This PC » rather than « Home »?"
    'explorateur-ce-pc.e' = "Explorer opens on « This PC » (your drives) instead of « Home », the Windows 11 page that mixes recent files with OneDrive files."

    'explorateur-compact.t' = "Enable COMPACT view in Explorer (tighter rows, like Windows 10)?"
    'explorateur-compact.e' = "Tightens the spacing between Explorer rows, as in Windows 10. Windows 11 spaces everything out for touch; on a desktop screen that just makes you scroll for nothing."

    'explorateur-galerie.t' = "Remove « Gallery » from the Explorer navigation pane?"
    'explorateur-galerie.e' = "Removes the « Gallery » entry from the Explorer navigation pane. It is a photo view added in 23H2, redundant with the Photos app. Reversible: the script exports the key before deleting it, so Exact restore can put it back."

    'explorateur-volet-accueil.t' = "Remove « Home » from the Explorer navigation pane?"
    'explorateur-volet-accueil.e' = "Removes the « Home » entry from the navigation pane. Explorer will automatically fall back to « This PC » on opening: it cannot open on a location that no longer exists."

    'suffixe-raccourci.t' = "Remove the « - Shortcut » suffix on new shortcuts?"
    'suffixe-raccourci.e' = "Windows appends « - Shortcut » to the name of every new shortcut. This setting stops that. It does not rename existing shortcuts: only new ones are affected."

    'recherche-barre-taches.t' = "Shrink the taskbar search box to a single icon?"
    'recherche-barre-taches.e' = "Shrinks the large taskbar search box to a single icon, freeing a lot of room. To hide it entirely: right-click the taskbar > Search > Hide."

    'bouton-vue-taches.t' = "Hide the « Task view » button from the taskbar?"
    'bouton-vue-taches.e' = "Hides the « Task view » button from the taskbar. The Win+Tab shortcut keeps working: only the button disappears."

    'horloge-secondes.t' = "Show SECONDS in the taskbar clock?"
    'horloge-secondes.e' = "Shows seconds in the taskbar clock. Microsoft removed it to save battery: on a laptop the clock redraws every second, which has a real if small cost. Negligible on a desktop."

    'demarrer-plus-epingles.t' = "Show MORE pins and less « Recommended » in the Start menu?"
    'demarrer-plus-epingles.e' = "Enlarges the pinned apps area of the Start menu at the expense of the « Recommended » area. Best combined with cutting the Start menu ads, in the Windows 11 tab."

    'aero-shake.t' = "Disable Aero Shake (shaking a window minimises all others)?"
    'aero-shake.e' = "Disables Aero Shake, the feature that minimises all your other windows when you shake the top one. Mostly useful if you trigger it by accident while moving a window."

    'snap-layouts.t' = "Disable the Snap Layouts flyout?"
    'snap-layouts.e' = "Disables the flyout menu that pops up when you hover the Maximise button. Snapping keeps working normally (Win+arrows, drag to an edge): only the automatic menu disappears."

    'barres-defilement.t' = "Keep scrollbars always visible (instead of letting them fade out)?"
    'barres-defilement.e' = "Keeps scrollbars permanently visible instead of having them fade out and reappear on hover. You always see where you are in a page, and you can aim at the bar without making it appear first."

    'photo-classique.t' = "Restore the classic Windows Photo Viewer?"
    'photo-classique.e' = "Brings back the old, very fast and lightweight Windows Photo Viewer from Windows 7/8. Associates JPG, JPEG, PNG, GIF, BMP, TIFF and ICO files with it."

    'god-mode.t' = "Add the « God Mode » shortcut to the Desktop?"
    'god-mode.e' = "Creates a special « full Control Panel » folder (God Mode) on your Desktop gathering more than 200 Windows administration and settings tools in one place."

    'menu-delay.t' = "Remove the menu display delay (MenuShowDelay)?"
    'menu-delay.e' = "Reduces the delay before menus appear on hover (from 400 ms by default to 20 ms). Makes submenus and context menus appear instantly, improving the overall feeling of responsiveness."

    'disable-login-blur.t' = "Disable the background blur on the sign-in screen?"
    'disable-login-blur.e' = "Disables the acrylic blur Windows applies to the background image of the password screen, for a sharp and more responsive display."

    # --- 54 : Mises à jour, sécurité & IA ---
    'copilot.t' = "Disable Windows Copilot?"
    'copilot.e' = "Removes the Copilot button and sets the policy that disables it. Since that old policy does not cover the modern Copilot shipped from 24H2 onwards (now a plain Store app), the script also UNINSTALLS that app: it is the only reliable way. You can reinstall it from the Store."

    'recall.t' = "Disable Recall and AI data analysis?"
    'recall.e' = "Recall periodically captures your screen and indexes it so you can « go back in time ». This setting disables it, removes its files and deletes the snapshots already recorded. On a Copilot+ PC, where Recall is a genuine Windows feature, the component is removed outright (restart required)."

    'update-defer.t' = "Defer feature updates by 365 days (security fixes keep arriving)?"
    'update-defer.e' = "Defers feature updates by 365 days to keep the system stable. Critical security fixes keep arriving. Requires Windows Pro edition."

    'update-block.t' = "Completely disable the Windows Update service?"
    'update-block.e' = "Disables and fully blocks the Windows Update service (wuauserv). Warning: no security fix will be able to install."

    'update-restore.t' = "Restore the default Windows Update settings?"
    'update-restore.e' = "Puts the Windows Update service settings back to their defaults."

    'vbs-desactiver.t' = "Disable virtualisation-based security (VBS) / Core Isolation?"
    'vbs-desactiver.e' = "Disables VBS and core isolation to improve gaming and GPU compute performance. Reduces overall system security."

    'update-pilotes.t' = "Stop Windows Update installing or updating drivers?"
    'update-pilotes.e' = "Stops Windows Update automatically overwriting your hardware drivers (such as Nvidia/AMD graphics drivers) with generic or older versions of its own choosing. You will have to update your drivers manually."

    'regback-backup.t' = "Enable periodic Windows Registry backups (RegBack)?"
    'regback-backup.e' = "Configures Windows to make regular automatic registry backups into System32\config\RegBack (disabled by default by Microsoft to save 50 MB of disk). Adds a safety margin should the registry become corrupted."

    'defender-cpu-limit.t' = "Cap Windows Defender CPU usage during scans?"
    'defender-cpu-limit.e' = "Caps Windows Defender's maximum CPU usage at 30% during its automatic background scans. Avoids temperature spikes and sudden slowdowns while you are gaming or working."

    # --- 57 : Windows 11 24H2+ ---
    'pubs-demarrer.t' = "Remove ads and 'recommendations' from the Start menu? (24H2+)"
    'pubs-demarrer.e' = "The Start menu shows « recommendations » that are really ads for Store apps, mixed in with your recent files and applications. This setting cuts all three. The Recommended area will empty out: see the « more pins » setting in the Appearance tab to reclaim the space."

    'pubs-scoobe.t' = "Cut the 'Let's finish setting up your device' screens after updates?"
    'pubs-scoobe.e' = "After every major update, Windows shows a full-page « Let's finish setting up your device » screen pushing you towards Edge, Bing and OneDrive. This setting stops it appearing."

    'pubs-explorateur.t' = "Remove OneDrive/Store ads disguised as notifications in Explorer?"
    'pubs-explorateur.e' = "Explorer shows banners that look like system notifications but are advertisements for OneDrive and Microsoft 365. This setting removes them. If you genuinely use OneDrive, you also lose its sync notifications."

    'pubs-verrouillage.t' = "Cut lock screen ads and Spotlight?"
    'pubs-verrouillage.e' = "The lock screen (Windows Spotlight) shows attractive photos accompanied by suggestions and advertisements. This setting cuts the advertising overlays."

    'widgets-dsh.t' = "Fully disable Widgets? ('Dsh' policy, the one that works since 24H2)"
    'widgets-dsh.e' = "Fully disables the Widgets panel. This is the policy that actually works from 24H2 onwards: the old « Windows Feeds » key that most guides recommend no longer even exists."

    'barre-taches-gauche.t' = "Align the taskbar LEFT (like Windows 10)?"
    'barre-taches-gauche.e' = "Aligns the taskbar to the left, as in Windows 10 and every earlier version, instead of the Windows 11 centring. Purely a matter of habit."

    'fin-de-tache.t' = "ADD 'End task' to the taskbar right-click menu? (kill an app without Task Manager)"
    'fin-de-tache.e' = "Adds « End task » to the right-click menu on a taskbar icon, so you can kill a frozen application without opening Task Manager. This one ENABLES a useful feature rather than cutting one."

    'panneau-telephone.t' = "Hide the 'Phone' panel from the Start menu? (new in 25H2)"
    'panneau-telephone.e' = "Hides the « Phone » panel added to the Start menu by 25H2. Undocumented by Microsoft and found by the community: if it reappears after an update, the key has changed."

    'paint-ia.t' = "Disable Paint's AI features (Cocreator, Generative fill, Image Creator)?"
    'paint-ia.e' = "Disables Paint's generative AI features (Cocreator, Generative fill, Image Creator). Paint keeps working normally for everything else."

    'click-to-do.t' = "Disable 'Click to Do' (AI screen analysis)?"
    'click-to-do.e' = "Click to Do analyses your screen contents with AI to offer contextual actions. Honestly: Microsoft only documents this policy for Insider builds, so its effect on a stable release is not guaranteed. It is set as a precaution. The feature only runs on Copilot+ PCs with an NPU anyway."

    # --- 55 : Logiciels (winget) ---
    'winget-export.t' = "EXPORT the list of apps installed on this PC (to reinstall them elsewhere)?"
    'winget-export.e' = "Exports the list of all your currently installed applications as JSON into the data folder."

    'winget-import.t' = "IMPORT and reinstall apps from a previous export?"
    'winget-import.e' = "Automatically imports and reinstalls your applications from a previously exported mes-apps.json file."

    'winget-upgrade-all.t' = "Update ALL installed apps (winget upgrade --all)?"
    'winget-upgrade-all.e' = "Automatically updates every application installed on the machine using winget."

    # --- 56 : Maintenance ---
    'maintenance-dism.t' = "Run DISM to repair the Windows system image? (several minutes)"
    'maintenance-dism.e' = "Scans the Windows system image for damage and repairs it by downloading healthy files through Windows Update (internet required)."

    'maintenance-sfc.t' = "Run an SFC scan to repair corrupted system files? (several minutes)"
    'maintenance-sfc.e' = "Scans all protected Windows system files and replaces corrupted versions with healthy copies."

    'maintenance-winsxs-cleanup.t' = "Clean and compress the component store (WinSxS)? (several minutes)"
    'maintenance-winsxs-cleanup.e' = "Runs the DISM cleanup with StartComponentCleanup and ResetBase. Permanently removes old system component versions made obsolete or superseded by recent updates. Frees a lot of space in C:\Windows\WinSxS, but makes the updates currently installed impossible to uninstall."

    'maintenance-purger-journaux.t' = "Purge every Windows event log?"
    'maintenance-purger-journaux.e' = "Empties all the Windows Event Viewer logs to free space."

    # --- 59 : Nettoyage disque ---
    'nettoyage-temp-user.t' = "Empty the temporary files (user account)"
    'nettoyage-temp-user.e' = "Empties the current user account's temporary folder (TEMP). Frees disk space."

    'nettoyage-temp-system.t' = "Empty the temporary files (Windows system)"
    'nettoyage-temp-system.e' = "Empties the Windows system temporary folder (System Temp) used by services and installers."

    'nettoyage-update-cache.t' = "Empty the Windows Update cache"
    'nettoyage-update-cache.e' = "Deletes the installers and temporary files of Windows updates already applied."

    'nettoyage-wer.t' = "Empty the Windows Error Reporting files (WER)"
    'nettoyage-wer.e' = "Deletes crash report files and system memory dumps."

    'nettoyage-delivery-optimization.t' = "Empty the Delivery Optimization cache"
    'nettoyage-delivery-optimization.e' = "Deletes the temporary files used for peer-to-peer distribution of updates."

    'nettoyage-miniatures.t' = "Empty the Explorer thumbnail cache"
    'nettoyage-miniatures.e' = "Deletes the thumbnail cache files (rebuilt automatically as you browse)."

    'nettoyage-windows-old.t' = "Delete the Windows.old rollback folder"
    'nettoyage-windows-old.e' = "Permanently deletes the Windows.old folder holding the previous system installation (gives up the ability to roll back)."

    # --- 60 : Démarrage & services ---
    'delai-demarrage.t' = "Remove the artificial 10 s delay before startup programs launch?"
    'delai-demarrage.e' = "Windows deliberately delays your startup programs by 10 seconds to make the desktop usable sooner. On an SSD that delay no longer serves a purpose. Affects YOUR programs only, not Windows services."

    'service-fax.t' = "Disable the Fax service?"
    'service-fax.e' = "The Fax service is loaded on every Windows installation, including the millions of PCs that have never seen a modem. No downside, unless you genuinely send faxes."

    'service-registre-distant.t' = "Disable Remote Registry? (attack surface, useless outside a company)"
    'service-registre-distant.e' = "Lets another machine read and modify your registry remotely. It is an attack surface, and it is useless outside a corporate network. Windows already leaves it disabled by default on a home PC."

    'service-retaildemo.t' = "Disable retail demo mode (RetailDemo)?"
    'service-retaildemo.e' = "Retail demo mode is for PCs on display in a shop. On your machine it will never do anything useful."

    'service-cartes.t' = "Disable offline map downloads (MapsBroker)?"
    'service-cartes.e' = "MapsBroker handles offline map downloads. Useless if you do not use the Maps app. Downside: it will no longer be able to download maps for offline use."

    'service-bluetooth.t' = "Disable Bluetooth? (only if this PC has NO Bluetooth device)"
    'service-bluetooth.e' = "Turns off the Bluetooth service. Only take this if this PC has no Bluetooth device: the script detects active devices and refuses if it finds any, since your keyboard, mouse or headset would stop working after a restart."

    'service-search.t' = "Disable Windows Search file indexing (WSearch)?"
    'service-search.e' = "Disables the Windows Search file indexing service. Recommended on machines with a good SSD, to save RAM and pointless disk activity. Explorer's search keeps working, but directly, without a prebuilt index."
}
