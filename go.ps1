# Santé PC 1.2.0
# Télécharge sante.ps1 v1.2.0, vérifie l'empreinte figée, puis exécute.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
$u = 'https://raw.githubusercontent.com/eraldinho/sante-pc/v1.2.0/sante.ps1'
$attendu = '57AD13B71B8FC18FA516709908BF912616EC3429A17C11F979D59249AABC480E'
$bytes = (New-Object Net.WebClient).DownloadData($u)
$obtenu = (Get-FileHash -InputStream ([IO.MemoryStream]::new($bytes)) -Algorithm SHA256).Hash
if ($obtenu -ne $attendu) { throw "Empreinte inattendue" }
iex ([Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF))
