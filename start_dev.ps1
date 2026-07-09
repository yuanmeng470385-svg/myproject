# 健康小云 — 一键启动开发环境
#cd D:\gongsi\app
# 用法: .\start_dev.ps1          # 启动全部
#       .\start_dev.ps1 -Backend  # 仅启动后端
#       .\start_dev.ps1 -Frontend # 仅启动前端
#       .\start_dev.ps1 -Build    # 启动前先 flutter pub get + pip install

param(
    [switch]$Backend,
    [switch]$Frontend,
    [switch]$Build,
    [int]$BackendPort = 8002
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = Join-Path $projectRoot "backend"
$flutterDir = Join-Path $projectRoot "health_xiaohe"

$startAll = -not ($Backend -or $Frontend)

Write-Host ""
Write-Host "╔════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   健康小云 开发环境启动器     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 检查依赖
# ============================================================
Write-Host "[1/4] 检查环境..." -ForegroundColor Yellow

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command python3 -ErrorAction SilentlyContinue
}
if (-not $python) {
    Write-Host "  ✗ 未找到 Python，请安装 Python ≥ 3.10" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Python $((python --version 2>&1) -replace 'Python ','')" -ForegroundColor Green

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    Write-Host "  ✗ 未找到 Flutter，请安装 Flutter SDK ≥ 3.11" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ $(flutter --version 2>&1 | Select-Object -First 1)" -ForegroundColor Green

# ============================================================
# 可选：构建依赖
# ============================================================
if ($Build) {
    Write-Host ""
    Write-Host "  安装依赖..." -ForegroundColor Yellow

    Push-Location $backendDir
    pip install -r requirements.txt -q 2>&1 | Out-Null
    Write-Host "  ✓ pip install 完成" -ForegroundColor Green
    Pop-Location

    Push-Location $flutterDir
    flutter pub get 2>&1 | Out-Null
    Write-Host "  ✓ flutter pub get 完成" -ForegroundColor Green
    Pop-Location
}

# ============================================================
# 检查端口占用
# ============================================================
function Test-PortInUse {
    param([int]$Port)
    $conn = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    return $conn -ne $null
}

# ============================================================
# 启动后端
# ============================================================
if ($startAll -or $Backend) {
    Write-Host ""
    Write-Host "[2/4] 启动后端..." -ForegroundColor Yellow

    if (Test-PortInUse -Port $BackendPort) {
        Write-Host "  ⚠ 端口 $BackendPort 已被占用，跳过后端启动" -ForegroundColor Yellow
        Write-Host "  （如果旧进程已僵死，手动 kill: Stop-Process -Id (Get-NetTCPConnection -LocalPort $BackendPort).OwningProcess）" -ForegroundColor DarkGray
    }
    else {
        if (-not (Test-Path (Join-Path $backendDir ".env"))) {
            Write-Host "  ✗ 未找到 backend/.env，请先配置环境变量" -ForegroundColor Red
            Write-Host "  参考: docs/README.md" -ForegroundColor DarkGray
            exit 1
        }

        $backendJob = Start-Job -Name "health-xiaohe-backend" -ArgumentList $backendDir, $BackendPort {
            param($dir, $port)
            Set-Location $dir
            python -m uvicorn main:app --reload --host 0.0.0.0 --port $port 2>&1
        }
        Write-Host "  ✓ 后端进程已启动 (PID: $($backendJob.Id))" -ForegroundColor Green

        # 等待后端就绪
        $ready = $false
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 1
            try {
                $response = Invoke-WebRequest -Uri "http://localhost:$BackendPort/health" -UseBasicParsing -TimeoutSec 2
                if ($response.StatusCode -eq 200) {
                    Write-Host "  ✓ 后端就绪: http://localhost:$BackendPort" -ForegroundColor Green
                    $ready = $true
                    break
                }
            }
            catch {
                # 继续等待
            }
        }
        if (-not $ready) {
            Write-Host "  ✗ 后端启动超时，请检查 backend/.env 配置" -ForegroundColor Red
        }
    }
}

# ============================================================
# 启动前端
# ============================================================
if ($startAll -or $Frontend) {
    Write-Host ""
    Write-Host "[3/4] 启动 Flutter Web..." -ForegroundColor Yellow

    Push-Location $flutterDir

    # Flutter run -d chrome 会阻塞，所以用 Start-Process 或 Job 跑
    $flutterJob = Start-Job -Name "health-xiaohe-flutter" -ArgumentList $flutterDir {
        param($dir)
        Set-Location $dir
        flutter run -d chrome 2>&1
    }

    Write-Host "  ✓ Flutter 编译中 (首次约 30-60s)..." -ForegroundColor Green

    # 等 Flutter 编译完成 — 看输出里出现 debug service URL
    $ready = $false
    for ($i = 0; $i -lt 120; $i++) {
        Start-Sleep -Seconds 2
        $output = Receive-Job $flutterJob 2>$null | Out-String
        if ($output -match "Flutter run key commands" -or $output -match "Debug service listening") {
            Write-Host "  ✓ Flutter 已启动 — Chrome 窗口即将弹出" -ForegroundColor Green
            $ready = $true
            break
        }
    }
    if (-not $ready) {
        Write-Host "  ✗ Flutter 启动超时，请手动检查" -ForegroundColor Red
    }

    Pop-Location
}

# ============================================================
# 完成
# ============================================================
Write-Host ""
Write-Host "[4/4] 启动完成!" -ForegroundColor Green
Write-Host ""

if ($startAll -or $Backend) {
    Write-Host "  后端 API:      http://localhost:$BackendPort" -ForegroundColor Cyan
    Write-Host "  健康检查:      http://localhost:$BackendPort/health" -ForegroundColor DarkGray
    Write-Host "  API 文档:      http://localhost:$BackendPort/docs" -ForegroundColor DarkGray
}
if ($startAll -or $Frontend) {
    Write-Host "  Flutter Web:   (Chrome 自动打开)" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "  停止服务:      Get-Job | Stop-Job; Get-Job | Remove-Job" -ForegroundColor DarkGray
Write-Host "  查看后端日志:  Receive-Job -Name 'health-xiaohe-backend'" -ForegroundColor DarkGray
Write-Host "  查看 Flutter日志: Receive-Job -Name 'health-xiaohe-flutter'" -ForegroundColor DarkGray
Write-Host ""
