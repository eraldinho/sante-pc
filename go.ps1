# Santé PC 1.1.1
# Télécharge sante.ps1 v1.1.1, vérifie l'empreinte figée, puis exécute.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
$u = 'https://raw.githubusercontent.com/eraldinho/sante-pc/v1.1.1/sante.ps1'
$attendu = '3FEC2200E93A0C40A81F2CA7F2CED4515980C94D52DDEF802AEABDC7D2EF9858'
$bytes = (New-Object Net.WebClient).DownloadData($u)
$obtenu = (Get-FileHash -InputStream ([IO.MemoryStream]::new($bytes)) -Algorithm SHA256).Hash
if ($obtenu -ne $attendu) { throw "Empreinte inattendue" }
iex ([Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF))
