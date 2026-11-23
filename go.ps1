# Santé PC 1.1.0
# Télécharge sante.ps1 v1.1.0, vérifie l'empreinte figée, puis exécute.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
$u = 'https://raw.githubusercontent.com/eraldinho/sante-pc/v1.1.0/sante.ps1'
$attendu = 'A0196A8BD02D4A7FF7A9D7CE7BE6A9367824EC320C61BECDFDD4A848BD466AF0'
$bytes = (New-Object Net.WebClient).DownloadData($u)
$obtenu = (Get-FileHash -InputStream ([IO.MemoryStream]::new($bytes)) -Algorithm SHA256).Hash
if ($obtenu -ne $attendu) { throw "Empreinte inattendue" }
iex ([Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF))
