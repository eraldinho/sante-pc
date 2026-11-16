# Santé PC

Lecture seule de l'état d'un PC Windows. La passe rapide et la passe complète constatent des traces déjà enregistrées par le système. L'outil ne répare rien et ne teste pas le matériel sous charge.

Version figée : `1.0.0`.

URL canonique, après création du tag `v1.0.0` :

`https://raw.githubusercontent.com/eraldinho/sante-pc/v1.0.0/sante.ps1`

Le fichier exécuté est `sante.ps1`. `sante.ps1.sha256` contient l'empreinte SHA-256 de ses octets, BOM compris, sous la forme `<HASH>  sante.ps1`. `tests/` et `tools/` ne sont pas chargés par le script.

## Lancement

La commande supportée télécharge les octets, les compare à l'empreinte publiée, puis exécute. Une empreinte différente interrompt avant toute exécution.

```powershell
$u = 'https://raw.githubusercontent.com/eraldinho/sante-pc/v1.0.0/sante.ps1'
$bytes = (New-Object Net.WebClient).DownloadData($u)
$attendu = ((New-Object Net.WebClient).DownloadString("$u.sha256")).Trim().Split()[0]
$obtenu = (Get-FileHash -InputStream ([IO.MemoryStream]::new($bytes)) -Algorithm SHA256).Hash
if ($obtenu -ne $attendu) { throw "Empreinte inattendue" }
iex ([Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF))
```

Cette commande lance la passe rapide dans la session courante.

Pour la passe complète, définir la variable avant le téléchargement :

```powershell
$env:SANTE_PASSE = 'Complete'
```

Sur une copie locale déjà présente : `powershell -File .\sante.ps1 Complete`.

La passe complète demande l'administrateur. Sans ces droits, le script copie `sante.ps1` dans `$env:TEMP`, retire la marque du Web (`Unblock-File`) et se relance avec `Start-Process powershell.exe -Verb RunAs -File`. Si la demande est annulée, les contrôles qui exigent l'administrateur restent `NonExécuté`.

## Résultat

Un objet par contrôle, affiché en tableau :

| Propriété | Contenu |
|---|---|
| `Controle` | Nom stable du contrôle |
| `Etat` | `OK`, `Attention`, `Erreur` ou `NonExécuté` |
| `Message` | La trace lue, ou la raison pour laquelle le contrôle n'a pas tourné |

`OK` veut dire que la lecture a eu lieu et que rien d'anormal n'y figure. Le code de sortie du processus n'est pas utilisé. L'objet `Récapitulatif` porte le pire état, dans l'ordre `OK` < `Attention` < `Erreur`. `NonExécuté` ne relève pas cet ordre et reste visible dans le tableau. Quand aucun contrôle n'est en `Erreur`, le résumé ajoute : `Un rapport sans trace n'innocente pas le matériel.`

Un contrôle qui exige l'administrateur et qui n'a pas pu tourner est `NonExécuté`. Il n'est jamais `OK`.

## Passe rapide

Lecture seule, en moins d'une minute. Elle tourne sans administrateur, sauf `CheckHealth`.

- **Identité** : modèle, BIOS, version de Windows, uptime. Lecture réussie : `OK`. Lecture vide : `NonExécuté`.
- **Disque** : espace libre par volume. Moins de 10 % libre, ou moins de 20 Go sur le volume système : `Attention`. Moins de 5 % : `Erreur`. Le seuil de 20 Go ne s'applique pas aux autres volumes. Moins de 5 % l'emporte sur le seuil de 20 Go.
- **Batterie** : charge, et usure = 1 − capacité pleine / capacité prévue. Usure supérieure à 20 % : `Attention`. Supérieure à 40 %, ou charge impossible (capacité pleine nulle alors que la capacité prévue est connue, ou charge illisible) : `Erreur`. Aucune batterie : `NonExécuté`, message `aucune batterie`.
- **Périphériques** : codes 10, 28, 31, 39 et 43 : `Erreur`. Code 22 : `Attention`. Un autre code non nul, ou un statut Error ou Degraded : `Attention`.
- **Pilotes** : version, date, éditeur et fichier `.sys` pour chaque appareil en défaut. L'état suit le périphérique. Une date ancienne seule ne change pas l'état.
- **Services** : démarrage Automatique arrêté : `Attention`. Manual et Automatique différé sont ignorés.
- **Journal** : System et Application, Critique et Erreur, 48 heures. Rien : `OK`. Au moins une Erreur et aucune Critique : `Attention`. Au moins une Critique : `Erreur`.
- **Defender** : moteur, signatures, protection temps réel, âge du dernier scan. Temps réel inactif ou signatures de plus de 7 jours : `Attention`. L'âge du scan est cité, il n'est pas noté.
- **SecureBoot** : désactivé : `Attention`.
- **CheckHealth** : `Healthy` est `OK` et le message dit que le magasin n'a pas été parcouru. `Repairable` ou `NonRepairable` : `Erreur`. Administrateur requis.
- **Redémarrage** : clé `RebootPending` ou `SessionsPending` : `Attention`, libellé `redémarrage en attente`.
- **ÉchecsPaquets** : journal Setup, fournisseur `Microsoft-Windows-Servicing`, événement 3, 14 jours. Chaque événement est une `Erreur`, avec le nom du paquet et le HRESULT.

## Passe complète

Tout ce qui précède, plus les lectures suivantes. Plusieurs minutes. Administrateur requis pour l'ensemble. Les contrôles qui lisent le magasin, `sfc`, les paquets en ligne ou les compteurs de fiabilité refusent de répondre `OK` sans droits.

- **CompteursDisque** : usure, température, erreurs de lecture et d'écriture, échec prédit (`HealthStatus` Unhealthy). Erreur non corrigée ou échec prédit : `Erreur`. Usure SMART supérieure à 80 % : `Attention`. La température est citée, elle n'est pas notée.
- **JournalDisque** : fournisseurs NTFS, `disk`, `stornvme`, `storahci`, niveaux Critique et Erreur, 14 jours. Au moins un événement : `Erreur`.
- **WHEA** : `Microsoft-Windows-WHEA-Logger`, 30 jours. Rien : `OK`. Erreur corrigée : `Attention`. Erreur non corrigée, message fatal, ou niveau Critique : `Erreur`.
- **Arrêts** : `Kernel-Power` 41, `WER-SystemErrorReporting` 1001, minidumps de `C:\Windows\Minidump`, 30 jours. Un seul 41, sans écran bleu ni minidump : `Attention`. Un écran bleu, un minidump, ou plusieurs 41 : `Erreur`. Si le message contient un `.sys` ou un code `0xD1`, `0x9F`, `0x116`, `0x124`, `0x9C`, `0x1A`, le texte le cite.
- **PiloteGraphique** : Display 4101 et `LiveKernelEvent` 141, comptés ensemble, 30 jours. Une occurrence : `Attention`. Deux ou plus : `Erreur`.
- **PiloteNonChargé** : `Kernel-PnP` 219, `Service Control Manager` 7000 ou 7026, 14 jours : `Erreur`.
- **PiloteBloqué** : journal `Microsoft-Windows-CodeIntegrity/Operational`, événements 3033, 3034, 3076, 3077 et 3089, 30 jours : `Erreur`. Les autres événements de ce journal ne sont pas des blocages.
- **Fiabilité** : indice le plus récent. Inférieur à 5 : `Attention`.
- **Températures** : une sonde ou un ventilateur exploitable : `OK`. Aucune sonde exploitable : `NonExécuté`, message `aucune sonde exposée`. Ce n'est pas un défaut, et il n'y a pas de seuil.
- **ScanHealth** : même barème que `CheckHealth`. `Healthy` précise que le magasin a été parcouru.
- **FichiersProtégés** : `sfc /verifyonly`. Le verdict est le texte de la commande (sortie et ajout du journal CBS), pas son code de sortie. Violation : `Erreur`.
- **ÉtatPaquets** : `Superseded` est ignoré. `PartiallyInstalled` : `Erreur`. `InstallPending` ou `UninstallPending` sans redémarrage en attente : `Erreur`. Avec redémarrage en attente : `Attention`.
- **RapportBatterie** : `powercfg /batteryreport`. Le chemin du HTML est dans le message.

## Codes HRESULT

Le message reprend le code numérique. Le libellé l'accompagne quand il est connu.

| Code | Libellé |
|---|---|
| `0x80073712` | Magasin de composants incohérent |
| `0x800f0831` | Magasin CBS corrompu |
| `0x800f081f` | Fichiers sources introuvables |
| `0x80073701` | Composant manquant |
| `0x800736CC` | Empreinte de fichier différente du manifeste |
| `0x800f0830` | Image plus réparable par l'entretien |
| `0x800f0982` à `0x800f0988` | Échec d'un delta de mise à jour cumulative |

## Hors périmètre

- Pas de `RestoreHealth`, pas de `sfc /scannow`, pas de `Repair-AppxPackage`, pas de réinitialisation de Windows Update.
- Pas de test de mémoire, de charge CPU ou GPU, ni de lecture des températures réelles du Core Ultra ou de l'Arc.
- Pas de pilote « trop ancien » sans appareil en défaut.
- Un paquet `Superseded` n'est pas un défaut.
- Un rapport sans trace n'innocente pas le matériel.

## Fichiers

`tools/update-hash.ps1` recalcule `sante.ps1.sha256` après une modification de `sante.ps1`. `.gitattributes` fige les octets de `sante.ps1` et de l'empreinte (`-text`), pour que l'empreinte publiée reste celle des octets servis.
