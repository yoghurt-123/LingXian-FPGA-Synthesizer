param(
  [string]$Source = (Join-Path $PSScriptRoot "fpga_uart_bridge.ino"),
  [string]$Build = (Join-Path $PSScriptRoot "build")
)
$ErrorActionPreference = "Stop"
$builder = "D:\Arduino\arduino-builder.exe"
$log = Join-Path $Build "compile.log"
if (Test-Path $Build) { Remove-Item $Build -Recurse -Force }
New-Item -ItemType Directory -Force $Build | Out-Null
& $builder -compile -logger=machine `
  -hardware "D:\Arduino\hardware" `
  -hardware "C:\Users\youger.com\AppData\Local\Temp\opencode\arduino_hw" `
  -hardware "C:\Users\youger.com\AppData\Local\Arduino15\packages\esp32\hardware" `
  -tools "D:\Arduino\tools-builder" `
  -tools "C:\Users\youger.com\AppData\Local\Arduino15\packages\esp32\tools" `
  -tools "C:\Users\youger.com\AppData\Local\Arduino15\packages\arduino\tools" `
  -built-in-libraries "D:\Arduino\libraries" `
  -fqbn "esp32:esp32:esp32c3:CDCOnBoot=cdc" `
  -build-path $Build -warnings=all $Source *> $log
if ($LASTEXITCODE -ne 0) { Get-Content $log | Select-Object -Last 30; throw "ESP build failed" }
Get-Content $log | Select-Object -Last 5
