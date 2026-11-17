# Santé PC 1.0.1
# Télécharge sante.ps1 v1.0.0, vérifie l'empreinte figée, puis exécute.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
$u = 'https://raw.githubusercontent.com/eraldinho/sante-pc/v1.0.0/sante.ps1'
$attendu = 'CD2210EBD7B3EB0A1D1BF414438F35A632AD526DBE3BF75BA507322BCAEF96D7'
$bytes = (New-Object Net.WebClient).DownloadData($u)
$obtenu = (Get-FileHash -InputStream ([IO.MemoryStream]::new($bytes)) -Algorithm SHA256).Hash
if ($obtenu -ne $attendu) { throw "Empreinte inattendue" }
iex ([Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF))
