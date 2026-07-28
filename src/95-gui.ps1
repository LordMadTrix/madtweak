# ------------------------------------------------------------------------------
# INTERFACE GRAPHIQUE (WPF)
#
# Ce module n'est qu'une FAÇADE : il ne contient aucun tweak, aucune connaissance
# du registre, aucune règle métier. Il fait trois choses :
#   1. il demande à Get-Inventaire la liste des tweaks pilotables (donc au CODE,
#      jamais à une liste tenue en parallèle) ;
#   2. il coche des cases ;
#   3. il pose les clés cochées dans $script:ProfilActif et rejoue les menus.
#
# Autrement dit : une interface graphique, ici, c'est UN PROFIL QUE TU COMPOSES
# TOI-MÊME. Tout le mécanisme existait déjà pour les profils ; on ne fait que lui
# donner des cases à cocher au lieu d'une liste écrite en dur.
#
# RESPONSIVITÉ : l'application des tweaks tourne sur un FIL D'ARRIÈRE-PLAN
# (Start-ApplyArrierePlan), pas sur le thread de l'interface. La fenêtre ne se fige
# donc jamais, même pendant un point de restauration (30-60 s) ou l'énumération des
# bloatwares. Une première version faisait tout sur le thread de l'interface : elle
# « tournait dans le vide », fenêtre gelée. Le repli synchrone (qui fige) ne sert
# que si le fichier source est illisible -- cas d'un script collé dans une console.
# ------------------------------------------------------------------------------

function Update-InterfaceGui {
    # L'équivalent WPF de DoEvents : on laisse le Dispatcher traiter ce qui est en
    # attente (redessin, log) avant de reprendre. Sans ça, Windows marquerait la
    # fenêtre « ne répond pas » dès le premier tweak un peu long.
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [System.Windows.Threading.DispatcherOperationCallback] { param($f) $f.Continue = $false; return $null },
        $frame) | Out-Null
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

function Start-ApplyArrierePlan {
    # Exécute l'application des tweaks sur un FIL D'ARRIÈRE-PLAN (runspace), pour
    # que la fenêtre ne se fige JAMAIS -- même pendant un point de restauration
    # (30-60 s) ou l'énumération des bloatwares. Le fil pousse ses messages dans
    # une file thread-safe ; une minuterie sur le thread de l'interface la vide
    # dans le journal et détecte la fin. Le fond d'écran figé, c'était toute
    # l'application qui tournait sur le thread de l'interface : ici, plus rien.
    #
    # Lève si le code source n'est pas lisible (script collé dans une console) :
    # l'appelant retombe alors sur l'exécution directe (qui fige, mais marche).
    param(
        [Parameter(Mandatory)]$Journal,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Cles,
        [bool]$EnSimulation,
        [bool]$PointResto,
        [Parameter(Mandatory)][scriptblock]$OnFini
    )
    $src = $null
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
        try { $src = [System.IO.File]::ReadAllText($PSCommandPath) } catch { }
    }
    if (-not $src) { throw "source-indisponible" }
    # On coupe AVANT la section LANCEMENT (l'appel « Initialize-Sauvegarde » en
    # début de ligne) : le fil définit toutes les fonctions sans relancer l'interface.
    $m = [regex]::Match($src, '(?m)^Initialize-Sauvegarde\b')
    if (-not $m.Success) { throw "source-indisponible" }
    $defs = $src.Substring(0, $m.Index)

    $sync = [hashtable]::Synchronized(@{
        File = (New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]')
        Fini = $false; OK = 0; Echec = 0; Simu = 0; Redem = @(); Jouees = @(); Progress = 0
    })

    # Le pilote tourne DANS le fil, après les définitions. Guillemets simples :
    # rien ne s'expanse ici, ces $variables sont résolues côté runspace.
    $pilote = @'
$script:DossierDonnees   = $SeedDossier
$script:DossierCles      = $SeedDossierCles
$script:FichierSauvegarde = $SeedFichierSauvegarde
$script:Sauvegarde       = $SeedSauvegarde
$script:Machine          = $SeedMachine
$script:InfosOS          = $SeedInfosOS
$script:EstFamille       = $SeedEstFamille
$script:BuildOS          = $SeedBuildOS
$script:SauvegardeActive = $true
$script:Simulation       = $SeedSimu
$script:CompteurOK = 0; $script:CompteurEchec = 0; $script:SimuCompteur = 0
$script:ClesJouees = @(); $script:RedemarrageRequis = @()
$script:Sync = $SeedSync
# Toute la sortie du script part désormais dans la file, pas dans une console.
$script:SortieGui = {
    param($m, $n)
    $script:Sync.File.Enqueue(@($n, $m))
    $script:Sync.Progress = $script:ClesJouees.Count
}
try {
    if ($SeedPointResto -and -not $SeedSimu) {
        $script:Sync.File.Enqueue(@('Info', 'Creation du point de restauration (30 a 60 s, la fenetre reste reactive)...'))
        if (-not (New-PointRestauration -Description 'MadTweak (interface)')) {
            $script:Sync.File.Enqueue(@('Avert', 'Point de restauration NON cree : aucun filet de securite.'))
        }
    }
    $script:ProfilActif = $SeedCles
    Invoke-TousLesMenus
}
catch {
    $script:Sync.File.Enqueue(@('Echec', "ERREUR INATTENDUE : $($_.Exception.Message)"))
}
finally {
    $script:ProfilActif = $null
    $script:Sync.OK     = $script:CompteurOK
    $script:Sync.Echec  = $script:CompteurEchec
    $script:Sync.Simu   = $script:SimuCompteur
    $script:Sync.Redem  = @($script:RedemarrageRequis)
    $script:Sync.Jouees = @($script:ClesJouees)
    $script:Sync.Fini   = $true
}
'@

    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ssp = $rs.SessionStateProxy
    # $script:Sauvegarde est partagé PAR RÉFÉRENCE : les sauvegardes écrites par le
    # fil sont visibles du thread principal, donc « Annuler » les connaîtra. Aucun
    # accès concurrent : pendant l'application, le thread principal ne fait que
    # vider la file.
    $ssp.SetVariable('SeedSync', $sync)
    $ssp.SetVariable('SeedDossier', $script:DossierDonnees)
    $ssp.SetVariable('SeedDossierCles', $script:DossierCles)
    $ssp.SetVariable('SeedFichierSauvegarde', $script:FichierSauvegarde)
    $ssp.SetVariable('SeedSauvegarde', $script:Sauvegarde)
    $ssp.SetVariable('SeedMachine', $script:Machine)
    $ssp.SetVariable('SeedInfosOS', $script:InfosOS)
    $ssp.SetVariable('SeedEstFamille', $script:EstFamille)
    $ssp.SetVariable('SeedBuildOS', $script:BuildOS)
    $ssp.SetVariable('SeedCles', [string[]]$Cles)
    $ssp.SetVariable('SeedSimu', $EnSimulation)
    $ssp.SetVariable('SeedPointResto', $PointResto)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript($defs + "`n" + $pilote) | Out-Null
    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Add_Tick({
        $item = $null
        while ($sync.File.TryDequeue([ref]$item)) {
            $prefixe = switch ($item[0]) {
                'OK' { '  [OK]    ' } 'Echec' { '  [ÉCHEC] ' } 'Avert' { '  [!]     ' }
                'Simu' { '  [SIMU]  ' } 'Titre' { '' } default { '  [..]    ' }
            }
            $Journal.AppendText("$prefixe$($item[1])`r`n")
        }
        $Journal.ScrollToEnd()
        if ($script:GuiProgress -and $Cles.Count -gt 0) {
            $val = [math]::Round(($sync.Progress / $Cles.Count) * 100)
            $script:GuiProgress.Value = [math]::Min(100, [math]::Max(0, $val))
        }
        if ($sync.Fini) {
            $timer.Stop()
            try { $ps.EndInvoke($handle) } catch { }
            $ps.Dispose(); $rs.Dispose()
            & $OnFini $sync
        }
    }.GetNewClosure())
    $timer.Start()
}

function Get-NomOnglet {
    # Les titres de menu sont écrits pour une console en majuscules : ils sont bien
    # trop longs pour un onglet. On les raccourcit ici, et seulement pour l'affichage.
    param([Parameter(Mandatory)][string]$Categorie)
    # Le motif reste FRANÇAIS : c'est le titre du menu console qui sert de clé, et il
    # ne dépend pas de la langue d'affichage. Seul le libellé rendu est traduit.
    $en = $script:LangueActive -eq 'en'
    switch -Wildcard ($Categorie) {
        "TWEAKS DE BASE*" { if ($en) { "Basics" } else { "Base" } }
        "TWEAKS AVANCÉS*" { if ($en) { "Advanced" } else { "Avancés" } }
        "EXPLORATEUR*" { if ($en) { "Privacy" } else { "Vie privée" } }
        "OPTIMISATION DU MATÉRIEL*" { if ($en) { "Hardware & Network" } else { "Matériel & Réseau" } }
        "SÉCURITÉ & IA*" { if ($en) { "Security & AI" } else { "Sécurité & IA" } }
        "NOUVEAUTÉS WINDOWS 11*" { if ($en) { "Windows 11" } else { "Windows 11" } }
        "APPARENCE*" { if ($en) { "Appearance" } else { "Apparence" } }
        "DÉMARRAGE*" { if ($en) { "Startup & Services" } else { "Démarrage & Services" } }
        "CONFIGURATION SÉCURITÉ*" { if ($en) { "Updates & Security" } else { "Mises à jour & Sécurité" } }
        "LOGICIELS EXPRESS*" { if ($en) { "Software (winget)" } else { "Logiciels (winget)" } }
        "OUTILS DE DIAGNOSTIC*" { if ($en) { "Maintenance" } else { "Maintenance" } }
        "NETTOYAGE DU DISQUE*" { if ($en) { "Cleanup" } else { "Nettoyage" } }
        default { $Categorie }
    }
}

function Get-NomProfil {
    # Nom d'affichage d'un profil. La CLÉ du profil reste française : elle sert
    # d'identifiant dans tout le code (boutons, Tag, journal). Seul l'affichage change.
    param([Parameter(Mandatory)][string]$Nom)
    if ($script:LangueActive -eq 'en' -and $script:Profils[$Nom].Nom_en) { return $script:Profils[$Nom].Nom_en }
    return $Nom
}

function Get-DescriptionProfil {
    param([Parameter(Mandatory)][string]$Nom)
    $p = $script:Profils[$Nom]
    if ($script:LangueActive -eq 'en' -and $p.Description_en) { return $p.Description_en }
    return $p.Description
}

$script:XamlInterface = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MadTweak — Configuration système" Height="740" Width="1060"
        WindowStartupLocation="CenterScreen" Background="{DynamicResource WindowBgBrush}"
        WindowState="Maximized">
  <Window.Resources>
    <SolidColorBrush x:Key="WindowBgBrush" Color="#FF1B1B1F"/>
    <SolidColorBrush x:Key="PanelBgBrush" Color="#FF232329"/>
    <SolidColorBrush x:Key="TextPrimaryBrush" Color="#FFD8D8DC"/>
    <SolidColorBrush x:Key="TextMutedBrush" Color="#FF8A8A92"/>
    <SolidColorBrush x:Key="AccentBrush" Color="#FF4FA6E8"/>
    <SolidColorBrush x:Key="BorderBrush" Color="#FF3F3F46"/>
    <SolidColorBrush x:Key="ButtonBgBrush" Color="#FF2D2D33"/>
    <SolidColorBrush x:Key="JournalBgBrush" Color="#FF141417"/>
    <SolidColorBrush x:Key="JournalFgBrush" Color="#FFC8C8CE"/>

    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Margin" Value="2,5,2,5"/>
      <!-- Sans template custom, WPF dessine une case BLANCHE système qui jure avec
           le thème sombre (« les carrés blancs »). On la redessine : case sombre,
           bordure thème, coche en couleur d'accent quand cochée. -->
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="case" Width="18" Height="18" CornerRadius="3"
                      Background="{DynamicResource ButtonBgBrush}"
                      BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1"
                      VerticalAlignment="Center" SnapsToDevicePixels="True">
                <Path x:Name="coche" Stretch="Uniform" Margin="3,4,3,3"
                      Data="M 0,5 L 4,9 L 11,0"
                      Stroke="{DynamicResource AccentBrush}" StrokeThickness="2"
                      StrokeStartLineCap="Round" StrokeEndLineCap="Round"
                      Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="coche" Property="Visibility" Value="Visible"/>
                <Setter TargetName="case" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="case" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Background" Value="{DynamicResource ButtonBgBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
    <!-- Champs de saisie : sans style explicite, WPF les peint en blanc sur blanc
         dès que le thème est sombre. Même remède que pour les cases et les onglets. -->
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource ButtonBgBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="CaretBrush" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="6,4"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
    </Style>
    <Style TargetType="PasswordBox">
      <Setter Property="Background" Value="{DynamicResource ButtonBgBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="CaretBrush" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="6,4"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
    </Style>
    <Style TargetType="TabItem">
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <!-- Le template Aero peint l'onglet SÉLECTIONNÉ en blanc. On le redessine :
           onglet actif = fond panneau + trait d'accent dessous ; inactif = bouton. -->
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TabItem">
            <Border x:Name="onglet" Background="{DynamicResource ButtonBgBrush}"
                    BorderThickness="0,0,0,2" BorderBrush="Transparent" Margin="0,0,2,0" CornerRadius="3,3,0,0">
              <ContentPresenter ContentSource="Header" Margin="12,6"
                                HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="onglet" Property="Background" Value="{DynamicResource PanelBgBrush}"/>
                <Setter TargetName="onglet" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="onglet" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Height" Value="26"/>
      <!-- Comme pour les cases, le template Aero dessine un fond BLANC système que
           le Setter Background ne remplace pas. On redessine toute la ComboBox :
           fond sombre, flèche au thème, liste déroulante sombre. -->
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton x:Name="bouton" Focusable="False" ClickMode="Press"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="bord" Background="{DynamicResource ButtonBgBrush}"
                            BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="3">
                      <Grid>
                        <Grid.ColumnDefinitions>
                          <ColumnDefinition/>
                          <ColumnDefinition Width="22"/>
                        </Grid.ColumnDefinitions>
                        <Path Grid.Column="1" HorizontalAlignment="Center" VerticalAlignment="Center"
                              Data="M 0,0 L 4,4 L 8,0" Stroke="{DynamicResource TextPrimaryBrush}" StrokeThickness="1.5"/>
                      </Grid>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="bord" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
                      </Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter x:Name="contenu" Content="{TemplateBinding SelectionBoxItem}"
                                ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                Margin="8,0,26,0" VerticalAlignment="Center" IsHitTestVisible="False"
                                TextElement.Foreground="{DynamicResource TextPrimaryBrush}"/>
              <Popup x:Name="liste" IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom"
                     AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                <Border Background="{DynamicResource PanelBgBrush}" BorderBrush="{DynamicResource BorderBrush}"
                        BorderThickness="1" CornerRadius="3" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
                  <ScrollViewer MaxHeight="320">
                    <ItemsPresenter/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Padding" Value="8,5"/>
      <!-- On REMPLACE le template Aero : sinon son survol bleu clair par défaut
           écrase notre couleur et rend l'item illisible (texte clair sur fond
           clair). Avec ce template, le fond de l'item est à nous : sombre au
           repos, accent + texte blanc au survol/sélection. -->
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="bordure" Background="{DynamicResource PanelBgBrush}"
                    Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
              <ContentPresenter x:Name="contenu" HorizontalAlignment="Left" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="bordure" Property="Background" Value="{DynamicResource AccentBrush}"/>
                <Setter Property="Foreground" Value="#FFFFFFFF"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="bordure" Property="Background" Value="{DynamicResource AccentBrush}"/>
                <Setter Property="Foreground" Value="#FFFFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- MENUS. Comme pour les cases et les listes, le template par défaut de WPF
         dessine un fond BLANC système : on le remplace entièrement, sinon les menus
         seraient illisibles sur un thème sombre (le fameux « carré blanc »).
         Deux styles : « MenuTop » pour les entrées de la barre (bouton + popup),
         et le style implicite pour les lignes du menu déroulant. -->
    <Style x:Key="MenuTop" TargetType="MenuItem">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="MenuItem">
            <Border x:Name="bord" Background="{DynamicResource ButtonBgBrush}"
                    BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1"
                    CornerRadius="3" Padding="12,6" Margin="0,0,8,0">
              <Grid>
                <ContentPresenter ContentSource="Header" VerticalAlignment="Center"/>
                <Popup x:Name="popup" IsOpen="{TemplateBinding IsSubmenuOpen}" Placement="Bottom"
                       AllowsTransparency="True" Focusable="False" PopupAnimation="Fade" StaysOpen="False">
                  <Border Background="{DynamicResource PanelBgBrush}" BorderBrush="{DynamicResource BorderBrush}"
                          BorderThickness="1" CornerRadius="3" Margin="0,3,0,0" MinWidth="210">
                    <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle"/>
                  </Border>
                </Popup>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="bord" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
              </Trigger>
              <Trigger Property="IsSubmenuOpen" Value="True">
                <Setter TargetName="bord" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="MenuItem">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="MenuItem">
            <Border x:Name="ligne" Background="Transparent" Padding="14,7">
              <ContentPresenter ContentSource="Header" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="ligne" Property="Background" Value="{DynamicResource ButtonBgBrush}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="Menu">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
    </Style>
    <Style TargetType="Separator">
      <Setter Property="Height" Value="1"/>
      <Setter Property="Margin" Value="8,4,8,4"/>
      <Setter Property="Background" Value="{DynamicResource BorderBrush}"/>
    </Style>

    <!-- Info-bulles assorties au thème sombre (la bulle système jaune jurerait). -->
    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="{DynamicResource PanelBgBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="9,6"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="MaxWidth" Value="320"/>
      <Setter Property="HasDropShadow" Value="True"/>
    </Style>
  </Window.Resources>

  <Grid x:Name="GridPrincipal" Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="190"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- En-tête -->
    <Grid Grid.Row="0" Margin="0,0,0,10">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0">
        <StackPanel Orientation="Horizontal">
          <TextBlock x:Name="TxtTitre" Text="MADTWEAK" FontSize="21" FontWeight="SemiBold" Foreground="{DynamicResource AccentBrush}"/>
          <Border x:Name="BorderScore" Background="{DynamicResource ButtonBgBrush}" BorderBrush="{DynamicResource BorderBrush}"
                  BorderThickness="1" CornerRadius="4" Padding="9,2" Margin="14,0,0,0" VerticalAlignment="Center"
                  Visibility="Collapsed"
                  ToolTip="{{entete.score.info}}">
            <TextBlock x:Name="TxtScore" FontSize="13" FontWeight="SemiBold"/>
          </Border>
        </StackPanel>
        <TextBlock x:Name="TxtSysteme" FontSize="11" Foreground="{DynamicResource TextMutedBrush}" Margin="0,3,0,0"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
        <TextBlock Text="{{entete.fond}}" VerticalAlignment="Center" Margin="0,0,5,0" Foreground="{DynamicResource TextMutedBrush}"/>
        <ComboBox x:Name="ComboFond" Width="160" Height="26" VerticalContentAlignment="Center" Margin="0,0,16,0"
                  ToolTip="{{entete.fond.info}}"/>
        <TextBlock Text="{{entete.accent}}" VerticalAlignment="Center" Margin="0,0,5,0" Foreground="{DynamicResource TextMutedBrush}"/>
        <ComboBox x:Name="ComboAccent" Width="170" Height="26" VerticalContentAlignment="Center" Margin="0,0,16,0"
                  ToolTip="{{entete.accent.info}}"/>
        <TextBlock Text="{{entete.theme}}" VerticalAlignment="Center" Margin="0,0,5,0" Foreground="{DynamicResource TextMutedBrush}"/>
        <ComboBox x:Name="ComboTheme" Width="160" Height="26" VerticalContentAlignment="Center"
                  ToolTip="{{entete.theme.info}}"/>
        <TextBlock Text="{{entete.langue}}" VerticalAlignment="Center" Margin="16,0,5,0" Foreground="{DynamicResource TextMutedBrush}"/>
        <ComboBox x:Name="ComboLangue" Width="118" Height="26" VerticalContentAlignment="Center"
                  ToolTip="{{entete.langue.info}}"/>
        <StackPanel x:Name="PanelEcran" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="{{entete.ecran}}" VerticalAlignment="Center" Margin="16,0,5,0" Foreground="{DynamicResource TextMutedBrush}"/>
          <Slider x:Name="SliderEcran" Width="110" Minimum="10" Maximum="100" TickFrequency="5" IsSnapToTickEnabled="True" VerticalAlignment="Center"
                  ToolTip="{{entete.ecran.info}}"/>
          <TextBlock x:Name="TxtEcran" Width="38" VerticalAlignment="Center" Margin="6,0,0,0" Foreground="{DynamicResource TextMutedBrush}"/>
        </StackPanel>
      </StackPanel>
    </Grid>

    <!-- Profils -->
    <Border x:Name="BorderProfils" Grid.Row="1" Background="{DynamicResource PanelBgBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1"
            CornerRadius="4" Padding="10" Margin="0,0,0,10">
      <StackPanel>
        <TextBlock Text="{{profils.entete}}"
                   FontSize="11" Foreground="{DynamicResource TextMutedBrush}" Margin="0,0,0,8"/>
        <StackPanel x:Name="PanelProfils"/>
      </StackPanel>
    </Border>

    <!-- Onglets de tweaks -->
    <TabControl x:Name="TabsCategories" Grid.Row="2" Background="{DynamicResource PanelBgBrush}" BorderBrush="{DynamicResource BorderBrush}"/>

    <!-- Actions -->
    <StackPanel Grid.Row="3" Margin="0,10,0,10">
      <!-- Barre d'outils. Les actions sont REGROUPÉES par intention dans des menus :
           15 boutons alignés obligeaient à lire toute la barre pour trouver le bon.
           Seuls restent visibles le filtre (usage constant) et « Gamer ROG ». -->
      <WrapPanel Margin="0,0,0,6">
        <TextBlock Text="{{barre.filtrer}}" VerticalAlignment="Center" Foreground="{DynamicResource TextMutedBrush}"/>
        <TextBox x:Name="TxtRecherche" Width="180" Height="28" VerticalContentAlignment="Center"
                 Background="{DynamicResource ButtonBgBrush}" Foreground="{DynamicResource TextPrimaryBrush}"
                 CaretBrush="{DynamicResource TextPrimaryBrush}"
                 BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" Padding="6,0" Margin="0,0,14,0"
                 ToolTip="{{barre.filtrer.info}}"/>

        <Menu Background="Transparent" VerticalAlignment="Center">
          <MenuItem Header="{{menu.analyser}}" Style="{StaticResource MenuTop}"
                    ToolTip="{{menu.analyser.info}}">
            <MenuItem x:Name="BtnEtatActuel" Header="{{act.etat}}"
                      ToolTip="{{act.etat.info}}"/>
            <MenuItem x:Name="BtnDerive" Header="{{act.derive}}"
                      ToolTip="{{act.derive.info}}"/>
            <Separator/>
            <MenuItem x:Name="BtnDemarrage" Header="{{act.demarrage}}"
                      ToolTip="{{act.demarrage.info}}"/>
            <MenuItem x:Name="BtnDisque" Header="{{act.disque}}"
                      ToolTip="{{act.disque.info}}"/>
            <MenuItem x:Name="BtnIndesirables" Header="{{act.indesirables}}"
                      ToolTip="{{act.indesirables.info}}"/>
            <Separator/>
            <MenuItem x:Name="BtnDiagnostic" Header="{{act.diagnostic}}"
                      ToolTip="{{act.diagnostic.info}}"/>
            <MenuItem x:Name="BtnRapport" Header="{{act.rapport}}"
                      ToolTip="{{act.rapport.info}}"/>
          </MenuItem>

          <MenuItem Header="{{menu.annuler}}" Style="{StaticResource MenuTop}"
                    ToolTip="{{menu.annuler.info}}">
            <MenuItem x:Name="BtnRestaurer" Header="{{act.restaurer}}"
                      ToolTip="{{act.restaurer.info}}"/>
            <MenuItem x:Name="BtnRestaurerSelectif" Header="{{act.restaurer.sel}}"
                      ToolTip="{{act.restaurer.sel.info}}"/>
            <Separator/>
            <MenuItem x:Name="BtnPointsResto" Header="{{act.points}}"
                      ToolTip="{{act.points.info}}"/>
          </MenuItem>

          <MenuItem Header="{{menu.config}}" Style="{StaticResource MenuTop}"
                    ToolTip="{{menu.config.info}}">
            <MenuItem x:Name="BtnEnregistrerProfil" Header="{{act.profil.enr}}"
                      ToolTip="{{act.profil.enr.info}}"/>
            <Separator/>
            <MenuItem x:Name="BtnExportConfig" Header="{{act.export}}"
                      ToolTip="{{act.export.info}}"/>
            <MenuItem x:Name="BtnImportConfig" Header="{{act.import}}"
                      ToolTip="{{act.import.info}}"/>
            <Separator/>
            <MenuItem x:Name="BtnMaintenance" Header="{{act.maintenance}}"
                      ToolTip="{{act.maintenance.info}}"/>
          </MenuItem>

          <MenuItem Header="{{menu.affichage}}" Style="{StaticResource MenuTop}"
                    ToolTip="{{menu.affichage.info}}">
            <MenuItem x:Name="BtnToggleProfils" Header="{{act.profils.cacher}}"
                      ToolTip="{{act.profils.info}}"/>
            <MenuItem x:Name="BtnToggleJournal" Header="{{act.journal.cacher}}"
                      ToolTip="{{act.journal.info}}"/>
          </MenuItem>
        </Menu>

        <Button x:Name="BtnGamerRog" Content="{{act.gamer}}" Background="#FF5A1220" BorderBrush="#FF8A1E33"
                FontWeight="SemiBold" Margin="8,0,0,0" VerticalAlignment="Center"
                ToolTip="{{act.gamer.info}}"/>
      </WrapPanel>
      <Grid>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
          <Button x:Name="BtnToutCocher" Content="{{act.cocher}}"
                  ToolTip="{{act.cocher.info}}"/>
          <Button x:Name="BtnToutDecocher" Content="{{act.decocher}}"
                  ToolTip="{{act.decocher.info}}"/>
          <CheckBox x:Name="ChkPointRestauration" Content="{{act.pointresto}}"
                    IsChecked="True" VerticalAlignment="Center" Margin="12,0,0,0"
                    ToolTip="{{act.pointresto.info}}"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <TextBlock x:Name="TxtSelection" VerticalAlignment="Center" Margin="0,0,14,0"
                     FontSize="12" Foreground="{DynamicResource TextMutedBrush}"/>
          <Button x:Name="BtnSimuler" Content="{{act.simuler}}" Background="#FF1F4A63" BorderBrush="#FF2E6F94"
                  ToolTip="{{act.simuler.info}}"/>
          <Button x:Name="BtnAppliquer" Content="{{act.appliquer}}" Background="#FF16603A" BorderBrush="#FF1F8A52"
                  FontWeight="SemiBold" Margin="0,0,8,0"
                  ToolTip="{{act.appliquer.info}}"/>
          <Button x:Name="BtnRedemarrer" Content="{{act.redemarrer}}" Background="#FF7D2323" BorderBrush="#FFA32E2E"
                  FontWeight="SemiBold" Margin="0"
                  ToolTip="{{act.redemarrer.info}}"/>
        </StackPanel>
      </Grid>
    </StackPanel>

    <!-- Journal -->
    <Border x:Name="BorderJournal" Grid.Row="4" Background="{DynamicResource JournalBgBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="4">
      <TextBox x:Name="TxtJournal" IsReadOnly="True" Background="Transparent" BorderThickness="0"
               Foreground="{DynamicResource JournalFgBrush}" FontFamily="Consolas" FontSize="12"
               VerticalScrollBarVisibility="Auto" TextWrapping="NoWrap" Padding="8"/>
    </Border>

    <StackPanel Grid.Row="5" Margin="0,8,0,0">
      <ProgressBar x:Name="BarreProgression" Height="6" Minimum="0" Maximum="100" Value="0"
                   Foreground="{DynamicResource AccentBrush}" Background="{DynamicResource ButtonBgBrush}"
                   BorderThickness="0" Visibility="Collapsed" Margin="0,0,0,5"/>
      <TextBlock x:Name="TxtEtat" FontSize="11" Foreground="{DynamicResource TextMutedBrush}"/>
    </StackPanel>
  </Grid>
</Window>
'@

function Invoke-BilanFinal {
    param($sync, [bool]$EnSimulation, [string[]]$Cles)
    # Filet habituel : une clé cochée qu'aucun tweak n'a atteinte = son menu
    # manque à Invoke-TousLesMenus.
    $jamais = @($Cles | Where-Object { $_ -notin $sync.Jouees })
    if ($jamais.Count -gt 0) {
        $script:JournalGui.AppendText("ANOMALIE INTERNE : $($jamais.Count) tweak(s) jamais atteint(s) : $($jamais -join ', ')`r`n")
        $script:JournalGui.AppendText("Leur menu n'est pas appelé par Invoke-TousLesMenus. C'est un défaut du script.`r`n")
    }
    $script:JournalGui.AppendText(("-" * 70) + "`r`n")
    if ($EnSimulation) {
        $bilan = "SIMULATION terminée : $($sync.Simu) modification(s) auraient été faites. Rien n'a été écrit."
    }
    else {
        $bilan = "Terminé : $($sync.OK) réussi(s), $($sync.Echec) échec(s)."
        if ($sync.Echec -gt 0) {
            $bilan += " Un échec est souvent un tweak qui REFUSE de s'appliquer parce qu'il serait nuisible ici."
        }
        # Mémorise les clés réellement appliquées : c'est ce qui permet ensuite de
        # détecter la « dérive » (tweaks revenus au défaut après une MAJ Windows).
        try { Save-ClesAppliquees @($sync.Jouees) } catch { }
    }
    $script:JournalGui.AppendText("$bilan`r`n")
    # Les redémarrages détectés dans le fil remontent dans l'état principal, pour
    # qu'Invoke-RedemarrageFinal les propose à la fermeture de l'interface.
    if (@($sync.Redem).Count -gt 0) {
        $script:JournalGui.AppendText("`r`n$(@($sync.Redem).Count) tweak(s) n'auront d'effet qu'APRÈS un redémarrage :`r`n")
        foreach ($t in $sync.Redem) {
            $script:JournalGui.AppendText("   - $t`r`n")
            if ($t -notin $script:RedemarrageRequis) { $script:RedemarrageRequis += $t }
        }
    }
    $script:JournalGui.ScrollToEnd()
    $script:GuiTxtEtat.Text = $bilan
    $script:GuiOccupe = $false
    # La barre atteint 100 %, puis disparaît : le travail est fini.
    if ($script:GuiProgress) {
        $script:GuiProgress.Value = 100
        $script:GuiProgress.Visibility = 'Collapsed'
    }
    $script:GuiFenetre.FindName("BtnAppliquer").IsEnabled = $true
    $script:GuiFenetre.FindName("BtnSimuler").IsEnabled = $true
    $script:GuiFenetre.FindName("BtnRedemarrer").IsEnabled = $true
}

function Invoke-LancerGui {
    param([bool]$EnSimulation)
    $cles = @($script:GuiCases.Keys | Where-Object { $script:GuiCases[$_].IsChecked })
    if ($cles.Count -eq 0) {
        $script:JournalGui.AppendText("`r`nAucun tweak coché : rien à faire.`r`n")
        $script:JournalGui.ScrollToEnd()
        return
    }

    $script:GuiOccupe = $true
    $script:GuiFenetre.FindName("BtnAppliquer").IsEnabled = $false
    $script:GuiFenetre.FindName("BtnSimuler").IsEnabled = $false
    $script:GuiFenetre.FindName("BtnRedemarrer").IsEnabled = $false
    # Barre de progression : repartie de zéro et rendue visible pour ce lot.
    if ($script:GuiProgress) {
        $script:GuiProgress.Value = 0
        $script:GuiProgress.Visibility = 'Visible'
    }
    $script:GuiTxtEtat.Text = if ($EnSimulation) { "Simulation en arrière-plan — la fenêtre reste réactive." } else { "Application en arrière-plan — la fenêtre reste réactive, laisse-la travailler." }
    $script:JournalGui.AppendText("`r`n" + ("=" * 70) + "`r`n")
    $script:JournalGui.AppendText($(if ($EnSimulation) {
        "SIMULATION de $($cles.Count) tweak(s) — RIEN ne sera écrit sur la machine.`r`n" }
        else { "APPLICATION de $($cles.Count) tweak(s).`r`n" }))
    $script:JournalGui.AppendText(("=" * 70) + "`r`n")

    $pointResto = (-not $EnSimulation) -and [bool]$script:GuiFenetre.FindName("ChkPointRestauration").IsChecked

    # À la fin du fil (sur le thread de l'interface), on affiche le bilan.
    $onFini = {
        param($sync)
        Invoke-BilanFinal $sync $EnSimulation $cles
    }.GetNewClosure()

    try {
        Start-ApplyArrierePlan -Journal $script:JournalGui -Cles $cles -EnSimulation $EnSimulation -PointResto $pointResto -OnFini $onFini
    }
    catch {
        # Repli : aucun fil possible (script sans fichier source). On exécute en
        # direct -- la fenêtre se fige, mais le travail se fait. Cas très rare :
        # Lancer.bat passe toujours par -File, donc le fichier existe.
        $script:JournalGui.AppendText("(Arrière-plan indisponible : exécution directe, la fenêtre peut se figer.)`r`n")
        Update-InterfaceGui
        $script:Simulation = $EnSimulation
        $script:CompteurOK = 0; $script:CompteurEchec = 0
        $script:SimuCompteur = 0; $script:ClesJouees = @()
        $redAvant = @($script:RedemarrageRequis)
        try {
            if ($pointResto) { New-PointRestauration -Description "MadTweak (interface)" | Out-Null }
            $script:ProfilActif = $cles
            Invoke-TousLesMenus
        }
        catch { $script:JournalGui.AppendText("ERREUR : $($_.Exception.Message)`r`n") }
        finally { $script:ProfilActif = $null; $script:Simulation = $false }
        $faux = @{
            OK = $script:CompteurOK; Echec = $script:CompteurEchec; Simu = $script:SimuCompteur
            Jouees = @($script:ClesJouees); Redem = @($script:RedemarrageRequis | Where-Object { $_ -notin $redAvant })
        }
        Invoke-BilanFinal $faux $EnSimulation $cles
    }
}

$script:Themes = [ordered]@{
    "Sombre Moderne" = @{
        WindowBg      = "#FF1B1B1F"
        PanelBg       = "#FF232329"
        TextPrimary   = "#FFD8D8DC"
        TextMuted     = "#FF8A8A92"
        Accent        = "#FF4FA6E8"
        Border        = "#FF3F3F46"
        ButtonBg      = "#FF2D2D33"
        JournalBg     = "#FF141417"
        JournalFg     = "#FFC8C8CE"
    }
    "Abysse" = @{
        WindowBg      = "#FF0A0F1D"
        PanelBg       = "#FF11192E"
        TextPrimary   = "#FFE0E6ED"
        TextMuted     = "#FF6B7C96"
        Accent        = "#FF00D2FF"
        Border        = "#FF233554"
        ButtonBg      = "#FF1B2A4A"
        JournalBg     = "#FF070B14"
        JournalFg     = "#FF90A4AE"
    }
    "Dracula" = @{
        WindowBg      = "#FF282A36"
        PanelBg       = "#FF1E1F29"
        TextPrimary   = "#FFF8F8F2"
        TextMuted     = "#FF6272A4"
        Accent        = "#FFBD93F9"
        Border        = "#FF44475A"
        ButtonBg      = "#FF343746"
        JournalBg     = "#FF1A1A24"
        JournalFg     = "#FF50FA7B"
    }
    "Foret Emeraude" = @{
        WindowBg      = "#FF0F1715"
        PanelBg       = "#FF16221F"
        TextPrimary   = "#FFE2E8F0"
        TextMuted     = "#FF64748B"
        Accent        = "#FF10B981"
        Border        = "#FF2D3F3A"
        ButtonBg      = "#FF1E2E2A"
        JournalBg     = "#FF0A0F0E"
        JournalFg     = "#FF34D399"
    }
    "Cyberpunk" = @{
        WindowBg      = "#FF0D0211"
        PanelBg       = "#FF1A0524"
        TextPrimary   = "#FFFFF5FA"
        TextMuted     = "#FFA131B6"
        Accent        = "#FFFF007F"
        Border        = "#FF520775"
        ButtonBg      = "#FF330647"
        JournalBg     = "#FF050007"
        JournalFg     = "#FF39FF14"
    }
    "Clair Elegant" = @{
        WindowBg      = "#FFF0F2F5"
        PanelBg       = "#FFFFFFFF"
        TextPrimary   = "#FF1A1D20"
        TextMuted     = "#FF70757A"
        Accent        = "#FF0066CC"
        Border        = "#FFD1D5DB"
        ButtonBg      = "#FFE5E7EB"
        JournalBg     = "#FFF9FAFB"
        JournalFg     = "#FF374151"
    }
}

function Set-Theme {
    param(
        [Parameter(Mandatory)]
        $Fenetre,
        [Parameter(Mandatory)]
        [string]$NomTheme
    )
    if (-not $script:Themes.Contains($NomTheme)) { return }
    $t = $script:Themes[$NomTheme]
    
    $keys = @("WindowBg", "PanelBg", "TextPrimary", "TextMuted", "Accent", "Border", "ButtonBg", "JournalBg", "JournalFg")
    foreach ($k in $keys) {
        $brushKey = $k + "Brush"
        # Piège vérifié : « New-Object SolidColorBrush -ArgumentList $couleur » avec
        # une couleur BOXÉE (ce que renvoie ConvertFromString) crée un pinceau
        # malformé. Quand WPF ré-évalue les DynamicResource, il échoue avec
        # « #XXXXXX n'est pas une valeur valide pour Background » -- ce qui faisait
        # planter TOUTE l'interface au démarrage. La parade : caster explicitement
        # en [Color], construire via ::new(), et geler le pinceau.
        $color = [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString($t[$k])
        $brush = [System.Windows.Media.SolidColorBrush]::new($color)
        $brush.Freeze()
        $Fenetre.Resources[$brushKey] = $brush
    }
    
    if ($script:DossierDonnees) {
        try {
            [System.IO.File]::WriteAllText((Join-Path $script:DossierDonnees "theme.txt"), $NomTheme, [System.Text.Encoding]::UTF8)
        } catch {}
    }
}

function Add-LigneComboClavier {
    # Ajoute au panneau une étiquette + une liste déroulante thémée, et la retourne.
    # Le style de ComboBox (template qui tue les « carrés blancs ») est assigné
    # explicitement, comme pour les cases : le style implicite ne suffit pas toujours
    # sur un contrôle créé par code.
    param($Panneau, $Style, [string]$Etiquette, [object[]]$Elements, [int]$IndexSel = 0)
    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = $Etiquette
    $lbl.Margin = "0,10,0,3"
    $lbl.FontWeight = "SemiBold"
    $Panneau.Children.Add($lbl) | Out-Null
    $cb = New-Object System.Windows.Controls.ComboBox
    if ($Style) { $cb.Style = $Style }
    $cb.Width = 260
    $cb.HorizontalAlignment = "Left"
    foreach ($el in $Elements) { $cb.Items.Add($el) | Out-Null }
    if ($cb.Items.Count -gt 0) { $cb.SelectedIndex = [Math]::Min($IndexSel, $cb.Items.Count - 1) }
    $Panneau.Children.Add($cb) | Out-Null
    return $cb
}

function Add-LigneSliderClavier {
    # Ajoute une étiquette + un curseur 0-100 %. L'étiquette affiche la valeur en direct.
    # Pas de closure : la référence de l'étiquette et le libellé voyagent dans le Tag
    # du curseur (GetNewClosure casserait la portée $script: -- à proscrire ici).
    param($Panneau, [string]$Etiquette, [int]$Valeur)
    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Margin = "0,10,0,3"
    $lbl.FontWeight = "SemiBold"
    $lbl.Text = "$Etiquette : $([int]$Valeur) %"
    $Panneau.Children.Add($lbl) | Out-Null
    $sl = New-Object System.Windows.Controls.Slider
    $sl.Minimum = 0; $sl.Maximum = 100; $sl.Width = 260; $sl.HorizontalAlignment = "Left"
    $sl.TickFrequency = 5; $sl.IsSnapToTickEnabled = $true; $sl.Value = $Valeur
    $sl.Tag = @{ Label = $lbl; Nom = $Etiquette }
    $sl.Add_ValueChanged({ $this.Tag.Label.Text = "$($this.Tag.Nom) : $([int]$this.Value) %" }) | Out-Null
    $Panneau.Children.Add($sl) | Out-Null
    return $sl
}

function Add-PageMateriel {
    # Ajoute l'onglet « Matériel » : le mode d'alimentation Windows (toujours) et, si
    # un clavier ASUS ROG compatible répond, les réglages RGB. L'onglet s'adapte au
    # matériel : la section clavier n'apparaît que si le clavier est là.
    # Suppose $script:GuiTabs déjà défini par Show-Gui.
    param($Fenetre)

    $styleCombo = $null
    try { $styleCombo = $Fenetre.FindResource([System.Windows.Controls.ComboBox]) } catch { }

    $pile = New-Object System.Windows.Controls.StackPanel
    $pile.Margin = "16"

    # --- Section CAPTEURS (en direct) : GPU (nvidia-smi) + ventilateurs (ACPI ASUS) ---
    $aGpu = [bool](Get-Command nvidia-smi -ErrorAction SilentlyContinue) -or (Test-Path "$env:SystemRoot\System32\nvidia-smi.exe")
    if ($aGpu -or (Test-ClavierAura)) {
        $tCap = New-Object System.Windows.Controls.TextBlock
        $tCap.Text = "Capteurs (en direct)"
        $tCap.FontWeight = "Bold"; $tCap.FontSize = 15; $tCap.Margin = "0,0,0,4"
        $pile.Children.Add($tCap) | Out-Null

        $script:MatLblGpu = New-Object System.Windows.Controls.TextBlock
        $script:MatLblGpu.FontSize = 13; $script:MatLblGpu.Margin = "0,2,0,2"
        $pile.Children.Add($script:MatLblGpu) | Out-Null
        $script:MatLblFans = New-Object System.Windows.Controls.TextBlock
        $script:MatLblFans.FontSize = 13; $script:MatLblFans.Margin = "0,2,0,2"
        $pile.Children.Add($script:MatLblFans) | Out-Null

        $majCapteurs = {
            $c = Get-CapteursMateriel
            $script:MatLblGpu.Text = if ($null -ne $c.GpuTemp) { "GPU : $($c.GpuTemp) °C   ·   charge $($c.GpuLoad) %" } else { "GPU : —" }
            $fc = if ($c.FanCpu) { "$($c.FanCpu) tr/min" } else { "—" }
            $fg = if ($c.FanGpu) { "$($c.FanGpu) tr/min" } else { "—" }
            $suffixe = if (-not $c.FanCpu) { "   (ventilos lisibles seulement en admin, via Lancer.bat)" } else { "" }
            $script:MatLblFans.Text = "Ventilateurs : CPU $fc   ·   GPU $fg$suffixe"
        }
        & $majCapteurs
        $script:GuiTimerCapteurs = New-Object System.Windows.Threading.DispatcherTimer
        $script:GuiTimerCapteurs.Interval = [TimeSpan]::FromMilliseconds(2500)
        $script:GuiTimerCapteurs.Add_Tick($majCapteurs) | Out-Null
        $script:GuiTimerCapteurs.Start()
        # La minuterie doit mourir avec la fenêtre, sinon elle tourne dans le vide.
        $Fenetre.Add_Closed({ if ($script:GuiTimerCapteurs) { $script:GuiTimerCapteurs.Stop() } }) | Out-Null

        $noteCap = New-Object System.Windows.Controls.TextBlock
        $noteCap.Text = "Température des cœurs CPU non affichée : Windows ne l'expose pas sans pilote dédié (HWiNFO, G-Helper). Le GPU, lui, est lu directement."
        $noteCap.TextWrapping = "Wrap"; $noteCap.FontSize = 11; $noteCap.Margin = "0,4,0,0"
        $noteCap.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextMutedBrush")
        $pile.Children.Add($noteCap) | Out-Null

        $sepC = New-Object System.Windows.Controls.Border
        $sepC.Height = 1; $sepC.Margin = "0,14,0,14"
        $sepC.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BorderBrush")
        $pile.Children.Add($sepC) | Out-Null
    }

    # --- Section ALIMENTATION (toujours présente) ---
    $tAlim = New-Object System.Windows.Controls.TextBlock
    $tAlim.Text = "Mode d'alimentation Windows"
    $tAlim.FontWeight = "Bold"; $tAlim.FontSize = 15; $tAlim.Margin = "0,0,0,4"
    $pile.Children.Add($tAlim) | Out-Null

    $sAlim = New-Object System.Windows.Controls.TextBlock
    $sAlim.Text = "Agit sur le boost et l'EPP du CPU côté Windows. Ce n'est PAS le Turbo ASUS (ventilateurs + TDP) : celui-ci n'est pas pilotable depuis un script — mesuré, la fréquence CPU sous charge est identique en Silencieux et Turbo. Pour un vrai contrôle des ventilateurs, utilise G-Helper."
    $sAlim.TextWrapping = "Wrap"; $sAlim.FontSize = 11; $sAlim.Margin = "0,0,0,6"
    $sAlim.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextMutedBrush")
    $pile.Children.Add($sAlim) | Out-Null

    $script:MatComboAlim = Add-LigneComboClavier $pile $styleCombo "Profil" @($script:ModesAlimentation.Keys) 1
    $script:MatComboAlim.ToolTip = "Mode d'alimentation Windows : agit sur le boost et l'EPP du CPU. Ce n'est PAS le Turbo ASUS (ventilateurs), qui n'est pas pilotable depuis un script."
    $script:MatComboAlim.Add_SelectionChanged({
        $m = [string]$script:MatComboAlim.SelectedItem
        if (-not $m) { return }
        if (Set-ModeAlimentation -Mode $m) { $script:JournalGui.AppendText("Mode d'alimentation Windows : « $m ».`r`n") }
        else { $script:JournalGui.AppendText("Mode d'alimentation : échec (« $m »).`r`n") }
        $script:JournalGui.ScrollToEnd()
    }) | Out-Null

    # --- Section CLAVIER RGB (seulement si le matériel répond) ---
    if (Test-ClavierAura) {
        $sep = New-Object System.Windows.Controls.Border
        $sep.Height = 1; $sep.Margin = "0,18,0,14"
        $sep.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BorderBrush")
        $pile.Children.Add($sep) | Out-Null

        $tKb = New-Object System.Windows.Controls.TextBlock
        $tKb.Text = "Clavier RGB ASUS ROG"
        $tKb.FontWeight = "Bold"; $tKb.FontSize = 15; $tKb.Margin = "0,0,0,4"
        $pile.Children.Add($tKb) | Out-Null

        $sKb = New-Object System.Windows.Controls.TextBlock
        $sKb.Text = "Effet, couleur et luminosité s'appliquent au bouton ci-dessous. La couleur suit aussi l'accent Windows du haut. La luminosité atténue la couleur envoyée ; le niveau matériel du rétroéclairage se règle avec Fn + F3/F4."
        $sKb.TextWrapping = "Wrap"; $sKb.FontSize = 11; $sKb.Margin = "0,0,0,6"
        $sKb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextMutedBrush")
        $pile.Children.Add($sKb) | Out-Null

        $script:KbComboEffet   = Add-LigneComboClavier $pile $styleCombo "Effet"                   @($script:EffetsClavier.Keys) 0
        $script:KbComboEffet.ToolTip = "Effet du rétroéclairage : statique, respiration, stroboscope ou arc-en-ciel."
        $script:KbComboCouleur = Add-LigneComboClavier $pile $styleCombo "Couleur"                 @($script:AccentsWindows.Keys) 0
        $script:KbComboCouleur.ToolTip = "Couleur du clavier (7 presets ROG). Ignorée par l'effet arc-en-ciel."
        $script:KbComboVitesse = Add-LigneComboClavier $pile $styleCombo "Vitesse (effets animés)" @($script:VitessesClavier.Keys) 1
        $script:KbComboVitesse.ToolTip = "Vitesse des effets animés (respiration, arc-en-ciel...)."
        $script:KbSliderLum    = Add-LigneSliderClavier $pile "Luminosité du clavier" $script:LuminositeClavier
        $script:KbSliderLum.ToolTip = "Luminosité du clavier (0-100 %), obtenue en atténuant la couleur envoyée. Le niveau matériel se règle avec Fn + F3/F4."

        $btnKb = New-Object System.Windows.Controls.Button
        $btnKb.Content = "Appliquer au clavier"
        $btnKb.Width = 200
        $btnKb.HorizontalAlignment = "Left"
        $btnKb.Margin = "0,18,0,0"
        $btnKb.ToolTip = "Envoie l'effet, la couleur, la vitesse et la luminosité choisis au clavier RGB."
        $btnKb.Add_Click({
            try {
                $eff = [string]$script:KbComboEffet.SelectedItem
                $nomCoul = [string]$script:KbComboCouleur.SelectedItem
                $vit = [string]$script:KbComboVitesse.SelectedItem
                $lum = [int]$script:KbSliderLum.Value
                $script:LuminositeClavier = $lum
                $c = $script:AccentsWindows[$nomCoul]
                if (Set-ClavierAura -R $c.R -G $c.G -B $c.B -Mode $eff -Vitesse $vit -Luminosite $lum) {
                    $script:JournalGui.AppendText("Clavier RGB : effet « $eff », couleur « $nomCoul », vitesse $vit, luminosité $lum %.`r`n")
                }
                else {
                    $script:JournalGui.AppendText("Clavier RGB : le clavier n'a pas répondu.`r`n")
                }
                $script:JournalGui.ScrollToEnd()
            }
            catch {
                $script:JournalGui.AppendText("Clavier RGB : échec — $($_.Exception.Message)`r`n")
                $script:JournalGui.ScrollToEnd()
            }
        }) | Out-Null
        $pile.Children.Add($btnKb) | Out-Null
    }

    $def = New-Object System.Windows.Controls.ScrollViewer
    $def.VerticalScrollBarVisibility = "Auto"
    $def.Content = $pile
    $onglet = New-Object System.Windows.Controls.TabItem
    $onglet.Header = T 'onglet.materiel'
    $onglet.Content = $def
    $script:GuiTabs.Items.Add($onglet) | Out-Null
}

function Add-LigneTexte {
    # Étiquette + champ de saisie. -Secret produit un PasswordBox (points au lieu
    # des lettres) : même géométrie, contrôle différent, d'où le retour polymorphe.
    param($Panneau, [string]$Etiquette, [string]$Valeur = "", [switch]$Secret, [int]$Largeur = 300)
    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = $Etiquette
    $lbl.Margin = "0,10,0,3"
    $lbl.FontWeight = "SemiBold"
    $Panneau.Children.Add($lbl) | Out-Null
    $ctl = if ($Secret) { New-Object System.Windows.Controls.PasswordBox }
    else { New-Object System.Windows.Controls.TextBox }
    if (-not $Secret) { $ctl.Text = $Valeur }
    $ctl.Width = $Largeur
    $ctl.HorizontalAlignment = "Left"
    $Panneau.Children.Add($ctl) | Out-Null
    return $ctl
}

function Add-PageInstallation {
    # Onglet « Clé d'installation » : les mêmes questions que le menu console, mais
    # toutes visibles d'un coup. Aucune logique n'est dupliquée -- la page se contente
    # de remplir les paramètres de New-AutounattendXml, qui reste le seul endroit où
    # le XML est écrit.
    param($Fenetre)

    $styleCombo = $null
    try { $styleCombo = $Fenetre.FindResource([System.Windows.Controls.ComboBox]) } catch { }
    $styleCase = $null
    try { $styleCase = $Fenetre.FindResource([System.Windows.Controls.CheckBox]) } catch { }

    $pile = New-Object System.Windows.Controls.StackPanel
    $pile.Margin = "16"

    $titre = New-Object System.Windows.Controls.TextBlock
    $titre.Text = T 'inst.titre'
    $titre.FontWeight = "Bold"; $titre.FontSize = 15; $titre.Margin = "0,0,0,6"
    $pile.Children.Add($titre) | Out-Null

    foreach ($cle in 'inst.expl1', 'inst.expl2', 'inst.avert') {
        $t = New-Object System.Windows.Controls.TextBlock
        $t.Text = T $cle
        $t.TextWrapping = "Wrap"; $t.FontSize = 12; $t.Margin = "0,0,0,4"
        $t.MaxWidth = 720
        if ($cle -ne 'inst.expl1') { $t.Opacity = 0.85 }
        $pile.Children.Add($t) | Out-Null
    }

    # --- Cible ----------------------------------------------------------------
    $script:InstVersions = [ordered]@{ "Windows 11" = "11"; "Windows 10" = "10" }
    $script:InstCbVersion = Add-LigneComboClavier $pile $styleCombo (T 'inst.version') @($script:InstVersions.Keys) 0

    $script:InstEditions = [ordered]@{}
    $script:InstEditions[(T 'inst.edition.demander')] = ""
    $script:InstEditions["Pro"] = "Pro"
    $script:InstEditions[(T 'inst.edition.famille')] = "Famille"
    $script:InstEditions[(T 'inst.edition.entreprise')] = "Entreprise"
    $script:InstCbEdition = Add-LigneComboClavier $pile $styleCombo (T 'inst.edition') @($script:InstEditions.Keys) 0

    # Un nom d'édition absent de l'image fait échouer l'installation. Plutôt que de
    # faire parier l'utilisateur sur le contenu de son ISO, on la lit. Le menu console
    # propose la même chose : les deux interfaces doivent savoir faire la même chose.
    $btnIso = New-Object System.Windows.Controls.Button
    $btnIso.Content = T 'inst.edition.lire'
    $btnIso.Margin = "0,6,0,0"
    $btnIso.HorizontalAlignment = "Left"
    $btnIso.Add_Click({
            $dlg = New-Object Microsoft.Win32.OpenFileDialog
            $dlg.Filter = (T 'inst.edition.filtre')
            $dlg.Title = T 'inst.edition.lire'
            if (-not $dlg.ShowDialog()) { return }
            # Le montage prend quelques secondes et fige la fenêtre : sans ce curseur,
            # on croit à un blocage et on reclique.
            [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
            try {
                $trouvees = Get-EditionsImage -Chemin $dlg.FileName
                if ($trouvees.Count -eq 0) { throw (T 'inst.edition.vide') }
                $script:InstEditions = [ordered]@{}
                $script:InstEditions[(T 'inst.edition.demander')] = ""
                foreach ($e in $trouvees) { $script:InstEditions["$($e.Nom)  (index $($e.Index))"] = $e.Nom }
                $script:InstCbEdition.Items.Clear()
                foreach ($k in $script:InstEditions.Keys) { $script:InstCbEdition.Items.Add($k) | Out-Null }
                $script:InstCbEdition.SelectedIndex = if ($script:InstCbEdition.Items.Count -gt 1) { 1 } else { 0 }
                $script:JournalGui.AppendText(((T 'inst.jrn.edition.ok') -f $trouvees.Count) + "`r`n")
            }
            catch {
                $script:JournalGui.AppendText(((T 'inst.jrn.edition.echec') -f $_.Exception.Message) + "`r`n")
            }
            finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
            $script:JournalGui.ScrollToEnd()
        }) | Out-Null
    $pile.Children.Add($btnIso) | Out-Null

    $script:InstLangues = Get-LanguesInstallation
    $script:InstCbLangue = Add-LigneComboClavier $pile $styleCombo (T 'inst.langue') @($script:InstLangues.Keys) 0

    $script:InstFuseaux = Get-FuseauxCourants
    $script:InstCbFuseau = Add-LigneComboClavier $pile $styleCombo (T 'inst.fuseau') @($script:InstFuseaux.Keys) 0

    # --- Compte ---------------------------------------------------------------
    $script:InstTxtUser = Add-LigneTexte $pile (T 'inst.compte')
    $script:InstTxtMdp = Add-LigneTexte $pile (T 'inst.mdp') -Secret
    $tMdp = New-Object System.Windows.Controls.TextBlock
    $tMdp.Text = T 'inst.mdp.avert'
    $tMdp.TextWrapping = "Wrap"; $tMdp.FontSize = 11; $tMdp.Margin = "0,3,0,0"; $tMdp.MaxWidth = 720
    $tMdp.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString('#FFD86A5A'))
    $pile.Children.Add($tMdp) | Out-Null
    $script:InstTxtMachine = Add-LigneTexte $pile (T 'inst.machine')

    # --- Profil ---------------------------------------------------------------
    $script:InstProfils = [ordered]@{}
    $script:InstProfils[(T 'inst.profil.aucun')] = ""
    foreach ($k in $script:Profils.Keys) { $script:InstProfils[(Get-NomProfil $k)] = $k }
    $script:InstCbProfil = Add-LigneComboClavier $pile $styleCombo (T 'inst.profil') @($script:InstProfils.Keys) 0

    # --- Applications ---------------------------------------------------------
    $lblApps = New-Object System.Windows.Controls.TextBlock
    $lblApps.Text = T 'inst.apps'
    $lblApps.Margin = "0,12,0,3"; $lblApps.FontWeight = "SemiBold"
    $pile.Children.Add($lblApps) | Out-Null

    $pileApps = New-Object System.Windows.Controls.StackPanel
    $script:InstAppsCases = @{}
    foreach ($nom in $script:CatalogueApps.Keys) {
        $c = New-Object System.Windows.Controls.CheckBox
        if ($styleCase) { $c.Style = $styleCase }
        $c.Content = $nom
        $c.Margin = "0,2,0,2"
        $pileApps.Children.Add($c) | Out-Null
        $script:InstAppsCases[$script:CatalogueApps[$nom]] = $c
    }
    $boiteApps = New-Object System.Windows.Controls.ScrollViewer
    $boiteApps.VerticalScrollBarVisibility = "Auto"
    $boiteApps.Height = 170; $boiteApps.Width = 420
    $boiteApps.HorizontalAlignment = "Left"
    $boiteApps.Padding = "8"
    $boiteApps.BorderThickness = "1"
    $boiteApps.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, "BorderBrush")
    $boiteApps.Content = $pileApps
    $pile.Children.Add($boiteApps) | Out-Null

    # --- Options ---------------------------------------------------------------
    $script:InstCaseTpm = New-Object System.Windows.Controls.CheckBox
    if ($styleCase) { $script:InstCaseTpm.Style = $styleCase }
    $script:InstCaseTpm.Content = T 'inst.tpm'
    $script:InstCaseTpm.Margin = "0,14,0,4"
    $pile.Children.Add($script:InstCaseTpm) | Out-Null

    $script:InstCaseDisque = New-Object System.Windows.Controls.CheckBox
    if ($styleCase) { $script:InstCaseDisque.Style = $styleCase }
    $script:InstCaseDisque.Content = T 'inst.disque'
    $script:InstCaseDisque.Margin = "0,4,0,4"
    $script:InstCaseDisque.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString('#FFD86A5A'))
    $pile.Children.Add($script:InstCaseDisque) | Out-Null

    # Le disque 0 est l'habitude, pas une garantie : sur une machine à plusieurs
    # disques, ce peut être celui des données. Se tromper ici efface le mauvais.
    $script:InstTxtDisque = Add-LigneTexte $pile (T 'inst.disque.numero') "0" -Largeur 80

    # La case la plus destructrice de tout l'outil : on redemande, explicitement,
    # au moment où elle est cochée. Décocher ne demande évidemment rien.
    $script:InstCaseDisque.Add_Checked({
            $r = [System.Windows.MessageBox]::Show(
                (T 'inst.disque.confirm'), (T 'inst.disque.titre'),
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning)
            if ($r -ne [System.Windows.MessageBoxResult]::Yes) { $this.IsChecked = $false }
        }) | Out-Null

    # --- Génération ------------------------------------------------------------
    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = T 'inst.generer'
    $btn.Margin = "0,16,0,0"
    $btn.HorizontalAlignment = "Left"
    $btn.Add_Click({
            try {
                $user = $script:InstTxtUser.Text.Trim()
                if (-not $user) {
                    $script:JournalGui.AppendText((T 'inst.jrn.sansnom') + "`r`n")
                    $script:JournalGui.ScrollToEnd()
                    return
                }
                $apps = @()
                foreach ($id in $script:InstAppsCases.Keys) {
                    if ($script:InstAppsCases[$id].IsChecked) { $apps += $id }
                }
                $profil = $script:InstProfils[$script:InstCbProfil.SelectedItem]
                $dossier = Join-Path ([Environment]::GetFolderPath("Desktop")) "madtweak-installation"
                $chemin = Join-Path $dossier "autounattend.xml"

                if ($script:Simulation) {
                    $script:JournalGui.AppendText(((T 'inst.jrn.simu') -f $chemin, $apps.Count) + "`r`n")
                    $script:JournalGui.ScrollToEnd()
                    return
                }
                if (-not (Test-Path $dossier)) { New-Item -ItemType Directory -Path $dossier -Force | Out-Null }

                $p = @{
                    Chemin         = $chemin
                    NomUtilisateur = $user
                    MotDePasse     = $script:InstTxtMdp.Password
                    NomMachine     = $script:InstTxtMachine.Text.Trim()
                    Langue         = $script:InstCbLangue.SelectedItem
                    Fuseau         = $script:InstFuseaux[$script:InstCbFuseau.SelectedItem]
                    Version        = $script:InstVersions[$script:InstCbVersion.SelectedItem]
                    Edition        = $script:InstEditions[$script:InstCbEdition.SelectedItem]
                    Apps           = $apps
                }
                if ($profil) { $p.Profil = $profil }
                if ($script:InstCaseTpm.IsChecked) { $p.SansTPM = $true }
                if ($script:InstCaseDisque.IsChecked) {
                    $p.EffacerDisque = $true
                    $nd = 0
                    if ([int]::TryParse($script:InstTxtDisque.Text.Trim(), [ref]$nd)) { $p.Disque = $nd }
                }

                New-AutounattendXml @p | Out-Null
                $script:JournalGui.AppendText(((T 'inst.jrn.ok') -f $chemin) + "`r`n")

                # Étape que l'outil sait faire lui-même : déposer les fichiers sur une
                # clé DÉJÀ préparée. On ne formate rien et on n'écrit aucune image ;
                # c'est le travail de Rufus, et il n'y a pas lieu de le refaire.
                $pretes = @(Get-ClesInstallation | Where-Object EstSupport)
                if ($pretes.Count -eq 0) {
                    $script:JournalGui.AppendText((T 'inst.jrn.cle.aucune') + "`r`n")
                }
                else {
                    foreach ($k in $pretes) {
                        $r = [System.Windows.MessageBox]::Show(
                            ((T 'inst.cle.confirm') -f $k.Lettre, $k.Nom, $k.Go),
                            (T 'inst.cle.titre'),
                            [System.Windows.MessageBoxButton]::YesNo,
                            [System.Windows.MessageBoxImage]::Question)
                        if ($r -ne [System.Windows.MessageBoxResult]::Yes) { continue }
                        $src = $null
                        if ($profil -and $PSCommandPath -and $PSCommandPath.EndsWith('.ps1')) { $src = $PSCommandPath }
                        try {
                            foreach ($fait in (Copy-FichiersVersCle -Lettre $k.Lettre -CheminXml $chemin -CheminMadTweak $src)) {
                                $script:JournalGui.AppendText(((T 'inst.jrn.cle.ok') -f $fait) + "`r`n")
                            }
                        }
                        catch {
                            $script:JournalGui.AppendText(((T 'inst.jrn.cle.echec') -f $_.Exception.Message) + "`r`n")
                        }
                        break
                    }
                }
                $script:JournalGui.AppendText((T 'inst.jrn.suite') + "`r`n")
                if ($profil) { $script:JournalGui.AppendText((T 'inst.jrn.profil') + "`r`n") }
                if ($script:InstTxtMdp.Password) { $script:JournalGui.AppendText((T 'inst.jrn.mdp') + "`r`n") }
                try { Start-Process explorer.exe $dossier } catch { }
            }
            catch {
                $script:JournalGui.AppendText(((T 'inst.jrn.echec') -f $_.Exception.Message) + "`r`n")
            }
            $script:JournalGui.ScrollToEnd()
        }) | Out-Null
    $pile.Children.Add($btn) | Out-Null

    $def = New-Object System.Windows.Controls.ScrollViewer
    $def.VerticalScrollBarVisibility = "Auto"
    $def.Content = $pile
    $onglet = New-Object System.Windows.Controls.TabItem
    $onglet.Header = T 'onglet.installation'
    $onglet.Content = $def
    $script:GuiTabs.Items.Add($onglet) | Out-Null
}

function Update-ScoreGui {
    # Affiche la note de santé dans l'en-tête, colorée selon le niveau.
    param($Score)
    if (-not $script:GuiTxtScore) { return }
    $script:GuiTxtScore.Text = "Santé : $($Score.Note)/100  ·  $($Score.Mention)"
    $couleur = if ($Score.Note -ge 80) { '#FF5CC86E' } elseif ($Score.Note -ge 60) { '#FF8FC85C' } elseif ($Score.Note -ge 40) { '#FFCAA24A' } else { '#FFD86A5A' }
    $b = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString($couleur))
    $b.Freeze()
    $script:GuiTxtScore.Foreground = $b
    if ($script:GuiBorderScore) { $script:GuiBorderScore.Visibility = 'Visible' }
}

function Show-ListeModaleGui {
    # Fenêtre modale générique : un titre, des lignes de texte, un bouton Fermer.
    # Sert aux analyses (démarrage, disque, indésirables) : elles n'ont rien à
    # modifier, juste beaucoup à montrer -- et le journal serait trop étroit.
    param([string]$Titre, [string[]]$Lignes)
    $win = New-Object System.Windows.Window
    $win.Title = $Titre; $win.Width = 780; $win.Height = 560
    $win.WindowStartupLocation = 'CenterOwner'
    if ($script:GuiFenetre) { $win.Owner = $script:GuiFenetre; $win.Resources = $script:GuiFenetre.Resources; $win.Background = $script:GuiFenetre.Background }
    $grille = New-Object System.Windows.Controls.Grid; $grille.Margin = "12"
    foreach ($h in '*', 'Auto') { $rd = New-Object System.Windows.Controls.RowDefinition; $rd.Height = $h; $grille.RowDefinitions.Add($rd) }
    $box = New-Object System.Windows.Controls.TextBox
    $box.IsReadOnly = $true; $box.FontFamily = "Consolas"; $box.FontSize = 12
    $box.VerticalScrollBarVisibility = 'Auto'; $box.TextWrapping = 'NoWrap'; $box.BorderThickness = 0
    $box.Text = ($Lignes -join "`r`n")
    $box.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, "JournalBgBrush")
    $box.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "JournalFgBrush")
    [System.Windows.Controls.Grid]::SetRow($box, 0); $grille.Children.Add($box) | Out-Null
    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = "Fermer"; $btn.HorizontalAlignment = 'Right'; $btn.Margin = "0,10,0,0"
    $btn.Add_Click({ $script:ListeModaleWin.Close() }) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($btn, 1); $grille.Children.Add($btn) | Out-Null
    $win.Content = $grille
    $script:ListeModaleWin = $win
    $win.ShowDialog() | Out-Null
}

function New-IconeApp {
    # Dessine l'icône de la fenêtre (carré rouge arrondi + « M » blanc) à la volée.
    # Pas de fichier .ico binaire embarqué : même principe que les fonds « MadTrix ».
    param([int]$Taille = 64)
    $canvas = New-Object System.Windows.Controls.Canvas
    $canvas.Width = $Taille; $canvas.Height = $Taille
    $fond = New-Object System.Windows.Shapes.Rectangle
    $fond.Width = $Taille; $fond.Height = $Taille; $fond.RadiusX = $Taille * 0.22; $fond.RadiusY = $Taille * 0.22
    $grad = New-Object System.Windows.Media.LinearGradientBrush
    $grad.StartPoint = "0,0"; $grad.EndPoint = "1,1"
    $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString("#FFE01008"), 0)))
    $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString("#FF7A0A0A"), 1)))
    $fond.Fill = $grad
    $canvas.Children.Add($fond) | Out-Null
    $m = New-Object System.Windows.Controls.TextBlock
    $m.Text = "M"
    $m.FontFamily = New-Object System.Windows.Media.FontFamily "Segoe UI Black"
    $m.FontSize = $Taille * 0.62
    $m.FontWeight = [System.Windows.FontWeights]::Black
    $m.Foreground = [System.Windows.Media.Brushes]::White
    $m.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    [System.Windows.Controls.Canvas]::SetLeft($m, ($Taille - $m.DesiredSize.Width) / 2)
    [System.Windows.Controls.Canvas]::SetTop($m, ($Taille - $m.DesiredSize.Height) / 2)
    $canvas.Children.Add($m) | Out-Null
    $canvas.Measure([System.Windows.Size]::new($Taille, $Taille))
    $canvas.Arrange([System.Windows.Rect]::new(0, 0, $Taille, $Taille))
    $canvas.UpdateLayout()
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($Taille, $Taille, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($canvas)
    $rtb.Freeze()
    return $rtb
}

function Add-BoutonProfilPerso {
    # Ajoute à la zone Profils une ligne pour un profil personnalisé, chargée comme
    # un profil intégré (coche ses clés). Lit les clés dans $script:ProfilsPersoCache
    # (rafraîchi à chaque enregistrement), donc pas de closure fragile.
    param([string]$Nom)
    $cles = @($script:ProfilsPersoCache[$Nom])
    $ligne = New-Object System.Windows.Controls.DockPanel
    $ligne.Margin = "0,0,0,6"; $ligne.LastChildFill = $true
    $b = New-Object System.Windows.Controls.Button
    $b.Content = "$Nom  ($($cles.Count))"
    $b.Width = 180; $b.VerticalAlignment = 'Top'; $b.Margin = "0,0,10,0"; $b.Tag = $Nom
    $b.Add_Click({
        param($emetteur, $evt)
        if ($script:GuiOccupe) { return }
        $c = @($script:ProfilsPersoCache[$emetteur.Tag])
        foreach ($x in $script:GuiCases.Values) { $x.IsChecked = $false }
        $n = 0
        foreach ($cle in $c) { if ($script:GuiCases.ContainsKey($cle)) { $script:GuiCases[$cle].IsChecked = $true; $n++ } }
        $script:JournalGui.AppendText("`r`n=== Profil perso « $($emetteur.Tag) » : $n tweak(s) cochés. Ajuste puis « Appliquer ». ===`r`n")
        $script:JournalGui.ScrollToEnd()
    }) | Out-Null
    [System.Windows.Controls.DockPanel]::SetDock($b, 'Left')
    $ligne.Children.Add($b) | Out-Null
    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = "Profil personnalisé — $($cles.Count) tweak(s), enregistré par toi."
    $desc.TextWrapping = 'Wrap'; $desc.FontSize = 11; $desc.VerticalAlignment = 'Center'
    $desc.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextMutedBrush")
    $ligne.Children.Add($desc) | Out-Null
    $script:PanelProfilsRef.Children.Add($ligne) | Out-Null
}

function Show-Gui {
    # Levée ici = repli sur la console (voir le lancement). On charge WPF avant tout
    # le reste : si l'assembly manque, rien n'a encore été construit pour rien.
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Type -AssemblyName PresentationCore, WindowsBase -ErrorAction Stop

    $fenetre = [System.Windows.Markup.XamlReader]::Parse((Expand-Textes $script:XamlInterface))

    # Finition « produit » : icône dessinée, titre et en-tête versionnés.
    try { $fenetre.Icon = New-IconeApp 64 } catch { }
    $fenetre.Title = "MadTweak v$($script:Version) — $(T 'app.soustitre')"
    $titreHaut = $fenetre.FindName("TxtTitre")
    if ($titreHaut) { $titreHaut.Text = "MADTWEAK  v$($script:Version)" }
    # Le score reste caché tant que l'audit n'a pas tourné : afficher « 0/100 » avant
    # d'avoir mesuré serait un mensonge.
    $script:GuiTxtScore = $fenetre.FindName("TxtScore")
    $script:GuiBorderScore = $fenetre.FindName("BorderScore")

    # --- Sélecteur de langue. Le choix est ENREGISTRÉ (il survit à la fermeture) mais
    # ne redessine pas la fenêtre : reconstruire tout l'arbre WPF à chaud coûterait
    # bien plus qu'un redémarrage de l'outil, pour un réglage qu'on change une fois.
    $script:GuiComboLangue = $fenetre.FindName("ComboLangue")
    $noms = [ordered]@{ 'fr' = 'Français'; 'en' = 'English' }
    foreach ($n in $noms.Values) { $script:GuiComboLangue.Items.Add($n) | Out-Null }
    $script:GuiComboLangue.SelectedIndex = @($noms.Keys).IndexOf($script:LangueActive)
    $script:GuiComboLangue.Add_SelectionChanged({
        $codes = @('fr', 'en')
        $c = $codes[$script:GuiComboLangue.SelectedIndex]
        if (-not $c -or $c -eq $script:LangueActive) { return }
        try {
            Set-Langue $c
            $f = Join-Path $script:DossierDonnees "langue.txt"
            [System.IO.File]::WriteAllText($f, $c, [System.Text.Encoding]::UTF8)
            $script:JournalGui.AppendText("`r`n" + (T 'langue.redemarrer') + "`r`n")
            $script:JournalGui.ScrollToEnd()
        }
        catch { }
    }) | Out-Null

    $comboTheme = $fenetre.FindName("ComboTheme")
    foreach ($tName in $script:Themes.Keys) {
        $comboTheme.Items.Add($tName) | Out-Null
    }
    
    $themeParDefaut = "Sombre Moderne"
    $fichierTheme = Join-Path $script:DossierDonnees "theme.txt"
    if (Test-Path $fichierTheme) {
        try {
            $sauvegarde = [System.IO.File]::ReadAllText($fichierTheme, [System.Text.Encoding]::UTF8).Trim()
            if ($script:Themes.Contains($sauvegarde)) {
                $themeParDefaut = $sauvegarde
            }
        } catch {}
    }
    
    $comboTheme.SelectedItem = $themeParDefaut
    Set-Theme -Fenetre $fenetre -NomTheme $themeParDefaut

    $comboTheme.Add_SelectionChanged({
        $themeSelection = $comboTheme.SelectedItem
        if ($themeSelection) {
            Set-Theme -Fenetre $script:GuiFenetre -NomTheme $themeSelection
        }
    }) | Out-Null

    # --- Accent Windows : colore les barres de titre, la barre des tâches et le
    # menu Démarrer. Appelle Set-AccentWindows (module Signature), donc réversible
    # via « Annuler » (chaque valeur passe par Save-EtatAvant). L'application est
    # rapide (registre + diffusion), donc directe sur le thread de l'interface.
    $script:GuiComboAccent = $fenetre.FindName("ComboAccent")
    $script:AccentPlaceholder = T 'sel.choisir'
    $script:AccentDefaut = T 'sel.accent.defaut'
    $script:GuiComboAccent.Items.Add($script:AccentPlaceholder) | Out-Null
    foreach ($nomAcc in $script:AccentsWindows.Keys) { $script:GuiComboAccent.Items.Add($nomAcc) | Out-Null }
    $script:GuiComboAccent.Items.Add($script:AccentDefaut) | Out-Null
    # SelectedIndex AVANT de brancher le gestionnaire : sinon la sélection initiale
    # déclencherait un « changement » et appliquerait un accent au démarrage.
    $script:GuiComboAccent.SelectedIndex = 0
    $script:GuiComboAccent.Add_SelectionChanged({
        # Lié au vrai scope (pas de GetNewClosure) : $script: y résout.
        $sel = $script:GuiComboAccent.SelectedItem
        if (-not $sel -or $sel -eq $script:AccentPlaceholder) { return }
        if ($script:GuiOccupe) {
            $script:JournalGui.AppendText("Attends la fin de l'application en cours avant de changer l'accent Windows.`r`n")
            $script:JournalGui.ScrollToEnd()
            return
        }
        # Set-Accent/Restore-Accent écrivent déjà leur bilan via Write-Etat, qui va
        # dans le journal. On enveloppe juste pour attraper une éventuelle erreur.
        try {
            if ($sel -eq $script:AccentDefaut) {
                Restore-AccentWindows
            }
            else {
                # 1) Le fond MadTrix D'ABORD, assorti à la couleur de l'accent : bureau,
                #    barres et accent seront tous coordonnés. On génère avant l'accent
                #    car Set-AccentWindows relance l'Explorateur à la fin.
                $c = $script:AccentsWindows[$sel]
                $hex = "#{0:X2}{1:X2}{2:X2}" -f [int]$c.R, [int]$c.G, [int]$c.B
                # Style = celui choisi dans « Fond d'écran », sinon Matrix par défaut.
                $style = "matrix"
                $selFond = $script:GuiComboFond.SelectedItem
                if ($selFond -and $selFond -match '—\s*(Matrix|HUD|Neon)') { $style = $Matches[1].ToLower() }
                $res = Get-ResolutionPhysique
                $script:JournalGui.AppendText("`r`nGénération du fond MadTrix « $style » assorti à l'accent « $sel » ($hex)...`r`n")
                $script:JournalGui.ScrollToEnd(); Update-InterfaceGui
                $chemin = Join-Path $script:DossierDonnees "fond-madtrix-$style.png"
                New-FondSignature -Style $style -Largeur $res.L -Hauteur $res.H -Chemin $chemin -Couleur $hex | Out-Null
                Set-FondEcran -Chemin $chemin
                $script:JournalGui.AppendText("Fond assorti appliqué.`r`n")
                $script:JournalGui.ScrollToEnd(); Update-InterfaceGui
                # 2) Puis l'accent (barres de titre + barre des tâches).
                Set-AccentWindows -Nom $sel
            }
        }
        catch {
            $script:JournalGui.AppendText("Échec de l'accent/fond : $($_.Exception.Message)`r`n")
            $script:JournalGui.ScrollToEnd()
        }
    }) | Out-Null

    # --- Fond d'écran « MadTrix » : mêmes styles que le menu Signature (Matrix, HUD,
    # Neon). Régénéré à la résolution réelle et appliqué directement. Réversible :
    # Set-FondEcran mémorise le fond précédent (Save-EtatAvant + fichier).
    $script:GuiComboFond = $fenetre.FindName("ComboFond")
    $script:FondPlaceholder = T 'sel.choisir'
    $script:FondPrecedent = T 'sel.fond.precedent'
    $script:GuiComboFond.Items.Add($script:FondPlaceholder) | Out-Null
    $script:GuiComboFond.Items.Add("MadTrix — Matrix") | Out-Null
    $script:GuiComboFond.Items.Add("MadTrix — HUD") | Out-Null
    $script:GuiComboFond.Items.Add("MadTrix — Neon") | Out-Null
    $script:GuiComboFond.Items.Add($script:FondPrecedent) | Out-Null
    $script:GuiComboFond.SelectedIndex = 0
    $script:GuiComboFond.Add_SelectionChanged({
        $sel = $script:GuiComboFond.SelectedItem
        if (-not $sel -or $sel -eq $script:FondPlaceholder) { return }
        if ($script:GuiOccupe) {
            $script:JournalGui.AppendText("Attends la fin de l'application en cours avant de changer le fond d'écran.`r`n")
            $script:JournalGui.ScrollToEnd()
            return
        }
        try {
            if ($sel -eq $script:FondPrecedent) {
                Restore-FondPrecedent
            }
            else {
                # "MadTrix — Matrix" -> "matrix"
                $style = ($sel -split '—')[-1].Trim().ToLower()
                # Le fond prend la COULEUR DU THÈME sélectionné : chaque thème a donc
                # sa propre image assortie. On lit l'accent du thème courant.
                $themeActuel = $script:GuiFenetre.FindName("ComboTheme").SelectedItem
                $couleurFond = "#E01008"
                if ($themeActuel -and $script:Themes.Contains($themeActuel)) {
                    $couleurFond = $script:Themes[$themeActuel].Accent
                }
                $res = Get-ResolutionPhysique
                $script:JournalGui.AppendText("`r`nGénération du fond « $style » assorti au thème « $themeActuel » en $($res.L)x$($res.H) (quelques secondes)...`r`n")
                $script:JournalGui.ScrollToEnd()
                Update-InterfaceGui
                $chemin = Join-Path $script:DossierDonnees "fond-madtrix-$style.png"
                New-FondSignature -Style $style -Largeur $res.L -Hauteur $res.H -Chemin $chemin -Couleur $couleurFond | Out-Null
                Set-FondEcran -Chemin $chemin
                $script:JournalGui.AppendText("Fond « $style » ($couleurFond) appliqué.`r`n")
                $script:JournalGui.ScrollToEnd()
            }
        }
        catch {
            $script:JournalGui.AppendText("Échec du fond d'écran : $($_.Exception.Message)`r`n")
            $script:JournalGui.ScrollToEnd()
        }
    }) | Out-Null

    # TOUT ce que touchent les gestionnaires d'événements vit en $script:. C'est
    # VITAL et pas cosmétique : un gestionnaire créé avec .GetNewClosure() est lié à
    # un module dynamique où $script: pointe dans le vide -> $script:Profils y est
    # NULL, d'où le « Indexation impossible dans un tableau Null » qui figeait la
    # fenêtre. La règle est donc : état partagé en $script:, et AUCUN GetNewClosure
    # sur les blocs qui lisent du $script: (ils sont alors liés au vrai scope).
    $script:GuiFenetre = $fenetre
    $script:GuiTabs = $fenetre.FindName("TabsCategories")
    $panelProfils = $fenetre.FindName("PanelProfils")
    $script:JournalGui = $fenetre.FindName("TxtJournal")
    $script:GuiTxtEtat = $fenetre.FindName("TxtEtat")
    $script:GuiTxtSelection = $fenetre.FindName("TxtSelection")
    $script:GuiProgress = $fenetre.FindName("BarreProgression")
    $script:GuiCases = @{}

    $fenetre.FindName("TxtSysteme").Text =
        "$($script:InfosOS.DisplayVersion) — build $($script:BuildOS).$($script:InfosOS.UBR) — $($script:InfosOS.EditionID)" +
        $(if ($script:EstFamille) { "  (Famille : plusieurs stratégies HKLM y sont ignorées par Windows)" } else { "" })

    # Vrai pendant une application/simulation : empêche un re-clic et coupe les
    # boutons. État par-application, lu par le bilan de fin.
    $script:GuiOccupe = $false
    $script:GuiEnSim = $false
    $script:GuiClesAppliquees = @()

    # --- Journal : c'est ici que toute la sortie du script atterrit ---
    $script:SortieGui = {
        param($Message, $Niveau)
        $prefixe = switch ($Niveau) {
            "OK" { "  [OK]    " } "Echec" { "  [ÉCHEC] " } "Avert" { "  [!]     " }
            "Simu" { "  [SIMU]  " } "Titre" { "" } default { "  [..]    " }
        }
        $script:JournalGui.AppendText("$prefixe$Message`r`n")
        $script:JournalGui.ScrollToEnd()
        # LA correction du « ça tourne dans le vide » : chaque tweak qui écrit une
        # ligne rend la main à l'affichage. Sans ce pompage, toute l'application se
        # déroulait fenêtre gelée, et le journal n'apparaissait qu'à la toute fin.
        # Un tweak lent isolé (énumération des bloatwares, point de restauration)
        # fige encore le temps de SON exécution -- inévitable sans thread séparé --
        # mais on n'a plus une seule longue congélation opaque.
        Update-InterfaceGui
    }

    # --- Luminosité de l'écran (barre d'en-tête) : native (WMI), donc universelle,
    # contrairement au clavier. Masquée si l'écran n'est pas pilotable (poste fixe).
    $script:GuiSliderEcran = $fenetre.FindName("SliderEcran")
    $script:GuiTxtEcran = $fenetre.FindName("TxtEcran")
    $panelEcran = $fenetre.FindName("PanelEcran")
    if (Test-EcranReglable) {
        $curEcran = Get-LuminositeEcran
        if ($curEcran -lt 10) { $curEcran = 75 }
        $script:GuiSliderEcran.Value = $curEcran
        $script:GuiTxtEcran.Text = "$curEcran %"
        # Attaché APRÈS la valeur initiale : la mise en place ne déclenche pas de réglage.
        $script:GuiSliderEcran.Add_ValueChanged({
            $v = [int]$this.Value
            $script:GuiTxtEcran.Text = "$v %"
            Set-LuminositeEcran -Niveau $v | Out-Null
        }) | Out-Null
    }
    elseif ($panelEcran) { $panelEcran.Visibility = 'Collapsed' }

    # --- Cases à cocher, construites depuis l'inventaire (donc depuis le code) ---
    $inventaire = Get-Inventaire
    $script:GuiCases = @{}
    $script:GuiExplications = @{}   # cle -> TextBlock d'explication, pour que la recherche masque les deux

    # Le style de case (avec le template qui remplace la case BLANCHE système) est
    # assigné EXPLICITEMENT à chaque case. Le style implicite (TargetType) devrait
    # suffire, mais l'assignation directe ne laisse AUCUN doute : c'est ce qui tue
    # définitivement les « carrés blancs ».
    $styleCase = $null
    try { $styleCase = $fenetre.FindResource([System.Windows.Controls.CheckBox]) } catch { }

    foreach ($groupe in ($inventaire | Group-Object Categorie)) {
        $pile = New-Object System.Windows.Controls.StackPanel
        $pile.Margin = "10"
        foreach ($t in $groupe.Group) {
            $cb = New-Object System.Windows.Controls.CheckBox
            if ($styleCase) { $cb.Style = $styleCase }
            # Les titres sont des QUESTIONS (« Désactiver X ? ») : le point
            # d'interrogation n'a plus de sens à côté d'une case à cocher.
            $cb.Content = ($t.Titre -replace '\s*\?\s*$', '')
            $cb.Tag = $t.Cle
            $cb.FontWeight = 'SemiBold'
            if ($t.Redemarrage) {
                $cb.ToolTip = "Ce réglage ne prendra effet qu'après un redémarrage."
                $cb.Content = "$($cb.Content)   ⟳"
            }
            $pile.Children.Add($cb) | Out-Null

            # L'explication est affichée EN PERMANENCE sous la case, pas rangée dans
            # une infobulle : une infobulle ne se découvre qu'en survolant, donc
            # personne ne la lit -- surtout pas celui qui coche vite. Un réglage
            # qu'on ne comprend pas est un réglage qu'on applique mal.
            if ($t.Explication) {
                $texte = New-Object System.Windows.Controls.TextBlock
                $texte.Text = $t.Explication
                $texte.TextWrapping = 'Wrap'
                $texte.FontSize = 11
                $texte.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextMutedBrush")
                $texte.Margin = '26,0,10,10'
                $pile.Children.Add($texte) | Out-Null
                $script:GuiExplications[$t.Cle] = $texte
            }
            $script:GuiCases[$t.Cle] = $cb
        }
        $defilement = New-Object System.Windows.Controls.ScrollViewer
        $defilement.VerticalScrollBarVisibility = 'Auto'
        $defilement.Content = $pile
        $onglet = New-Object System.Windows.Controls.TabItem
        $onglet.Header = "$(Get-NomOnglet $groupe.Name)  ($($groupe.Count))"
        $onglet.Content = $defilement
        $script:GuiTabs.Items.Add($onglet) | Out-Null
    }

    # Page MATÉRIEL : mode d'alimentation Windows (toujours) + réglages du clavier RGB
    # si le matériel répond. Comme le sous-titre OS, l'interface s'adapte au matériel.
    Add-PageMateriel $fenetre

    # Page CLÉ D'INSTALLATION : génère le fichier de réponses d'une installation
    # automatisée. Rien à cocher parmi les tweaks ici, uniquement de la saisie.
    Add-PageInstallation $fenetre

    $majSelection = {
        $n = @($script:GuiCases.Values | Where-Object { $_.IsChecked }).Count
        $script:GuiTxtSelection.Text = "$n tweak(s) sélectionné(s) sur $($script:GuiCases.Count)"
    }
    foreach ($cb in $script:GuiCases.Values) {
        $cb.Add_Checked($majSelection) | Out-Null
        $cb.Add_Unchecked($majSelection) | Out-Null
    }

    # --- Profils : ils ne font que cocher. Rien n'est appliqué avant « Appliquer ». ---
    # Chaque profil est une LIGNE : bouton à gauche, description toujours visible à
    # droite. La description vivait dans une infobulle, donc elle ne se lisait qu'au
    # survol -- exactement le défaut qu'on reproche aux infobulles pour les tweaks.
    # Un profil applique un gros lot d'un coup : c'est le pire endroit pour cacher
    # ce qu'il fait derrière un survol.
    foreach ($nomProfil in $script:Profils.Keys) {
        $profil = $script:Profils[$nomProfil]

        $ligne = New-Object System.Windows.Controls.DockPanel
        $ligne.Margin = "0,0,0,6"
        $ligne.LastChildFill = $true

        $bouton = New-Object System.Windows.Controls.Button
        $bouton.Content = "$(Get-NomProfil $nomProfil)  ($($profil.Cles.Count))"
        $bouton.Width = 180
        $bouton.VerticalAlignment = 'Top'
        $bouton.Margin = "0,0,10,0"
        $bouton.Tag = $nomProfil
        $bouton.Add_Click({
            param($emetteur, $evt)
            if ($script:GuiOccupe) { return }   # une application est en cours
            $p = $script:Profils[$emetteur.Tag]
            foreach ($c in $script:GuiCases.Values) { $c.IsChecked = $false }
            foreach ($cle in $p.Cles) { if ($script:GuiCases.ContainsKey($cle)) { $script:GuiCases[$cle].IsChecked = $true } }
            $script:JournalGui.AppendText("`r`n=== Profil « $($emetteur.Tag) » : $($p.Cles.Count) tweaks cochés ===`r`n")
            $script:JournalGui.AppendText("$($p.Description)`r`n")
            $script:JournalGui.AppendText("Rien n'est encore appliqué : ajuste les cases, puis Simuler ou Appliquer.`r`n")
            $script:JournalGui.ScrollToEnd()
        }) | Out-Null
        [System.Windows.Controls.DockPanel]::SetDock($bouton, 'Left')
        $ligne.Children.Add($bouton) | Out-Null

        $desc = New-Object System.Windows.Controls.TextBlock
        $desc.Text = Get-DescriptionProfil $nomProfil
        $desc.TextWrapping = 'Wrap'
        $desc.FontSize = 11
        $desc.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextMutedBrush")
        $desc.VerticalAlignment = 'Center'
        $ligne.Children.Add($desc) | Out-Null

        $panelProfils.Children.Add($ligne) | Out-Null
    }

    # --- Profils PERSONNALISÉS (enregistrés par l'utilisateur), sous les intégrés ---
    $script:PanelProfilsRef = $panelProfils
    $script:ProfilsPersoCache = Get-ProfilsPerso
    $script:ProfilsPersoAffiches = New-Object System.Collections.Generic.HashSet[string]
    foreach ($nomPP in @($script:ProfilsPersoCache.Keys)) {
        Add-BoutonProfilPerso $nomPP
        [void]$script:ProfilsPersoAffiches.Add($nomPP)
    }

    # --- Tout cocher / décocher ---
    $script:GuiFenetre.FindName("BtnToutCocher").Add_Click({
        if ($script:GuiOccupe) { return }
        if ($script:GuiTabs.SelectedItem) {
            # Le panneau contient aussi les TextBlock d'explication : sans ce filtre,
            # on tenterait de cocher un bloc de texte.
            foreach ($c in $script:GuiTabs.SelectedItem.Content.Content.Children) {
                if ($c -is [System.Windows.Controls.CheckBox]) { $c.IsChecked = $true }
            }
        }
    }) | Out-Null
    $script:GuiFenetre.FindName("BtnToutDecocher").Add_Click({
        if ($script:GuiOccupe) { return }
        foreach ($c in $script:GuiCases.Values) { $c.IsChecked = $false }
    }) | Out-Null

    $script:GuiFenetre.FindName("BtnSimuler").Add_Click({ Invoke-LancerGui $true }) | Out-Null
    $script:GuiFenetre.FindName("BtnAppliquer").Add_Click({ Invoke-LancerGui $false }) | Out-Null
    $script:GuiFenetre.FindName("BtnRedemarrer").Add_Click({
        if ($script:GuiOccupe) { return }
        $result = [System.Windows.MessageBox]::Show(
            "Es-tu sûr de vouloir redémarrer le PC maintenant pour appliquer tous les tweaks ?",
            "Confirmation de redémarrage",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )
        if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
            $script:GuiFenetre.Close()
            Restart-Computer -Force
        }
    }) | Out-Null

    # --- Recherche / filtre des tweaks : masque cases + explications qui ne correspondent pas ---
    $script:GuiRecherche = $fenetre.FindName("TxtRecherche")
    $script:GuiRecherche.Add_TextChanged({
        $q = $script:GuiRecherche.Text.Trim().ToLower()
        foreach ($cle in $script:GuiCases.Keys) {
            $cb = $script:GuiCases[$cle]
            $texte = "$($cb.Content) $cle"
            if ($script:GuiExplications.ContainsKey($cle)) { $texte += " " + $script:GuiExplications[$cle].Text }
            $vis = if (-not $q -or $texte.ToLower().Contains($q)) { 'Visible' } else { 'Collapsed' }
            $cb.Visibility = $vis
            if ($script:GuiExplications.ContainsKey($cle)) { $script:GuiExplications[$cle].Visibility = $vis }
        }
    }) | Out-Null

    # --- État actuel : lit l'audit et COLORE en vert les cases déjà appliquées ---
    $fenetre.FindName("BtnEtatActuel").Add_Click({
        if ($script:GuiOccupe) { return }
        $script:GuiTxtEtat.Text = "Analyse de l'état réel de la machine (quelques secondes)..."
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        Update-InterfaceGui
        try {
            # Un seul passage sur le catalogue : il alimente à la fois la coloration
            # des cases et le score (les calculer à part doublait le temps d'attente).
            $audit = Get-AuditComplet
            $etat = $audit.Etat
            $vert = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0x5C, 0xC8, 0x6E)); $vert.Freeze()
            $oui = 0; $non = 0
            foreach ($cle in $script:GuiCases.Keys) {
                $cb = $script:GuiCases[$cle]
                switch ($etat[$cle]) {
                    'OUI' { $cb.Foreground = $vert; $oui++ }
                    'NON' { $cb.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "TextPrimaryBrush"); $non++ }
                    '?' { $cb.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "TextMutedBrush") }
                    default { $cb.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "TextPrimaryBrush") }
                }
            }
            $script:JournalGui.AppendText("`r`n=== État actuel : $oui réglage(s) déjà actif(s), $non au défaut (sur les tweaks audités) ===`r`n")
            $script:JournalGui.AppendText("En vert = déjà appliqué sur cette machine. Coche ce qui manque, puis « Appliquer ».`r`n")
            # Score de santé : déjà calculé par le même passage, rien à relancer.
            $sc = $audit.Score
            Update-ScoreGui $sc
            $script:JournalGui.AppendText("`r`nSCORE DE SANTÉ : $($sc.Note)/100 ($($sc.Mention)) — $($sc.Appliques) réglages en place sur $($sc.Total) applicables ici.`r`n")
            foreach ($c in $sc.Detail.Keys) { $script:JournalGui.AppendText(("   {0,-22} {1,3}/100`r`n" -f $c, $sc.Detail[$c])) }
            $script:JournalGui.ScrollToEnd()
            $script:GuiTxtEtat.Text = "Audit terminé : score $($sc.Note)/100 — $oui actif(s), $non au défaut."
        }
        catch { $script:GuiTxtEtat.Text = "Audit impossible : $($_.Exception.Message)" }
        finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
    }) | Out-Null

    # --- Restauration exacte (Annuler dans la GUI) : remet l'état d'avant depuis la sauvegarde ---
    $fenetre.FindName("BtnRestaurer").Add_Click({
        if ($script:GuiOccupe) { return }
        $n = $script:Sauvegarde.Count
        if ($n -eq 0) {
            $script:JournalGui.AppendText("`r`nRestauration exacte : rien à remettre (ce script n'a modifié aucune valeur ici).`r`n")
            $script:JournalGui.ScrollToEnd(); return
        }
        $rep = [System.Windows.MessageBox]::Show(
            "Remettre les $n valeur(s) modifiées par ce script telles qu'elles étaient avant ?",
            "Restauration exacte", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($rep -ne [System.Windows.MessageBoxResult]::Yes) { return }
        try {
            Restore-Sauvegarde
            $script:JournalGui.AppendText("`r`n=== Restauration exacte : $n valeur(s) remises comme avant. ===`r`n")
        }
        catch { $script:JournalGui.AppendText("Restauration : échec — $($_.Exception.Message)`r`n") }
        $script:JournalGui.ScrollToEnd()
    }) | Out-Null

    # --- Combo « Gamer ROG » : alimentation Performances + clavier rouge + coche le profil Gamer ---
    $fenetre.FindName("BtnGamerRog").Add_Click({
        if ($script:GuiOccupe) { return }
        Set-ModeAlimentation -Mode "Performances" | Out-Null
        try { Set-ClavierAura -R 226 -G 0 -B 24 -Mode "Statique" | Out-Null } catch { }
        $n = 0
        $profil = $script:Profils["Gamer"]
        if ($profil) {
            foreach ($c in $script:GuiCases.Values) { $c.IsChecked = $false }
            foreach ($cle in $profil.Cles) { if ($script:GuiCases.ContainsKey($cle)) { $script:GuiCases[$cle].IsChecked = $true; $n++ } }
        }
        $script:JournalGui.AppendText("`r`n=== Gamer ROG : alimentation « Performances », clavier rouge, $n tweak(s) Gamer cochés. ===`r`n")
        $script:JournalGui.AppendText("Rien d'appliqué côté tweaks pour l'instant : vérifie la sélection, puis « Appliquer ».`r`n")
        $script:JournalGui.ScrollToEnd()
    }) | Out-Null

    # --- Replier les zones haut (profils) et bas (journal) pour agrandir la liste ---
    # La rangée profils est en Auto : masquer son cadre suffit à la réduire à 0. La
    # rangée journal est en hauteur fixe (190) : on remet aussi sa hauteur à 0 pour
    # que les onglets (rangée *) récupèrent la place.
    $script:GuiGrid = $fenetre.FindName("GridPrincipal")
    $script:GuiBorderProfils = $fenetre.FindName("BorderProfils")
    $script:GuiBorderJournal = $fenetre.FindName("BorderJournal")
    $script:GuiBtnToggleProfils = $fenetre.FindName("BtnToggleProfils")
    $script:GuiBtnToggleJournal = $fenetre.FindName("BtnToggleJournal")
    # Ce sont désormais des MenuItem : leur libellé est .Header (un MenuItem n'a pas
    # de propriété .Content -- y écrire lèverait).
    $script:GuiBtnToggleProfils.Add_Click({
        if ($script:GuiBorderProfils.Visibility -eq 'Visible') {
            $script:GuiBorderProfils.Visibility = 'Collapsed'
            $script:GuiBtnToggleProfils.Header = 'Afficher les profils'
        }
        else {
            $script:GuiBorderProfils.Visibility = 'Visible'
            $script:GuiBtnToggleProfils.Header = 'Cacher les profils'
        }
    }) | Out-Null
    $script:GuiBtnToggleJournal.Add_Click({
        if ($script:GuiBorderJournal.Visibility -eq 'Visible') {
            $script:GuiBorderJournal.Visibility = 'Collapsed'
            $script:GuiGrid.RowDefinitions[4].Height = [System.Windows.GridLength]::new(0)
            $script:GuiBtnToggleJournal.Header = 'Afficher le journal'
        }
        else {
            $script:GuiBorderJournal.Visibility = 'Visible'
            $script:GuiGrid.RowDefinitions[4].Height = [System.Windows.GridLength]::new(190)
            $script:GuiBtnToggleJournal.Header = 'Cacher le journal'
        }
    }) | Out-Null

    # --- Vérifier la dérive : réglages appliqués mais revenus au défaut (post-MAJ) ---
    $fenetre.FindName("BtnDerive").Add_Click({
        if ($script:GuiOccupe) { return }
        $script:GuiTxtEtat.Text = "Recherche des réglages revenus en arrière..."
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        Update-InterfaceGui
        try {
            $drift = @(Get-DeriveTweaks)
            if ($drift.Count -eq 0) {
                $script:JournalGui.AppendText("`r`n=== Dérive : aucun réglage déjà appliqué n'est revenu en arrière. ===`r`n")
                $script:JournalGui.AppendText("(La dérive se compare à ce que tu as appliqué via cet outil ; applique au moins une fois pour l'alimenter.)`r`n")
            }
            else {
                foreach ($x in $script:GuiCases.Values) { $x.IsChecked = $false }
                $n = 0
                foreach ($cle in $drift) { if ($script:GuiCases.ContainsKey($cle)) { $script:GuiCases[$cle].IsChecked = $true; $n++ } }
                $script:JournalGui.AppendText("`r`n=== Dérive : $n réglage(s) que tu avais appliqués sont revenus au défaut (souvent après une MAJ Windows). Cochés — clique « Appliquer » pour les remettre. ===`r`n")
            }
            $script:JournalGui.ScrollToEnd()
            $script:GuiTxtEtat.Text = "Dérive : $($drift.Count) réglage(s) à réappliquer."
        }
        catch { $script:GuiTxtEtat.Text = "Dérive : $($_.Exception.Message)" }
        finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
    }) | Out-Null

    # --- Rapport HTML : état actuel, fichier autonome ouvert dans le navigateur ---
    $fenetre.FindName("BtnRapport").Add_Click({
        if ($script:GuiOccupe) { return }
        $script:GuiTxtEtat.Text = "Génération du rapport HTML..."
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        Update-InterfaceGui
        try {
            $chemin = New-RapportHTML
            $script:JournalGui.AppendText("`r`n=== Rapport HTML généré : $chemin ===`r`n")
            $script:JournalGui.ScrollToEnd()
            Start-Process $chemin
            $script:GuiTxtEtat.Text = "Rapport ouvert dans le navigateur."
        }
        catch { $script:GuiTxtEtat.Text = "Rapport : $($_.Exception.Message)" }
        finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
    }) | Out-Null

    # --- Enregistrer la sélection comme profil personnalisé ---
    $fenetre.FindName("BtnEnregistrerProfil").Add_Click({
        if ($script:GuiOccupe) { return }
        $cles = @($script:GuiCases.GetEnumerator() | Where-Object { $_.Value.IsChecked } | ForEach-Object { $_.Key })
        if ($cles.Count -eq 0) {
            $script:JournalGui.AppendText("`r`nEnregistrer : coche d'abord des tweaks, puis réessaie.`r`n"); $script:JournalGui.ScrollToEnd(); return
        }
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
        $nom = [Microsoft.VisualBasic.Interaction]::InputBox("Nom du profil personnalisé ($($cles.Count) tweak(s) cochés) :", "Enregistrer la sélection", "Mon profil")
        if (-not $nom -or -not $nom.Trim()) { return }
        $nom = $nom.Trim()
        try {
            Save-ProfilPerso -Nom $nom -Cles $cles
            $script:ProfilsPersoCache = Get-ProfilsPerso
            if (-not $script:ProfilsPersoAffiches.Contains($nom)) {
                Add-BoutonProfilPerso $nom
                [void]$script:ProfilsPersoAffiches.Add($nom)
            }
            $script:JournalGui.AppendText("`r`n=== Profil « $nom » enregistré ($($cles.Count) tweaks). Il apparaît dans la zone Profils, rechargeable en un clic. ===`r`n")
            $script:JournalGui.ScrollToEnd()
        }
        catch {
            $script:JournalGui.AppendText("Enregistrement impossible : $($_.Exception.Message)`r`n"); $script:JournalGui.ScrollToEnd()
        }
    }) | Out-Null

    # --- Analyse du démarrage : durée réelle + coût de chaque programme ---
    $fenetre.FindName("BtnDemarrage").Add_Click({
        if ($script:GuiOccupe) { return }
        $script:GuiTxtEtat.Text = "Analyse du démarrage..."
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        Update-InterfaceGui
        try {
            $a = Get-AnalyseDemarrage
            $L = @()
            if ($a.BootMs -gt 0) { $L += "Dernier démarrage mesuré par Windows : $([math]::Round($a.BootMs / 1000, 1)) secondes." }
            else { $L += "Durée de démarrage non mesurée par Windows (journal Diagnostics-Performance vide)." }
            $L += ""
            if ($a.Programmes.Count -eq 0) { $L += "Aucun programme de démarrage dans les clés Run." }
            else {
                $L += ("{0,-38} {1,-12} {2}" -f "PROGRAMME", "ZONE", "COÛT")
                $L += ("-" * 70)
                foreach ($p in $a.Programmes) {
                    $c = if ($p.CoutMs -gt 0) { "$([math]::Round($p.CoutMs / 1000, 1)) s" } else { "non mesuré" }
                    $L += ("{0,-38} {1,-12} {2}" -f $p.Nom, $p.Zone, $c)
                }
                $L += ""
                $L += "Pour retirer un programme du démarrage : onglet « Démarrage & services »,"
                $L += "ou Gestionnaire des tâches > Applications de démarrage."
            }
            Show-ListeModaleGui "Analyse du démarrage" $L
            $script:GuiTxtEtat.Text = "Démarrage : $($a.Programmes.Count) programme(s) au lancement."
        }
        catch { $script:GuiTxtEtat.Text = "Analyse démarrage : $($_.Exception.Message)" }
        finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
    }) | Out-Null

    # --- Analyse disque : on PÈSE avant de proposer de nettoyer ---
    $fenetre.FindName("BtnDisque").Add_Click({
        if ($script:GuiOccupe) { return }
        $script:GuiTxtEtat.Text = "Mesure de l'espace disque (quelques secondes)..."
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        Update-InterfaceGui
        try {
            $d = Get-AnalyseDisque
            $L = @("Disque système : $($d.LibreGo) Go libres sur $($d.TotalGo) Go", "")
            $L += ("{0,-36} {1,12}" -f "POSTE", "TAILLE")
            $L += ("-" * 50)
            $tot = 0
            foreach ($p in $d.Postes) {
                $tot += $p.Mo
                $taille = if ($p.Mo -ge 1024) { "$([math]::Round($p.Mo / 1024, 2)) Go" } else { "$($p.Mo) Mo" }
                $L += ("{0,-36} {1,12}" -f $p.Nom, $taille)
            }
            $L += ("-" * 50)
            $L += ("{0,-36} {1,12}" -f "TOTAL mesuré", "$([math]::Round($tot / 1024, 2)) Go")
            $L += ""
            $L += "Note : « Téléchargements » et « Windows.old » ne sont PAS touchés par le"
            $L += "nettoyage automatique -- ce sont tes fichiers. Le fichier d'hibernation"
            $L += "n'est libérable qu'en désactivant l'hibernation (déconseillé sur portable)."
            $L += "Pour nettoyer le reste : onglet « Nettoyage »."
            Show-ListeModaleGui "Analyse du disque" $L
            $script:GuiTxtEtat.Text = "Disque : $([math]::Round($tot / 1024, 2)) Go mesurés, $($d.LibreGo) Go libres."
        }
        catch { $script:GuiTxtEtat.Text = "Analyse disque : $($_.Exception.Message)" }
        finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
    }) | Out-Null

    # --- Logiciels indésirables : on SIGNALE, on ne désinstalle rien dans le dos ---
    $fenetre.FindName("BtnIndesirables").Add_Click({
        if ($script:GuiOccupe) { return }
        $script:GuiTxtEtat.Text = "Recherche de logiciels indésirables..."
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        Update-InterfaceGui
        try {
            $pups = @(Get-LogicielsIndesirables)
            if ($pups.Count -eq 0) {
                $L = @("Aucun logiciel indésirable connu détecté.", "",
                    "Sont recherchés : antivirus d'essai préinstallés (McAfee, Norton, Avast...),",
                    "faux optimiseurs (Driver Booster, Advanced SystemCare...), barres d'outils",
                    "et détourneurs de recherche, logiciels OEM superflus.")
            }
            else {
                $L = @("$($pups.Count) logiciel(s) à examiner. RIEN n'a été désinstallé :", "")
                foreach ($p in $pups) {
                    $L += "  $($p.Nom)"
                    $L += "     Éditeur   : $($p.Editeur)"
                    $L += "     Catégorie : $($p.Categorie)"
                    $L += "     Pourquoi  : $($p.Pourquoi)"
                    $L += ""
                }
                $L += "Pour les retirer : Paramètres > Applications > Applications installées."
                $L += "Un antivirus se désinstalle avec SON propre outil de suppression (éditeur)."
            }
            Show-ListeModaleGui "Logiciels indésirables" $L
            $script:GuiTxtEtat.Text = "Indésirables : $($pups.Count) détecté(s)."
        }
        catch { $script:GuiTxtEtat.Text = "Recherche indésirables : $($_.Exception.Message)" }
        finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
    }) | Out-Null

    # --- Points de restauration Windows : lister, et éventuellement y revenir ---
    $fenetre.FindName("BtnPointsResto").Add_Click({
        if ($script:GuiOccupe) { return }
        $script:GuiTxtEtat.Text = "Lecture des points de restauration..."
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        Update-InterfaceGui
        $pts = @()
        try { $pts = @(Get-PointsRestauration) } catch { }
        [System.Windows.Input.Mouse]::OverrideCursor = $null
        if ($pts.Count -eq 0) {
            $script:JournalGui.AppendText("`r`nAucun point de restauration : la protection système est peut-être désactivée. Coche « Point de restauration avant d'appliquer » pour en créer un.`r`n")
            $script:JournalGui.ScrollToEnd()
            $script:GuiTxtEtat.Text = "Aucun point de restauration trouvé."
            return
        }
        $script:JournalGui.AppendText("`r`n=== $($pts.Count) point(s) de restauration ===`r`n")
        foreach ($p in $pts) {
            $d = if ($p.Date) { $p.Date.ToString('dd/MM/yyyy HH:mm') } else { "date inconnue" }
            $script:JournalGui.AppendText(("   #{0}  {1}  {2}  [{3}]`r`n" -f $p.Numero, $d, $p.Description, $p.Type))
        }
        $script:JournalGui.ScrollToEnd()
        $recent = $pts[0]
        $dr = if ($recent.Date) { $recent.Date.ToString('dd/MM/yyyy HH:mm') } else { "date inconnue" }
        $rep = [System.Windows.MessageBox]::Show(
            "Restaurer le système au point le plus récent ?`n`n   #$($recent.Numero) — $dr`n   $($recent.Description)`n`nWindows REDÉMARRERA la machine pour l'appliquer. Enregistre ton travail avant de confirmer.`n`n(La liste complète est dans le journal.)",
            "Points de restauration", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($rep -eq [System.Windows.MessageBoxResult]::Yes) {
            try {
                Restore-PointRestauration -Numero $recent.Numero | Out-Null
                $script:JournalGui.AppendText("Restauration lancée : la machine va redémarrer.`r`n")
            }
            catch { $script:JournalGui.AppendText("Restauration refusée : $($_.Exception.Message)`r`n") }
            $script:JournalGui.ScrollToEnd()
        }
        $script:GuiTxtEtat.Text = "$($pts.Count) point(s) de restauration listé(s) dans le journal."
    }) | Out-Null

    # --- Diagnostic plantages : crashes récents + tweaks suspects, corrige le pire ---
    $fenetre.FindName("BtnDiagnostic").Add_Click({
        if ($script:GuiOccupe) { return }
        $script:GuiTxtEtat.Text = "Analyse des plantages récents..."
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        Update-InterfaceGui
        try {
            $d = Get-DiagnosticPlantages
            $script:JournalGui.AppendText("`r`n=== DIAGNOSTIC PLANTAGES ===`r`n")
            if ($d.Crashes.Count -eq 0) {
                $script:JournalGui.AppendText("Aucun arrêt inattendu / écran bleu dans les 21 derniers jours.`r`n")
            }
            else {
                $script:JournalGui.AppendText("$($d.Crashes.Count) plantage(s) récent(s) :`r`n")
                foreach ($c in $d.Crashes) { $script:JournalGui.AppendText("   - $($c.TimeCreated) (Event $($c.Id))`r`n") }
            }
            if ($d.Suspects.Count -eq 0) {
                $script:JournalGui.AppendText("Aucun tweak suspect actif.`r`n")
            }
            else {
                foreach ($s in $d.Suspects) {
                    $script:JournalGui.AppendText("   [$($s.Gravite)] $($s.Nom)`r`n         -> $($s.Conseil)`r`n")
                    if ($s.Cle -eq 'modern-standby') {
                        try {
                            Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "PlatformAoAcOverride" -Force -ErrorAction Stop
                            $script:JournalGui.AppendText("         >> CORRIGÉ : veille moderne S0 restaurée. REDÉMARRE pour finaliser.`r`n")
                        }
                        catch { $script:JournalGui.AppendText("         >> Correction auto impossible : $($_.Exception.Message)`r`n") }
                    }
                }
            }
            $script:JournalGui.ScrollToEnd()
            $script:GuiTxtEtat.Text = "Diagnostic : $($d.Crashes.Count) plantage(s), $($d.Suspects.Count) suspect(s)."
        }
        catch { $script:GuiTxtEtat.Text = "Diagnostic : $($_.Exception.Message)" }
        finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
    }) | Out-Null

    # --- Restauration sélective : fenêtre modale, une case par valeur modifiée ---
    $fenetre.FindName("BtnRestaurerSelectif").Add_Click({
        if ($script:GuiOccupe) { return }
        $entrees = @(Get-EntreesSauvegarde)
        if ($entrees.Count -eq 0) {
            $script:JournalGui.AppendText("`r`nRestauration sélective : aucune modification enregistrée à annuler.`r`n"); $script:JournalGui.ScrollToEnd(); return
        }
        $win = New-Object System.Windows.Window
        $win.Title = "Restauration sélective"; $win.Width = 720; $win.Height = 560
        $win.WindowStartupLocation = 'CenterOwner'; $win.Owner = $script:GuiFenetre
        $win.Resources = $script:GuiFenetre.Resources   # partage les styles => tout est thémé
        $win.Background = $script:GuiFenetre.Background
        $grille = New-Object System.Windows.Controls.Grid; $grille.Margin = "12"
        foreach ($h in 'Auto', '*', 'Auto') { $rd = New-Object System.Windows.Controls.RowDefinition; $rd.Height = $h; $grille.RowDefinitions.Add($rd) }
        $entete = New-Object System.Windows.Controls.TextBlock
        $entete.Text = "Coche les réglages à remettre à leur état d'origine ($($entrees.Count) modifiés) :"
        $entete.Margin = "0,0,0,8"; $entete.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextPrimaryBrush")
        [System.Windows.Controls.Grid]::SetRow($entete, 0); $grille.Children.Add($entete) | Out-Null
        $sv = New-Object System.Windows.Controls.ScrollViewer; $sv.VerticalScrollBarVisibility = 'Auto'
        [System.Windows.Controls.Grid]::SetRow($sv, 1)
        $pile = New-Object System.Windows.Controls.StackPanel
        $script:RestoreCases = @{}
        foreach ($en in $entrees) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = "$($en.Desc)   (avant : $($en.Avant))"
            $cb.Tag = $en.Cle; $cb.Margin = "0,3,0,3"
            $pile.Children.Add($cb) | Out-Null
            $script:RestoreCases[$en.Cle] = $cb
        }
        $sv.Content = $pile; $grille.Children.Add($sv) | Out-Null
        $barre = New-Object System.Windows.Controls.StackPanel; $barre.Orientation = 'Horizontal'; $barre.HorizontalAlignment = 'Right'; $barre.Margin = "0,10,0,0"
        [System.Windows.Controls.Grid]::SetRow($barre, 2)
        $btnOk = New-Object System.Windows.Controls.Button; $btnOk.Content = "Restaurer la sélection"; $btnOk.Margin = "0,0,8,0"
        $btnFerm = New-Object System.Windows.Controls.Button; $btnFerm.Content = "Fermer"
        $btnOk.Add_Click({
            $sel = @($script:RestoreCases.GetEnumerator() | Where-Object { $_.Value.IsChecked } | ForEach-Object { $_.Key })
            if ($sel.Count -eq 0) { return }
            $res = Restore-SauvegardePartielle -Cles $sel
            $script:JournalGui.AppendText("`r`n=== Restauration sélective : $($res.OK) valeur(s) remise(s), $($res.Echecs) échec(s). ===`r`n")
            $script:JournalGui.ScrollToEnd()
            $script:RestoreWin.Close()
        }) | Out-Null
        $btnFerm.Add_Click({ $script:RestoreWin.Close() }) | Out-Null
        $barre.Children.Add($btnOk) | Out-Null; $barre.Children.Add($btnFerm) | Out-Null
        $grille.Children.Add($barre) | Out-Null
        $win.Content = $grille
        $script:RestoreWin = $win
        $win.ShowDialog() | Out-Null
    }) | Out-Null

    # --- Exporter / importer un bundle de config ---
    $fenetre.FindName("BtnExportConfig").Add_Click({
        if ($script:GuiOccupe) { return }
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Filter = "Config MadTweak (*.json)|*.json"; $dlg.FileName = "ma-config-madtweak.json"
        if ($dlg.ShowDialog()) {
            try { $c = Export-ConfigBundle -Chemin $dlg.FileName; $script:JournalGui.AppendText("`r`n=== Config exportée : $c ===`r`n") }
            catch { $script:JournalGui.AppendText("Export : $($_.Exception.Message)`r`n") }
            $script:JournalGui.ScrollToEnd()
        }
    }) | Out-Null
    $fenetre.FindName("BtnImportConfig").Add_Click({
        if ($script:GuiOccupe) { return }
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Filter = "Config MadTweak (*.json)|*.json"
        if ($dlg.ShowDialog()) {
            try {
                $r = Import-ConfigBundle -Chemin $dlg.FileName
                $script:ProfilsPersoCache = Get-ProfilsPerso
                foreach ($nomPP in @($script:ProfilsPersoCache.Keys)) {
                    if (-not $script:ProfilsPersoAffiches.Contains($nomPP)) { Add-BoutonProfilPerso $nomPP; [void]$script:ProfilsPersoAffiches.Add($nomPP) }
                }
                foreach ($x in $script:GuiCases.Values) { $x.IsChecked = $false }
                $n = 0
                foreach ($cle in $r.Cles) { if ($script:GuiCases.ContainsKey($cle)) { $script:GuiCases[$cle].IsChecked = $true; $n++ } }
                $appsTxt = if ($r.Apps) { ", liste d'apps récupérée (menu Logiciels > importer)" } else { "" }
                $script:JournalGui.AppendText("`r`n=== Config importée : $($r.NbProfils) profil(s) perso, $n tweak(s) cochés$appsTxt. Clique « Appliquer » pour poser les tweaks. ===`r`n")
            }
            catch { $script:JournalGui.AppendText("Import : $($_.Exception.Message)`r`n") }
            $script:JournalGui.ScrollToEnd()
        }
    }) | Out-Null

    # --- Maintenance auto : bascule la tâche planifiée hebdomadaire ---
    $script:GuiBtnMaintenance = $fenetre.FindName("BtnMaintenance")
    if (Test-MaintenanceHebdo) { $script:GuiBtnMaintenance.Header = "Maintenance auto : ACTIVÉE" }
    $script:GuiBtnMaintenance.Add_Click({
        if ($script:GuiOccupe) { return }
        try {
            if (Test-MaintenanceHebdo) {
                Unregister-MaintenanceHebdo
                $script:GuiBtnMaintenance.Header = "Maintenance auto (hebdomadaire)"
                $script:JournalGui.AppendText("`r`nMaintenance hebdomadaire désactivée.`r`n")
            }
            else {
                Register-MaintenanceHebdo
                $script:GuiBtnMaintenance.Header = "Maintenance auto : ACTIVÉE"
                $script:JournalGui.AppendText("`r`nMaintenance planifiée (dimanche midi) : nettoyage léger des fichiers temporaires, en silence.`r`n")
            }
            $script:JournalGui.ScrollToEnd()
        }
        catch { $script:JournalGui.AppendText("Maintenance : $($_.Exception.Message)`r`n"); $script:JournalGui.ScrollToEnd() }
    }) | Out-Null

    & $majSelection
    $script:JournalGui.AppendText("Interface prête. $($script:GuiCases.Count) tweaks pilotables, $($script:Profils.Count) profils.`r`n")
    $script:JournalGui.AppendText("Tous les tweaks (y compris Edge, OneDrive, Windows Update, VBS, DISM/SFC, logiciels et nettoyage) sont désormais disponibles directement via cette interface.`r`n`r`n")
    $script:JournalGui.AppendText("Conseil : commence par « Simuler ». Rien ne sera écrit, et tu verras`r`n")
    $script:JournalGui.AppendText("exactement quelle valeur changerait, et en quoi.`r`n")
    $script:GuiTxtEtat.Text = "Prêt. Données de session : $script:DossierDonnees"

    # Minimisation de la console pendant que l'IHM est affichée
    $hwnd = [IntPtr]::Zero
    try {
        if (-not ([System.Management.Automation.PSTypeName]"Win32.NativeMethods").Type) {
            $sig = @'
            [DllImport("user32.dll")]
            public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
            [DllImport("kernel32.dll")]
            public static extern IntPtr GetConsoleWindow();
'@
            Add-Type -MemberDefinition $sig -Name NativeMethods -Namespace Win32 -ErrorAction SilentlyContinue | Out-Null
        }
        $hwnd = [Win32.NativeMethods]::GetConsoleWindow()
        if ($hwnd -ne [IntPtr]::Zero) {
            [Win32.NativeMethods]::ShowWindow($hwnd, 2) | Out-Null # 2 = SW_SHOWMINIMIZED
        }
    } catch {}

    $fenetre.ShowDialog() | Out-Null

    # Restauration de la console après fermeture de l'IHM
    try {
        if ($hwnd -ne [IntPtr]::Zero) {
            [Win32.NativeMethods]::ShowWindow($hwnd, 9) | Out-Null # 9 = SW_RESTORE
        }
    } catch {}

    # La console reprend la main une fois la fenêtre fermée.
    $script:SortieGui = $null
}
