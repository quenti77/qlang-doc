--" Readable names of the actions written in the journal, by key. A key without a name is shown as it is. --"
let ACTION_LABELS: map<string, string> = {
    "account.create": "Compte créé",
    "account.delete": "Compte supprimé",
    "account.login": "Connexion",
    "account.password": "Mot de passe changé",
    "folder.create": "Dossier créé",
    "folder.delete": "Dossier supprimé",
    "folder.move": "Dossier déplacé",
    "folder.section": "Section du dossier changée",
    "folder.update": "Dossier modifié",
    "package.add": "Paquet ajouté",
    "package.approve": "Paquet approuvé",
    "package.delete": "Paquet supprimé",
    "package.reject": "Paquet refusé",
    "package.remove": "Paquet retiré",
    "package.restore": "Paquet rétabli",
    "package.sync": "Paquet synchronisé",
    "package.sync_failed": "Synchronisation en échec",
    "package.unyank": "Version rétablie",
    "package.yank": "Version retirée",
    "page.delete": "Page supprimée",
    "page.edit": "Page modifiée",
    "page.import": "Page importée",
    "page.move": "Page déplacée",
    "page.rename": "Page renommée",
    "page.restore": "Page restaurée",
    "release.create": "Version créée",
    "release.delete": "Version supprimée",
    "release.publish": "Version publiée",
    "release.restore": "Version rétablie dans la copie de travail",
    "release.rollback": "Retour à une version antérieure",
    "release.unpublish": "Documentation dépubliée",
}

fun action_label(key: string) -> string
    ACTION_LABELS[key] ?? key
end

export action_label
