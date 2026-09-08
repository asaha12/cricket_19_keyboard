@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem BRAC MT942 RPT Generator - Windows
rem ============================================================

echo.
echo ==========================================
echo        BRAC MT942 RPT FILE GENERATOR
echo ==========================================
echo.

:TYPE
set "TXN_TYPE="
set /p "TXN_TYPE=Enter Transaction Type (D/C): "

if /I "%TXN_TYPE%"=="D" (
    set "TXN_TYPE=D"
    goto AMOUNT
)

if /I "%TXN_TYPE%"=="C" (
    set "TXN_TYPE=C"
    goto AMOUNT
)

echo Invalid input. Please type only D or C.
goto TYPE

:AMOUNT
set "AMOUNT="
set /p "AMOUNT=Enter Amount (whole number only): "

if not defined AMOUNT (
    echo Invalid amount. Please enter a valid number.
    goto AMOUNT
)

rem Validate digits only.
echo(%AMOUNT%| %SystemRoot%\System32\findstr.exe /R /X "[0-9][0-9]*" >nul
if errorlevel 1 (
    echo Invalid amount. Please enter numbers only, without decimal point or letters.
    goto AMOUNT
)

:TNX
set "TNX="
set /p "TNX=Enter TNX Number: "

if not defined TNX (
    echo Invalid TNX number. Please enter a value.
    goto TNX
)

rem Get local system date/time.
rem WMIC is used first for compatibility with older Windows.
for /f "tokens=2 delims==" %%A in ('wmic os get LocalDateTime /value 2^>nul') do if not defined LDT set "LDT=%%A"

if defined LDT (
    set "YY=!LDT:~2,2!"
    set "MM=!LDT:~4,2!"
    set "DD=!LDT:~6,2!"
    set "HH=!LDT:~8,2!"
    set "MIN=!LDT:~10,2!"
    set "FILESTAMP=!LDT:~0,14!"
) else (
    rem Fallback when WMIC is unavailable.
    for /f "usebackq tokens=1-6" %%A in (`powershell -NoProfile -Command "(Get-Date).ToString('yy MM dd HH mm yyyyMMddHHmmss')"`) do (
        set "YY=%%A"
        set "MM=%%B"
        set "DD=%%C"
        set "HH=%%D"
        set "MIN=%%E"
        set "FILESTAMP=%%F"
    )
)

rem :61: date format = YYMMDDMMDD (year, month, day, month, day). Time is NOT used here.
set "DATESTAMP=!YY!!MM!!DD!!MM!!DD!"
set "FILENAME=BRACBD02.PAYMENTS.!FILESTAMP!.1049.MT942.rpt"
set "OUTPUT=%CD%\!FILENAME!"

(
echo {1:F01SCBLBDDXXXXX3234100042}{2:O9421232241202SCBLBDDXXXXX32341000422412021232N}{3:{108:00000000003880}}{4:
echo :20:24120205fr150001
echo :25:01600028203BDT
echo :28C:42/1
echo :34F:BDT0,
echo :13D:2412021232+0800
echo :61:!DATESTAMP!!TXN_TYPE!T!AMOUNT!,00N508!TNX!//
echo !TNX!
echo :86:D02564C00004720001-!TNX!
echo SB9999241202FX12
echo DDX2262450000030
echo :61:2412021202DT9600,00N208NONREF          //
echo :86:IL99992412020012
echo BRAC BANK PLC
echo BRAKBDDHXXX
echo BRA2412020007469
echo :61:2412021202CT100000,00N208NONREF          //
echo :86:IL99992412020014
echo BRAC BANK PLC
echo BRAKBDDHXXX
echo BRA2412020007470
echo -}{5:{CHK:CHECKSUM DISABLED}{MAC:MACCING DISABLED}}
) > "!OUTPUT!"

echo.
echo ==========================================
echo File generated successfully:
echo !OUTPUT!
echo ==========================================
echo.
pause
endlocal
