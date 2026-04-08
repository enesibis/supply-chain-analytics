@echo off
:: SCM_3 - Snapshot Yenileme
:: Her gece otomatik çalışır, snap_ tablolarını günceller

sqlcmd -S "ENES\SQLEXPRESS" -d SCM_3 -Q "EXEC dbo.sp_RefreshAllSnapshots" -b

if %ERRORLEVEL% NEQ 0 (
    echo [%date% %time%] HATA: Snapshot yenileme basarisiz. >> "%~dp0refresh_log.txt"
    exit /b 1
)

echo [%date% %time%] Snapshot yenileme tamamlandi. >> "%~dp0refresh_log.txt"
