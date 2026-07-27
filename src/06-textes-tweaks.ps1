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
}
