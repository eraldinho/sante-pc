# Journal

## v1.1.0

- Envoi optionnel du rapport vers la console Santé PC. Sans jeton, la passe reste locale, comme en 1.0.0.
- Fichier JSON dans le dossier temporaire, sans jeton. Le nom d'ordinateur, le nom d'utilisateur, le numéro de série et l'UUID ne partent pas en clair.
- `machineId` est une empreinte SHA-256. Un identifiant illisible est marqué peu stable.

## v1.0.1

- Ajout de `go.ps1` : une ligne de lancement qui vérifie l'empreinte figée de `sante.ps1` v1.0.0 avant l'exécution.
- `sante.ps1` et son empreinte sont inchangés.

## v1.0.0

- Première version : passe rapide et passe complète, lecture seule.
- Un objet par contrôle (`Controle`, `Etat`, `Message`) et un récapitulatif du pire état.
- Empreinte publiée dans `sante.ps1.sha256`.
- Barèmes décrits dans le README.
