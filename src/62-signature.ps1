# ------------------------------------------------------------------------------
# SIGNATURE — fonds d'écran « MadTrix » générés à la volée
#
# Aucune image n'est stockée dans le script : ce serait des mégaoctets de binaire
# encodés en base64, à contre-courant de tout le reste. À la place, le fond est
# DESSINÉ par du code (WPF, le même moteur que l'interface), régénéré à la
# résolution réelle de l'écran au moment où tu le demandes. Le script reste un
# seul fichier texte, et le rendu est net sur n'importe quel écran.
#
# WPF exige un thread STA : powershell.exe le fournit. Sous un hôte non-STA (rare
# en console), la génération lève, et on le dit au lieu de planter.
# ------------------------------------------------------------------------------

function Get-ResolutionPhysique {
    # La résolution « logique » (Screen.Bounds) est réduite quand Windows applique
    # une mise à l'échelle (150 % ici). Pour un fond NET, on veut la résolution
    # physique réelle, que seul GetDeviceCaps expose.
    try {
        Add-Type -Namespace MadTweak -Name Ecran -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
[DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
[DllImport("gdi32.dll")]  public static extern int GetDeviceCaps(IntPtr h, int i);
'@ -ErrorAction SilentlyContinue
        $dc = [MadTweak.Ecran]::GetDC([IntPtr]::Zero)
        try {
            $l = [MadTweak.Ecran]::GetDeviceCaps($dc, 118)  # DESKTOPHORZRES
            $h = [MadTweak.Ecran]::GetDeviceCaps($dc, 117)  # DESKTOPVERTRES
        }
        finally { [MadTweak.Ecran]::ReleaseDC([IntPtr]::Zero, $dc) | Out-Null }
        if ($l -ge 640 -and $h -ge 480) { return @{ L = $l; H = $h } }
    }
    catch { }
    # Repli : résolution logique, ou 1920x1080 en dernier recours.
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        if ($b.Width -ge 640) { return @{ L = $b.Width; H = $b.Height } }
    }
    catch { }
    return @{ L = 1920; H = 1080 }
}

# --- Petites fabriques WPF (préfixe Sig- pour ne heurter aucun autre nom) ------
function New-SigPinceau { param([string]$Hex)
    New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Hex))
}
function New-SigGlow { param([string]$Couleur = "#FFE01008", [double]$Rayon = 40, [double]$Opacite = 1)
    $e = New-Object System.Windows.Media.Effects.DropShadowEffect
    $e.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($Couleur)
    $e.BlurRadius = $Rayon; $e.ShadowDepth = 0; $e.Opacity = $Opacite
    $e
}
function New-SigCanvas { param([int]$L, [int]$H)
    $c = New-Object System.Windows.Controls.Canvas; $c.Width = $L; $c.Height = $H; $c
}
function Add-SigTexte {
    param($Canvas, [string]$Texte, [double]$Taille, [string]$Police, [string]$CouleurHex,
          [double]$X, [double]$Y, $Effet = $null, [double]$Opacite = 1, [string]$Poids = "Bold")
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Texte
    $tb.FontFamily = New-Object System.Windows.Media.FontFamily $Police
    $tb.FontSize = $Taille
    $tb.FontWeight = [System.Windows.FontWeights]::$Poids
    $tb.Foreground = New-SigPinceau $CouleurHex
    $tb.Opacity = $Opacite
    if ($Effet) { $tb.Effect = $Effet }
    [System.Windows.Controls.Canvas]::SetLeft($tb, $X)
    [System.Windows.Controls.Canvas]::SetTop($tb, $Y)
    $Canvas.Children.Add($tb) | Out-Null
    $tb
}
function Add-SigLigne {
    param($Canvas, [double]$X1, [double]$Y1, [double]$X2, [double]$Y2, $Pinceau, [double]$Epaisseur = 3, $Effet = $null)
    $ln = New-Object System.Windows.Shapes.Line
    $ln.X1 = $X1; $ln.Y1 = $Y1; $ln.X2 = $X2; $ln.Y2 = $Y2
    $ln.Stroke = $Pinceau; $ln.StrokeThickness = $Epaisseur
    if ($Effet) { $ln.Effect = $Effet }
    $Canvas.Children.Add($ln) | Out-Null
}
function Add-SigFond {
    param($Canvas, [int]$L, [int]$H, [string]$Centre, [string]$Bord)
    $r = New-Object System.Windows.Shapes.Rectangle; $r.Width = $L; $r.Height = $H
    $g = New-Object System.Windows.Media.RadialGradientBrush
    $g.GradientOrigin = [System.Windows.Point]::new(0.5, 0.42)
    $g.Center = [System.Windows.Point]::new(0.5, 0.42)
    $g.RadiusX = 0.75; $g.RadiusY = 0.85
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($Centre), 0)))
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($Bord), 1)))
    $r.Fill = $g
    $Canvas.Children.Add($r) | Out-Null
}
function Add-SigGrille {
    param($Canvas, [int]$L, [int]$H, [int]$Pas, [string]$Couleur)
    $p = New-SigPinceau $Couleur
    for ($x = 0; $x -le $L; $x += $Pas) { Add-SigLigne $Canvas $x 0 $x $H $p 1 }
    for ($y = 0; $y -le $H; $y += $Pas) { Add-SigLigne $Canvas 0 $y $L $y $p 1 }
}
function Add-SigPluie {
    # Pluie de code façon Matrix. Graine fixe = signature reproductible. Les couleurs
    # viennent de la palette (dérivée d'une couleur de base), pour un fond assorti au thème.
    param($Canvas, [int]$L, [int]$H, [int]$Graine, [hashtable]$Palette)
    $rand = New-Object System.Random $Graine
    $glyphes = @()
    0x30A0..0x30FF | ForEach-Object { $glyphes += [char]$_ }   # katakana
    "0123456789ABCDEF".ToCharArray() | ForEach-Object { $glyphes += $_ }
    $taille = 22; $pas = 26
    for ($x = 10; $x -lt $L; $x += $pas) {
        $depart = $rand.Next(-40, $H); $long = $rand.Next(8, 34)
        for ($i = 0; $i -lt $long; $i++) {
            $y = $depart - $i * $taille
            if ($y -lt -$taille -or $y -gt $H) { continue }
            $g = $glyphes[$rand.Next(0, $glyphes.Count)]
            if ($i -eq 0) { $c = $Palette.RainHead; $o = 1.0 }
            elseif ($i -lt 3) { $c = $Palette.RainMid; $o = 0.95 }
            else { $c = $Palette.RainBody; $o = [Math]::Max(0.08, 0.9 - $i * 0.04) }
            Add-SigTexte $Canvas "$g" $taille "Consolas" $c $x $y $null $o "Normal" | Out-Null
        }
    }
}
function Add-SigCrochets {
    param($Canvas, [int]$L, [int]$H, [int]$Marge, [int]$Taille, [string]$Couleur)
    $p = New-SigPinceau $Couleur; $e = New-SigGlow $Couleur 10 0.8
    $ga = $Marge; $dr = $L - $Marge; $ht = $Marge; $bs = $H - $Marge
    Add-SigLigne $Canvas $ga $ht ($ga + $Taille) $ht $p 3 $e; Add-SigLigne $Canvas $ga $ht $ga ($ht + $Taille) $p 3 $e
    Add-SigLigne $Canvas $dr $ht ($dr - $Taille) $ht $p 3 $e; Add-SigLigne $Canvas $dr $ht $dr ($ht + $Taille) $p 3 $e
    Add-SigLigne $Canvas $ga $bs ($ga + $Taille) $bs $p 3 $e; Add-SigLigne $Canvas $ga $bs $ga ($bs - $Taille) $p 3 $e
    Add-SigLigne $Canvas $dr $bs ($dr - $Taille) $bs $p 3 $e; Add-SigLigne $Canvas $dr $bs $dr ($bs - $Taille) $p 3 $e
}
function Add-SigNom {
    # « MadTrix » + filet + « R O G » + tagline, centrés. Taille proportionnelle à
    # la largeur pour rester juste sur toutes les résolutions. Couleurs = palette.
    param($Canvas, [int]$L, [int]$H, [hashtable]$Palette)
    $cx = $L / 2; $cy = $H / 2
    $tailleNom = [Math]::Round($L * 0.094)   # ~240 px sur 2560
    $halo = Add-SigTexte $Canvas "MadTrix" $tailleNom "Segoe UI Black" $Palette.Glow 0 0 (New-SigGlow $Palette.Halo ($tailleNom*0.38) 0.9) 0.9 "Black"
    $halo.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    $w = $halo.DesiredSize.Width; $h = $halo.DesiredSize.Height
    [System.Windows.Controls.Canvas]::SetLeft($halo, $cx - $w/2); [System.Windows.Controls.Canvas]::SetTop($halo, $cy - $h/2)
    Add-SigTexte $Canvas "MadTrix" $tailleNom "Segoe UI Black" $Palette.NomNet ($cx - $w/2) ($cy - $h/2) (New-SigGlow $Palette.Glow ($tailleNom*0.1) 1) 1 "Black" | Out-Null

    $filet = New-Object System.Windows.Shapes.Rectangle
    $filet.Width = $w * 0.9; $filet.Height = [Math]::Max(3, $L*0.0016)
    $filet.Fill = New-SigPinceau $Palette.Filet; $filet.Effect = New-SigGlow $Palette.Glow 16 1
    [System.Windows.Controls.Canvas]::SetLeft($filet, $cx - ($w*0.9)/2)
    [System.Windows.Controls.Canvas]::SetTop($filet, $cy + $h/2 - 10)
    $Canvas.Children.Add($filet) | Out-Null

    $rog = Add-SigTexte $Canvas "R  O  G" ($tailleNom*0.19) "Bahnschrift" $Palette.Rog 0 0 (New-SigGlow $Palette.Glow 18 0.9) 1 "SemiBold"
    $rog.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    [System.Windows.Controls.Canvas]::SetLeft($rog, $cx - $rog.DesiredSize.Width/2)
    [System.Windows.Controls.Canvas]::SetTop($rog, $cy + $h/2 + 8)

    $tag = Add-SigTexte $Canvas "// REPUBLIC OF GAMERS  -  SYSTEME OPTIMISE" ($tailleNom*0.083) "Consolas" $Palette.Tagline 0 0 $null 0.85 "Normal"
    $tag.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    [System.Windows.Controls.Canvas]::SetLeft($tag, $cx - $tag.DesiredSize.Width/2)
    [System.Windows.Controls.Canvas]::SetTop($tag, $cy + $h/2 + 8 + $rog.DesiredSize.Height + 14)
}

function ConvertTo-HexSig {
    param([int]$R, [int]$G, [int]$B, [string]$Alpha = "FF")
    "#{0}{1:X2}{2:X2}{3:X2}" -f $Alpha,
        [int][Math]::Min(255, [Math]::Max(0, $R)),
        [int][Math]::Min(255, [Math]::Max(0, $G)),
        [int][Math]::Min(255, [Math]::Max(0, $B))
}

function Get-PaletteSignature {
    # Dérive TOUTES les couleurs du fond à partir d'une seule couleur de base.
    # C'est ce qui permet un fond assorti à chaque thème sans dupliquer le dessin.
    param([Parameter(Mandatory)][string]$Base)   # "#RRGGBB" ou "#AARRGGBB"
    $col = [System.Windows.Media.ColorConverter]::ConvertFromString($Base)
    $r = [int]$col.R; $g = [int]$col.G; $b = [int]$col.B
    $tint  = { param($t) $n = Get-Nuance $r $g $b (1 + $t); ConvertTo-HexSig $n[0] $n[1] $n[2] }
    $shade = { param($s) $n = Get-Nuance $r $g $b (1 - $s); ConvertTo-HexSig $n[0] $n[1] $n[2] }
    # Tagline : version douce, mélangée vers un gris moyen.
    $tag = ConvertTo-HexSig ([int]($r*0.45 + 144*0.55)) ([int]($g*0.45 + 144*0.55)) ([int]($b*0.45 + 144*0.55))
    @{
        FondCentre = (& $shade 0.88)                 # fond radial : centre très sombre teinté
        FondBord   = "#FF040405"                     # bords quasi noirs
        RainHead   = (& $tint 0.85)                  # tête de goutte : presque blanche
        RainMid    = (& $tint 0.30)                  # corps clair
        RainBody   = (ConvertTo-HexSig $r $g $b)     # corps = couleur de base
        Halo       = (& $shade 0.20)
        Glow       = (ConvertTo-HexSig $r $g $b)
        NomNet     = "#FFF6F2F2"                      # « MadTrix » net : blanc cassé
        Filet      = (ConvertTo-HexSig $r $g $b)
        Rog        = (& $tint 0.14)
        Tagline    = $tag
        GrilleArgb = (ConvertTo-HexSig $r $g $b "22") # grille faible (alpha 0x22)
        Crochets   = (ConvertTo-HexSig $r $g $b)
    }
}

$script:StylesSignature = @("matrix", "hud", "neon")

function New-FondSignature {
    # Dessine un fond et l'enregistre en PNG. Retourne le chemin.
    param(
        [Parameter(Mandatory)][ValidateSet("matrix", "hud", "neon")][string]$Style,
        [Parameter(Mandatory)][int]$Largeur,
        [Parameter(Mandatory)][int]$Hauteur,
        [Parameter(Mandatory)][string]$Chemin,
        # Couleur de base du fond. Défaut = rouge MadTrix historique.
        [string]$Couleur = "#E01008"
    )
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
    $pal = Get-PaletteSignature -Base $Couleur

    $c = New-SigCanvas $Largeur $Hauteur
    switch ($Style) {
        "matrix" {
            Add-SigFond $c $Largeur $Hauteur $pal.FondCentre $pal.FondBord
            Add-SigPluie $c $Largeur $Hauteur 7 $pal
        }
        "hud" {
            Add-SigFond $c $Largeur $Hauteur $pal.FondCentre $pal.FondBord
            Add-SigGrille $c $Largeur $Hauteur 64 $pal.GrilleArgb
            Add-SigPluie $c $Largeur $Hauteur 21 $pal
            Add-SigCrochets $c $Largeur $Hauteur 70 90 $pal.Crochets
        }
        "neon" {
            Add-SigFond $c $Largeur $Hauteur $pal.FondCentre $pal.FondBord
            Add-SigGrille $c $Largeur $Hauteur 90 $pal.GrilleArgb
        }
    }
    Add-SigNom $c $Largeur $Hauteur $pal

    $c.Measure([System.Windows.Size]::new($Largeur, $Hauteur))
    $c.Arrange([System.Windows.Rect]::new(0, 0, $Largeur, $Hauteur))
    $c.UpdateLayout()
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($Largeur, $Hauteur, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($c)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [System.IO.File]::Create($Chemin)
    try { $enc.Save($fs) } finally { $fs.Dispose() }
    return $Chemin
}

function Set-FondEcran {
    # Applique le fond via SystemParametersInfo (effet immédiat), après avoir noté
    # le fond précédent pour pouvoir le remettre. On sauvegarde AUSSI dans le JSON
    # via Save-EtatAvant, pour que la « Restauration EXACTE » le connaisse.
    param([Parameter(Mandatory)][string]$Chemin)
    Add-Type -Namespace MadTweak -Name Bureau -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
'@ -ErrorAction SilentlyContinue

    # Mémorise le fond d'avant, une seule fois (le premier vu est le vrai).
    $memoire = Join-Path $script:DossierDonnees "fond-precedent.txt"
    if (-not (Test-Path $memoire)) {
        $ancien = (Get-ItemProperty "HKCU:\Control Panel\Desktop" -Name WallPaper -ErrorAction SilentlyContinue).WallPaper
        [System.IO.File]::WriteAllText($memoire, "$ancien")
    }
    Save-EtatAvant -Path "HKCU:\Control Panel\Desktop" -Name "WallPaper"
    Save-EtatAvant -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle"
    Save-EtatAvant -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper"

    # 10 = « Remplir », 0 = pas de mosaïque : le fond couvre tout l'écran.
    Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -Value "10"
    Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name TileWallpaper -Value "0"
    # 0x0014 = SPI_SETDESKWALLPAPER ; 3 = met à jour le registre ET rafraîchit.
    $r = [MadTweak.Bureau]::SystemParametersInfo(0x0014, 0, $Chemin, 3)
    if ($r -eq 0) { throw "Windows a refusé d'appliquer le fond d'écran (SystemParametersInfo a renvoyé 0)." }
}

function Restore-FondPrecedent {
    # Remet le fond d'écran d'avant, avec effet immédiat.
    $memoire = Join-Path $script:DossierDonnees "fond-precedent.txt"
    if (-not (Test-Path $memoire)) { throw "Aucun fond précédent mémorisé : ce script n'a pas encore changé ton fond d'écran." }
    $ancien = [System.IO.File]::ReadAllText($memoire).Trim()
    Add-Type -Namespace MadTweak -Name Bureau -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
'@ -ErrorAction SilentlyContinue
    [MadTweak.Bureau]::SystemParametersInfo(0x0014, 0, $ancien, 3) | Out-Null
    if ($ancien) { Write-Etat "Fond d'écran précédent restauré." -Niveau OK }
    else { Write-Etat "Il n'y avait pas de fond d'écran avant (fond uni) : l'écran est remis ainsi." -Niveau Info }
}

# ------------------------------------------------------------------------------
# ACCENT WINDOWS — couleur des barres de titre, de la barre des tâches et du Démarrer
#
# Différent du sélecteur de thème de CETTE fenêtre : ici on repeint Windows lui-même.
# Tout passe par Set-RegValue, donc « Annuler » sait tout remettre (Save-EtatAvant).
# ------------------------------------------------------------------------------
$script:AccentsWindows = [ordered]@{
    "ROG Rouge"      = @{ R = 226; G = 0;   B = 24  }
    "ROG Bleu"       = @{ R = 0;   G = 120; B = 215 }
    "Cyan Cyber"     = @{ R = 0;   G = 200; B = 235 }
    "Vert Émeraude"  = @{ R = 16;  G = 185; B = 129 }
    "Violet Néon"    = @{ R = 160; G = 90;  B = 220 }
    "Orange"         = @{ R = 255; G = 130; B = 0   }
    "Rose Néon"      = @{ R = 255; G = 0;   B = 120 }
}

function ConvertTo-DwordCouleur {
    # Un DWORD de registre est un entier 32 bits SIGNÉ côté PowerShell : une couleur
    # avec alpha 0xFF déborde de int32. On passe par les OCTETS (little-endian) pour
    # écrire exactement les bons bits sans exception d'overflow.
    #   ABGR (accent)      -> octets R, G, B, FF
    #   ARGB (colorization)-> octets B, G, R, FF
    param([byte]$O0, [byte]$O1, [byte]$O2, [byte]$O3 = 0xFF)
    return [System.BitConverter]::ToInt32([byte[]]@($O0, $O1, $O2, $O3), 0)
}

function Get-Nuance {
    # Éclaircit (facteur > 1, mélange vers le blanc) ou assombrit (facteur < 1).
    param([int]$R, [int]$G, [int]$B, [double]$Facteur)
    if ($Facteur -ge 1) {
        $t = [Math]::Min(1, $Facteur - 1)
        return @([int]($R + (255 - $R) * $t), [int]($G + (255 - $G) * $t), [int]($B + (255 - $B) * $t))
    }
    return @([int]($R * $Facteur), [int]($G * $Facteur), [int]($B * $Facteur))
}

# ------------------------------------------------------------------------------
# CLAVIER RGB ASUS ROG (Aura) — pilotage HID direct, sans logiciel tiers.
#
# Les claviers des portables ROG (contrôleur ITE, VID_0B05/PID_19B6) exposent une
# interface vendeur en page d'usage 0xFF31 : on y écrit un rapport 0x5D
# (b3 = effet + couleur, b4 = appliquer, b5 = mémoriser). C'est le canal qu'utilisent
# G-Helper et asusctl. Windows NE SAIT PAS piloter ce clavier (aucune interface
# LampArray / Éclairage dynamique) et OpenRGB ne le reconnaît pas : le HID direct
# est la seule voie. La luminosité, elle, passe par l'ACPI WMI ASUS (admin requis).
# NB : le rétroéclairage doit être allumé pour voir la couleur (Fn + F3/F4).
# ------------------------------------------------------------------------------
function Initialize-TypeClavierAura {
    # Compile (une seule fois) le pilote HID. Séparé pour que la détection, la
    # couleur, les effets et la luminosité partagent le même type compilé.
    if (([System.Management.Automation.PSTypeName]'MadTweak.ClavierAura').Type) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MadTweak {
  public static class ClavierAura {
    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVICE_INTERFACE_DATA { public int cbSize; public Guid InterfaceClassGuid; public int Flags; public IntPtr Reserved; }
    [StructLayout(LayoutKind.Sequential)]
    struct HIDD_ATTRIBUTES { public int Size; public ushort VendorID; public ushort ProductID; public ushort VersionNumber; }
    [StructLayout(LayoutKind.Sequential)]
    struct HIDP_CAPS {
      public ushort Usage; public ushort UsagePage;
      public ushort InputReportByteLength; public ushort OutputReportByteLength; public ushort FeatureReportByteLength;
      [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)] public ushort[] Reserved;
      public ushort NumberLinkCollectionNodes;
      public ushort a1,a2,a3,a4,a5,a6,a7,a8,a9;
    }
    [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid g);
    [DllImport("setupapi.dll", CharSet=CharSet.Auto)] static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr e, IntPtr h, int f);
    [DllImport("setupapi.dll", CharSet=CharSet.Auto)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr h, IntPtr d, ref Guid g, int i, ref SP_DEVICE_INTERFACE_DATA a);
    [DllImport("setupapi.dll", CharSet=CharSet.Auto)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr h, ref SP_DEVICE_INTERFACE_DATA a, IntPtr d, int ds, ref int rq, IntPtr dd);
    [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr h);
    [DllImport("kernel32.dll", CharSet=CharSet.Auto)] static extern IntPtr CreateFile(string n, uint acc, uint sh, IntPtr sec, uint disp, uint fl, IntPtr t);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("hid.dll")] static extern bool HidD_GetAttributes(IntPtr h, ref HIDD_ATTRIBUTES a);
    [DllImport("hid.dll")] static extern bool HidD_GetPreparsedData(IntPtr h, out IntPtr p);
    [DllImport("hid.dll")] static extern bool HidD_FreePreparsedData(IntPtr p);
    [DllImport("hid.dll")] static extern int  HidP_GetCaps(IntPtr p, out HIDP_CAPS c);
    [DllImport("hid.dll")] static extern bool HidD_SetFeature(IntPtr h, byte[] b, int len);
    [DllImport("hid.dll")] static extern bool HidD_SetOutputReport(IntPtr h, byte[] b, int len);
    const int DIGCF_PRESENT = 0x2, DIGCF_DEVICEINTERFACE = 0x10;
    const uint GENERIC_WRITE = 0x40000000, GENERIC_READ = 0x80000000, FILE_SHARE_RW = 0x3, OPEN_EXISTING = 3;

    static IntPtr OpenAura() { return OpenByUsage(0x0079); }
    static IntPtr OpenByUsage(ushort want) {
      Guid hid; HidD_GetHidGuid(out hid);
      IntPtr set = SetupDiGetClassDevs(ref hid, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
      var da = new SP_DEVICE_INTERFACE_DATA(); da.cbSize = Marshal.SizeOf(da);
      int idx = 0; IntPtr found = (IntPtr)(-1);
      while (SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref hid, idx++, ref da)) {
        int req = 0;
        SetupDiGetDeviceInterfaceDetail(set, ref da, IntPtr.Zero, 0, ref req, IntPtr.Zero);
        if (req <= 0) continue;
        IntPtr buf = Marshal.AllocHGlobal(req);
        Marshal.WriteInt32(buf, IntPtr.Size == 8 ? 8 : 6);
        string path = null;
        if (SetupDiGetDeviceInterfaceDetail(set, ref da, buf, req, ref req, IntPtr.Zero))
          path = Marshal.PtrToStringAuto(new IntPtr(buf.ToInt64() + 4));
        Marshal.FreeHGlobal(buf);
        if (path == null) continue;
        IntPtr h = CreateFile(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_RW, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (h == (IntPtr)(-1)) continue;
        var at = new HIDD_ATTRIBUTES(); at.Size = Marshal.SizeOf(at);
        bool match = false;
        if (HidD_GetAttributes(h, ref at) && at.VendorID == 0x0B05 && at.ProductID == 0x19B6) {
          IntPtr pp;
          if (HidD_GetPreparsedData(h, out pp)) {
            HIDP_CAPS caps; HidP_GetCaps(pp, out caps); HidD_FreePreparsedData(pp);
            if (caps.UsagePage == 0xFF31 && caps.Usage == want) match = true;
          }
        }
        if (match) { found = h; break; }
        CloseHandle(h);
      }
      SetupDiDestroyDeviceInfoList(set);
      return found;
    }

    static byte[] Frame(byte[] payload) { var b = new byte[64]; Array.Copy(payload, b, payload.Length); return b; }
    static bool Send(IntPtr h, byte[] payload) {
      var b = Frame(payload);
      bool ok = HidD_SetFeature(h, b, b.Length);
      if (!ok) ok = HidD_SetOutputReport(h, b, b.Length);
      return ok;
    }

    public static bool SetEffect(byte mode, byte r, byte g, byte b, byte speed) {
      IntPtr h = OpenAura();
      if (h == (IntPtr)(-1)) return false;
      try {
        bool ok = Send(h, new byte[]{0x5d, 0xb3, 0x00, mode, r, g, b, speed, 0x00, 0x00, r, g, b}); // effet + couleur
        Send(h, new byte[]{0x5d, 0xb4});   // appliquer
        Send(h, new byte[]{0x5d, 0xb5});   // mémoriser
        return ok;
      } finally { CloseHandle(h); }
    }
    public static bool SetColor(byte r, byte g, byte b) { return SetEffect(0x00, r, g, b, 0x00); }
    public static bool Present() {
      IntPtr h = OpenAura();
      if (h == (IntPtr)(-1)) return false;
      CloseHandle(h); return true;
    }
  }
}
'@ -ErrorAction Stop
}

# Effets supportés par le contrôleur N-Key (nom affiché -> octet « mode »). On s'en
# tient au socle universel de ces claviers (statique, respiration, stroboscope,
# arc-en-ciel) : les effets exotiques (comète, pluie...) varient selon le modèle et
# ne seraient qu'un placebo s'ils ne s'animent pas.
$script:EffetsClavier = [ordered]@{
    "Statique"    = 0x00
    "Respiration" = 0x01
    "Stroboscope" = 0x02
    "Arc-en-ciel" = 0x03
}
$script:VitessesClavier = [ordered]@{ "Lent" = 0xE1; "Moyen" = 0xEB; "Rapide" = 0xF5 }

# Luminosité du clavier en % : appliquée en ATTÉNUANT la couleur envoyée (la commande
# de niveau du firmware est ignorée sur ce matériel). Mémorisée ici pour que la
# synchronisation sur l'accent respecte le dernier réglage choisi.
$script:LuminositeClavier = 100

function Test-ClavierAura {
    # $true si un clavier RGB ASUS ROG compatible (N-Key ITE) répond présent.
    # C'est ce test qui décide d'AFFICHER ou non la page « Clavier RGB » de l'interface.
    try { Initialize-TypeClavierAura } catch { return $false }
    try { return [MadTweak.ClavierAura]::Present() } catch { return $false }
}

function Set-ClavierAura {
    # Pose une couleur et/ou un effet sur le clavier Aura. Best-effort : renvoie
    # $false si aucun clavier compatible n'est présent, sans faire échouer l'appelant.
    # -Luminosite (0-100 %) atténue la couleur : c'est notre réglage de luminosité,
    # la commande de niveau du firmware étant ignorée sur ce clavier.
    param(
        [Parameter(Mandatory)][int]$R, [Parameter(Mandatory)][int]$G, [Parameter(Mandatory)][int]$B,
        [string]$Mode = "Statique", [string]$Vitesse = "Moyen",
        [ValidateRange(0, 100)][int]$Luminosite = $script:LuminositeClavier
    )
    if (-not $script:EffetsClavier.Contains($Mode)) { $Mode = "Statique" }
    if (-not $script:VitessesClavier.Contains($Vitesse)) { $Vitesse = "Moyen" }
    $R = [int]($R * $Luminosite / 100)
    $G = [int]($G * $Luminosite / 100)
    $B = [int]($B * $Luminosite / 100)
    if ($script:Simulation) {
        Write-Simu "poserait le clavier RGB ASUS : effet « $Mode », couleur RVB $R,$G,$B, vitesse $Vitesse, luminosité $Luminosite%"
        return $true
    }
    try { Initialize-TypeClavierAura } catch { return $false }
    $m = [byte]$script:EffetsClavier[$Mode]
    $v = [byte]$script:VitessesClavier[$Vitesse]
    return [MadTweak.ClavierAura]::SetEffect($m, [byte]$R, [byte]$G, [byte]$B, $v)
}

# NOTE : la commande de NIVEAU de rétroéclairage du firmware et les modes de
# performance (Turbo/Silencieux) restent écartés : sur ce matériel, les commandes
# ASUS correspondantes (WMI DEVS, pilote \\.\ATKACPI) sont ACCEPTÉES mais SANS effet
# hors écosystème ASUS complet -- ce ne serait qu'un placebo (a fortiori sur du
# thermique). La luminosité du CLAVIER est donc obtenue en atténuant la couleur
# (Set-ClavierAura -Luminosite), ce qui fonctionne. Les courbes de ventilateur
# relèvent d'un outil dédié (G-Helper).

# ------------------------------------------------------------------------------
# LUMINOSITÉ DE L'ÉCRAN — via WMI (WmiMonitorBrightnessMethods) : natif et fiable,
# ne dépend d'aucun pilote tiers. Disponible sur les écrans pilotables (portables).
# ------------------------------------------------------------------------------
function Test-EcranReglable {
    try { $null = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop; return $true }
    catch { return $false }
}

function Get-LuminositeEcran {
    try { return [int](Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness -ErrorAction Stop).CurrentBrightness }
    catch { return -1 }
}

function Set-LuminositeEcran {
    param([Parameter(Mandatory)][ValidateRange(0, 100)][int]$Niveau)
    if ($script:Simulation) { Write-Simu "réglerait la luminosité de l'écran sur $Niveau%"; return $true }
    try {
        $m = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop
        Invoke-CimMethod -InputObject $m -MethodName WmiSetBrightness -Arguments @{ Brightness = [byte]$Niveau; Timeout = [uint32]0 } -ErrorAction Stop | Out-Null
        return $true
    }
    catch { return $false }
}

# ------------------------------------------------------------------------------
# MODE D'ALIMENTATION WINDOWS — le curseur « Mode d'alimentation » des Paramètres.
# Natif (PowerSetActiveOverlayScheme), fiable, sans aucun ASUS.
#
# ATTENTION : ce n'est PAS le « Turbo » ASUS. Le Turbo ASUS pilote les ventilateurs
# et le TDP via l'EC, et il est INACCESSIBLE à un script isolé -- mesuré sur ce
# matériel : sous charge CPU, la fréquence est IDENTIQUE en Silencieux et en Turbo
# (le driver ASUS ignore la commande hors Armoury Crate / G-Helper). Ce réglage-ci
# agit sur le boost et l'EPP du CPU côté Windows, ce qui est réel mais différent.
# ------------------------------------------------------------------------------
$script:ModesAlimentation = [ordered]@{
    "Économie d'énergie" = "961cc777-2547-4f9d-8174-7d86181b8a7a"
    "Équilibré"          = "00000000-0000-0000-0000-000000000000"
    "Performances"       = "ded574b5-45a0-4f42-8737-46345c09c238"
}

function Initialize-TypeAlimentation {
    if (([System.Management.Automation.PSTypeName]'MadTweak.Alim').Type) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MadTweak {
  public static class Alim {
    [DllImport("powrprof.dll")] public static extern uint PowerSetActiveOverlayScheme(Guid overlay);
  }
}
'@ -ErrorAction Stop
}

function Set-ModeAlimentation {
    # Applique un mode d'alimentation Windows (overlay). Best-effort : $false si l'API
    # échoue. NB : « Équilibré » = GUID nul, qui retire tout overlay (= défaut).
    param([Parameter(Mandatory)][string]$Mode)
    if (-not $script:ModesAlimentation.Contains($Mode)) { throw "Mode d'alimentation « $Mode » inconnu." }
    if ($script:Simulation) { Write-Simu "réglerait le mode d'alimentation Windows sur « $Mode »"; return $true }
    try {
        Initialize-TypeAlimentation
        return ([MadTweak.Alim]::PowerSetActiveOverlayScheme([Guid]$script:ModesAlimentation[$Mode]) -eq 0)
    }
    catch { return $false }
}

# ------------------------------------------------------------------------------
# CAPTEURS (lecture seule) — GPU via nvidia-smi (sans admin, fiable) et ventilateurs
# via l'ACPI ASUS (ATKACPI DSTS, admin requis). La vraie température des cœurs CPU
# n'est PAS exposée sans pilote dédié (HWiNFO/LibreHardwareMonitor) : on ne l'invente
# pas. La zone thermique ACPI, elle, ne reflète qu'un point carte mère générique.
# ------------------------------------------------------------------------------
function Initialize-TypeAcpi {
    if (([System.Management.Automation.PSTypeName]'MadTweak.Acpi').Type) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MadTweak {
  public static class Acpi {
    [DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
    static extern IntPtr CreateFile(string n, uint a, uint s, IntPtr se, uint d, uint f, IntPtr t);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool DeviceIoControl(IntPtr h, uint c, byte[] i, uint isz, byte[] o, uint osz, out uint r, IntPtr ov);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    const uint GR=0x80000000, GW=0x40000000, OPEN=3, IOCTL=0x0022240C, DSTS=0x53545344;
    public static long Dsts(uint id) {
      IntPtr h = CreateFile(@"\\.\ATKACPI", GR|GW, 0, IntPtr.Zero, OPEN, 0, IntPtr.Zero);
      if (h == (IntPtr)(-1)) return -2;
      try {
        byte[] b = new byte[12];
        BitConverter.GetBytes(DSTS).CopyTo(b,0); BitConverter.GetBytes((uint)4).CopyTo(b,4); BitConverter.GetBytes(id).CopyTo(b,8);
        byte[] o = new byte[16]; uint r;
        if (!DeviceIoControl(h, IOCTL, b, (uint)b.Length, o, (uint)o.Length, out r, IntPtr.Zero)) return -3;
        return BitConverter.ToUInt32(o, 0);
      } finally { CloseHandle(h); }
    }
  }
}
'@ -ErrorAction Stop
}

function Get-CapteursMateriel {
    # Renvoie @{ GpuTemp; GpuLoad; FanCpu; FanGpu } ; $null pour l'indisponible.
    $r = @{ GpuTemp = $null; GpuLoad = $null; FanCpu = $null; FanGpu = $null }
    try {
        $exe = (Get-Command nvidia-smi -ErrorAction SilentlyContinue).Source
        if (-not $exe -and (Test-Path "$env:SystemRoot\System32\nvidia-smi.exe")) { $exe = "$env:SystemRoot\System32\nvidia-smi.exe" }
        if ($exe) {
            $o = @(& $exe --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>$null)[0]
            if ($o) { $p = ($o -split ',').Trim(); $r.GpuTemp = [int]$p[0]; $r.GpuLoad = [int]$p[1] }
        }
    }
    catch { }
    try {
        Initialize-TypeAcpi
        $c = [MadTweak.Acpi]::Dsts(0x00110013); if ($c -gt 0) { $r.FanCpu = ($c -band 0xFF) * 100 }
        $g = [MadTweak.Acpi]::Dsts(0x00110014); if ($g -gt 0) { $r.FanGpu = ($g -band 0xFF) * 100 }
    }
    catch { }
    return $r
}

function Set-AccentWindows {
    param([Parameter(Mandatory)][string]$Nom)
    if (-not $script:AccentsWindows.Contains($Nom)) { throw "Accent « $Nom » inconnu." }
    $c = $script:AccentsWindows[$Nom]
    $R = $c.R; $G = $c.G; $B = $c.B

    $accent = ConvertTo-DwordCouleur $R $G $B 0xFF           # ABGR
    $coloriz = ConvertTo-DwordCouleur $B $G $R 0xFF          # ARGB
    $sombre = Get-Nuance $R $G $B 0.60
    $startDword = ConvertTo-DwordCouleur $sombre[0] $sombre[1] $sombre[2] 0xFF

    # Palette des 8 nuances (clair -> foncé), la couleur choisie au centre.
    $facteurs = @(1.6, 1.4, 1.2, 1.0, 0.82, 0.66, 0.52, 0.40)
    $palette = New-Object System.Collections.Generic.List[byte]
    foreach ($f in $facteurs) {
        $n = Get-Nuance $R $G $B $f
        $palette.Add([byte][Math]::Min(255, $n[0]))
        $palette.Add([byte][Math]::Min(255, $n[1]))
        $palette.Add([byte][Math]::Min(255, $n[2]))
        $palette.Add([byte]0xFF)
    }

    $kAccent = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent"
    $kDWM = "HKCU:\Software\Microsoft\Windows\DWM"
    $kPerso = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"

    if ($script:Simulation) {
        Write-Simu "appliquerait l'accent Windows « $Nom » (RVB $R,$G,$B) : barres de titre, barre des tâches, Démarrer, et synchroniserait le clavier RGB ASUS"
        return
    }

    Set-RegValue -Path $kAccent -Name "AccentColorMenu" -Value $accent
    Set-RegValue -Path $kAccent -Name "StartColorMenu" -Value $startDword
    Set-RegValue -Path $kAccent -Name "AccentPalette" -Value ([byte[]]$palette.ToArray()) -Type Binary
    Set-RegValue -Path $kDWM -Name "AccentColor" -Value $accent
    Set-RegValue -Path $kDWM -Name "ColorizationColor" -Value $coloriz
    Set-RegValue -Path $kDWM -Name "ColorizationAfterglow" -Value $coloriz
    Set-RegValue -Path $kDWM -Name "ColorPrevalence" -Value 1          # accent sur les barres de titre
    # La barre des tâches et le menu Démarrer ne prennent l'accent qu'en thème SOMBRE.
    Set-RegValue -Path $kPerso -Name "ColorPrevalence" -Value 1
    Set-RegValue -Path $kPerso -Name "SystemUsesLightTheme" -Value 0
    Set-RegValue -Path $kPerso -Name "AppsUseLightTheme" -Value 0

    Publish-ChangementCouleur

    # Synchronise le clavier RGB ASUS (Aura) sur la même couleur, en HID direct.
    # Best-effort : sur une machine sans clavier ROG compatible, on ignore sans
    # faire échouer l'accent. Le RGB clavier n'est PAS dans la sauvegarde JSON
    # (c'est du matériel, pas du registre) : « Retour au défaut » le remet en blanc.
    try {
        if (Set-ClavierAura -R $R -G $G -B $B) {
            Write-Etat "Clavier RGB ASUS synchronisé sur l'accent (RVB $R,$G,$B)." -Niveau OK
        }
        else {
            Write-Etat "Aucun clavier RGB ASUS compatible détecté : synchronisation du clavier ignorée." -Niveau Info
        }
    }
    catch {
        Write-Etat "Synchronisation du clavier ignorée : $($_.Exception.Message)" -Niveau Avert
    }

    Write-Etat "Accent « $Nom » appliqué (RVB $R,$G,$B). Thème sombre activé pour que la barre des tâches se colore aussi." -Niveau OK
}

function Restore-AccentWindows {
    # Remet l'accent Windows à un état neutre : plus de couleur sur les barres.
    # La RESTAURATION EXACTE (menu Annuler) rend l'état précis d'avant ; ceci est
    # le retour « défaut Windows » immédiat.
    if ($script:Simulation) { Write-Simu "retirerait l'accent des barres, et remettrait le clavier RGB en blanc statique"; return }
    Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "ColorPrevalence" -Value 0
    Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "ColorPrevalence" -Value 0
    Publish-ChangementCouleur
    # Le clavier ne se « lit » pas : on ne peut pas restaurer l'effet Aura exact
    # d'avant (arc-en-ciel, respiration...). On le remet en blanc statique, neutre.
    try { Set-ClavierAura -R 255 -G 255 -B 255 | Out-Null } catch { }
    Write-Etat "Accent retiré des barres, clavier remis en blanc. Pour l'état EXACT d'avant, utilise « Restauration EXACTE » (menu Annuler). L'effet Aura d'origine du clavier (animé) n'est pas récupérable par cette voie." -Niveau Info
}

function Publish-ChangementCouleur {
    # Diffuse le changement pour qu'il s'applique sans fermer la session.
    Add-Type -Namespace MadTweak -Name Couleur -MemberDefinition @'
[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.IntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out System.IntPtr lpdwResult);
'@ -ErrorAction SilentlyContinue
    $HWND_BROADCAST = [System.IntPtr]0xFFFF
    $WM_SETTINGCHANGE = 0x001A
    $out = [System.IntPtr]::Zero
    foreach ($sig in @("ImmersiveColorSet", "WindowsThemeElement")) {
        [MadTweak.Couleur]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [System.IntPtr]::Zero, $sig, 2, 200, [ref]$out) | Out-Null
    }

    # Les barres de TITRE se recolorent tout de suite via DWM. Mais la BARRE DES
    # TÂCHES et le menu Démarrer ne relisent la couleur d'accent qu'au redémarrage
    # du shell : sans ça, la barre garde l'ancienne couleur (bug « barre rouge
    # alors que l'accent est bleu »). On relance donc l'Explorateur. La fenêtre
    # MadTweak (autre processus) n'est pas touchée ; seuls la barre et le bureau
    # clignotent une seconde.
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 900
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        Start-Process explorer.exe
    }
}

function Menu-AccentWindows {
    Clear-Host
    Write-Host "=== ACCENT WINDOWS (couleur des barres) ===" -ForegroundColor Cyan
    Write-Host "  Colore les barres de titre, la barre des tâches et le menu Démarrer." -ForegroundColor DarkGray
    Write-Host "  + synchronise le clavier RGB ASUS (Aura) sur la même couleur." -ForegroundColor DarkGray
    Write-Host "  Réversible : « Annuler » remet l'état exact d'avant." -ForegroundColor DarkGray
    Write-Host ""
    $noms = @($script:AccentsWindows.Keys)
    for ($i = 0; $i -lt $noms.Count; $i++) {
        $c = $script:AccentsWindows[$noms[$i]]
        Write-Host ("  {0} - {1,-16} (RVB {2},{3},{4})" -f ($i + 1), $noms[$i], $c.R, $c.G, $c.B) -ForegroundColor Gray
    }
    Write-Host ("  {0} - Retour au défaut (retirer l'accent des barres)" -f ($noms.Count + 1)) -ForegroundColor Yellow
    Write-Host ("  {0} - Retour" -f ($noms.Count + 2))
    Write-Host ""
    $choix = Read-Host "Choisis (1-$($noms.Count + 2))"

    $n = 0
    if (-not [int]::TryParse($choix, [ref]$n)) { return }
    try {
        if ($n -ge 1 -and $n -le $noms.Count) {
            Set-AccentWindows -Nom $noms[$n - 1]
            $script:CompteurOK++
        }
        elseif ($n -eq $noms.Count + 1) {
            Restore-AccentWindows
            $script:CompteurOK++
        }
    }
    catch {
        Write-Etat "Échec : $($_.Exception.Message)" -Niveau Echec
        $script:CompteurEchec++
    }
}

function Menu-Signature {
    Clear-Host
    Write-Host "=== SIGNATURE : FOND D'ÉCRAN MADTRIX ===" -ForegroundColor Red
    Write-Host "  Génère un fond d'écran à ta résolution exacte, puis l'applique." -ForegroundColor DarkGray
    Write-Host "  Ton fond actuel est mémorisé : l'option 5 le remet quand tu veux." -ForegroundColor DarkGray
    Write-Host ""
    $script:CompteurOK = 0; $script:CompteurEchec = 0

    $res = Get-ResolutionPhysique
    Write-Host "  Résolution détectée : $($res.L) x $($res.H)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  1 - Style MATRIX  (pluie de code katakana rouge)" -ForegroundColor Red
    Write-Host "  2 - Style HUD     (pluie + grille + crochets gaming)" -ForegroundColor Red
    Write-Host "  3 - Style NEON    (sobre, gros nom néon)" -ForegroundColor Red
    Write-Host "  4 - Générer les TROIS dans un dossier, sans les appliquer" -ForegroundColor Yellow
    Write-Host "  5 - Remettre mon fond d'écran d'avant" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  6 - ACCENT WINDOWS : couleur des barres (ROG rouge, bleu, cyan...)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  7 - Retour au menu principal"
    Write-Host ""
    $choix = Read-Host "Choisis (1-7)"

    try {
        switch ($choix) {
            { $_ -in "1", "2", "3" } {
                $style = $script:StylesSignature[[int]$choix - 1]
                if ($script:Simulation) { Write-Simu "générerait et appliquerait le fond « $style » en $($res.L)x$($res.H)"; break }
                $chemin = Join-Path $script:DossierDonnees "fond-madtrix-$style.png"
                Write-Etat "Génération du fond « $style »..." -Niveau Info
                New-FondSignature -Style $style -Largeur $res.L -Hauteur $res.H -Chemin $chemin | Out-Null
                Set-FondEcran -Chemin $chemin
                Write-Etat "Fond « $style » appliqué. Fichier : $chemin" -Niveau OK
                $script:CompteurOK++
            }
            "4" {
                $dossier = Join-Path ([Environment]::GetFolderPath("Desktop")) "signatures-madtrix"
                if (-not (Test-Path $dossier)) { New-Item -ItemType Directory -Path $dossier -Force | Out-Null }
                if ($script:Simulation) { Write-Simu "générerait les 3 fonds dans $dossier"; break }
                foreach ($style in $script:StylesSignature) {
                    $chemin = Join-Path $dossier "madtrix-$style.png"
                    New-FondSignature -Style $style -Largeur $res.L -Hauteur $res.H -Chemin $chemin | Out-Null
                    Write-Etat "Généré : $chemin" -Niveau OK
                }
                Write-Etat "Les trois fonds sont dans : $dossier" -Niveau Info
                $script:CompteurOK++
            }
            "5" {
                if ($script:Simulation) { Write-Simu "remettrait le fond d'écran précédent"; break }
                Restore-FondPrecedent
                $script:CompteurOK++
            }
            "6" { Menu-AccentWindows }
            "7" { return }
            default { Write-Etat "Choix invalide." -Niveau Avert }
        }
    }
    catch {
        Write-Etat "Échec : $($_.Exception.Message)" -Niveau Echec
        $script:CompteurEchec++
    }

    Fin-De-Menu
}
