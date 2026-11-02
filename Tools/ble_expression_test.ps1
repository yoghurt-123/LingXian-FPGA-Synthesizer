param(
  [string]$Port = "COM5",
  [int]$Baud = 115200
)
$ErrorActionPreference = "Stop"
$port = New-Object System.IO.Ports.SerialPort $Port,$Baud,None,8,one
$port.NewLine = "`n"
$port.ReadTimeout = 2000
$port.Open()
Start-Sleep -Milliseconds 800
$commands = @(
  "TEST HELP",
  "TEST GTR 0 3 12",
  "TEST GTRM 0 5 15",
  "TEST CHS 0",
  "TEST CHT 15",
  "TEST OCT 2",
  "TEST NOTE 0 15",
  "TEST OFF 0",
  "TEST BEND 1",
  "TEST VIB 1",
  "TEST GLIDE 1",
  "TEST SLIDE 10",
  "TEST OD 1",
  "TEST REV 1",
  "TEST DAMP 1",
  "TEST REL",
  "TEST CAPS"
)
foreach ($c in $commands) {
  $port.WriteLine($c)
  Start-Sleep -Milliseconds 120
  try { Write-Output $port.ReadExisting() } catch {}
}
$port.Close()
